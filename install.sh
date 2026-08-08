#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
HERMES_DIR="$ROOT_DIR/data/hermes"
OMNIROUTE_DIR="$ROOT_DIR/data/omniroute"
OPENWEBUI_DIR="$ROOT_DIR/data/open-webui"
N8N_DIR="$ROOT_DIR/data/n8n"
CADDY_DIR="$ROOT_DIR/data/caddy"
EXEC_DIR="$ROOT_DIR/data/stack-secrets/execution"
DRY_RUN=false
NO_START=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --no-start) NO_START=true ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./install.sh [--dry-run] [--no-start]

Interactive installer for Hermes + OmniRoute + optional Smart Router/Open WebUI/n8n/Caddy.
--dry-run   collect answers and print the planned profiles without writing files
--no-start  write configuration but do not run docker compose up
USAGE
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

prompt() {
  local label="$1" default="${2-}" value
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "$label: " value
    printf '%s' "$value"
  fi
}

prompt_secret() {
  local label="$1" allow_empty="${2:-false}" value
  while true; do
    read -r -s -p "$label: " value
    printf '\n' >&2
    if [[ -n "$value" || "$allow_empty" == true ]]; then
      printf '%s' "$value"
      return
    fi
    warn "A value is required." >&2
  done
}

confirm() {
  local label="$1" default="${2:-n}" answer suffix
  [[ "$default" == y ]] && suffix="Y/n" || suffix="y/N"
  read -r -p "$label [$suffix]: " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "${1:-32}"
  else
    od -An -N "${1:-32}" -tx1 /dev/urandom | tr -d ' \n'
  fi
}

dotenv_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\$\$}"
  printf '"%s"' "$value"
}

yaml_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 )); }
valid_ids() { [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]]; }
valid_domain() { [[ ${#1} -le 253 && "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }

ask_port() {
  local label="$1" default="$2" value
  while true; do
    value="$(prompt "$label" "$default")"
    valid_port "$value" && { printf '%s' "$value"; return; }
    warn "Enter a port from 1 to 65535." >&2
  done
}

ask_domain_optional() {
  local label="$1" value
  while true; do
    value="$(prompt "$label")"
    value="${value,,}"
    [[ -z "$value" ]] && { printf ''; return; }
    valid_domain "$value" && { printf '%s' "$value"; return; }
    warn "Enter a hostname such as ai.example.com, or leave blank." >&2
  done
}

existing_env_value() {
  local key="$1" file="${2:-$ENV_FILE}" line value
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" | tail -n1 || true)"
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then value="${value:1:${#value}-2}"; fi
  printf '%s' "$value"
}

compose_detect() {
  command -v docker >/dev/null 2>&1 || die "Docker Engine is required. Install Docker and the Compose plugin first."
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is required (docker compose)."
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    die "Docker is installed but the current user cannot access the daemon. Fix Docker permissions or run with a configured sudo session."
  fi
}

cat <<'BANNER'
Hermes Linux Stack — OmniRoute release
--------------------------------------
This installer replaces the legacy router with OmniRoute.
OmniRoute dashboard: port 20128
OmniRoute OpenAI API: port 20129 (private/loopback by default)
BANNER

install_omniroute=true
install_hermes=false
install_webui=false
install_smart=false
install_n8n=false
install_caddy=false

confirm "Install Hermes Agent?" y && install_hermes=true
confirm "Install Open WebUI?" y && install_webui=true
if [[ "$install_hermes" == true || "$install_webui" == true ]]; then
  confirm "Enable the optional Hermes Smart Router?" n && install_smart=true
fi
confirm "Install n8n?" n && install_n8n=true
confirm "Configure Caddy HTTPS reverse proxy?" n && install_caddy=true

omni_bind="$(prompt "OmniRoute dashboard bind IP" "${OMNIROUTE_BIND_IP:-127.0.0.1}")"
omni_port="$(ask_port "OmniRoute dashboard host port" "${OMNIROUTE_PORT:-20128}")"
omni_api_bind="$(prompt "OmniRoute API bind IP" "${OMNIROUTE_API_BIND_IP:-127.0.0.1}")"
omni_api_port="$(ask_port "OmniRoute API host port" "${OMNIROUTE_API_PORT:-20129}")"
[[ "$omni_port" != "$omni_api_port" ]] || die "Dashboard and API host ports must be different in split-port mode."

existing_password="$(existing_env_value OMNIROUTE_INITIAL_PASSWORD)"
if [[ -n "$existing_password" ]]; then
  omni_password="$existing_password"
  info "Reusing the existing OmniRoute initial password from .env."
else
  omni_password="$(prompt_secret "Choose the initial OmniRoute dashboard password")"
fi

omni_endpoint_key="omniroute-internal"
omni_require_key=false
if confirm "Already have an OmniRoute endpoint API key and require it now?" n; then
  omni_endpoint_key="$(prompt_secret "Existing OmniRoute endpoint API key")"
  omni_require_key=true
fi

model_name="$(prompt "Hermes default OmniRoute model/route" "auto")"
telegram_token=""
telegram_ids=""
telegram_home=""
if [[ "$install_hermes" == true ]]; then
  old_token="$(existing_env_value TELEGRAM_BOT_TOKEN "$HERMES_DIR/.env")"
  old_ids="$(existing_env_value TELEGRAM_ALLOWED_USERS "$HERMES_DIR/.env")"
  if [[ -n "$old_token" ]]; then
    telegram_token="$old_token"
    info "Reusing existing Hermes Telegram bot token."
  else
    telegram_token="$(prompt_secret "Telegram bot token")"
  fi
  while true; do
    telegram_ids="$(prompt "Telegram allowed user IDs (comma separated)" "${old_ids:-}")"
    valid_ids "$telegram_ids" && break
    warn "Enter one or more numeric Telegram user IDs, e.g. 123456789,987654321."
  done
  telegram_home="$(prompt "Telegram home channel ID (optional)" "$(existing_env_value TELEGRAM_HOME_CHANNEL "$HERMES_DIR/.env")")"
fi

openwebui_signup=true
if [[ "$install_webui" == true ]]; then
  confirm "Allow Open WebUI user signup?" y || openwebui_signup=false
fi

n8n_tz="UTC"
if [[ "$install_n8n" == true ]]; then
  n8n_tz="$(prompt "n8n timezone" "${TZ:-UTC}")"
fi

omni_domain=""; webui_domain=""; n8n_domain=""
if [[ "$install_caddy" == true ]]; then
  info "Enter only domains that already resolve to this server. Leave unused services blank."
  omni_domain="$(ask_domain_optional "OmniRoute domain")"
  [[ "$install_webui" == true ]] && webui_domain="$(ask_domain_optional "Open WebUI domain")"
  [[ "$install_n8n" == true ]] && n8n_domain="$(ask_domain_optional "n8n domain")"
  if [[ -z "$omni_domain$webui_domain$n8n_domain" ]]; then
    warn "No Caddy domains supplied; disabling Caddy profile."
    install_caddy=false
  fi
fi

profiles=(omniroute)
[[ "$install_smart" == true ]] && profiles+=(smart-router)
[[ "$install_hermes" == true ]] && profiles+=(hermes)
[[ "$install_webui" == true ]] && profiles+=(open-webui)
[[ "$install_n8n" == true ]] && profiles+=(n8n)
[[ "$install_caddy" == true ]] && profiles+=(caddy)
profiles_csv="$(IFS=,; printf '%s' "${profiles[*]}")"

provider_url="http://omniroute:20129/v1"
[[ "$install_smart" == true ]] && provider_url="http://smart-router:8080/v1"

printf '\nSelected profiles: %s\n' "$profiles_csv"
printf 'Hermes/Open WebUI upstream: %s\n' "$provider_url"
if [[ "$DRY_RUN" == true ]]; then
  ok "Dry run complete; no files were changed."
  exit 0
fi

compose_detect
mkdir -p "$OMNIROUTE_DIR" "$HERMES_DIR" "$OPENWEBUI_DIR" "$N8N_DIR" \
  "$CADDY_DIR/data" "$CADDY_DIR/config" "$ROOT_DIR/data/smart-router" \
  "$EXEC_DIR/docker-state" "$EXEC_DIR/ssh-state" "$EXEC_DIR/approver-state" "$EXEC_DIR/ssh" \
  "$ROOT_DIR/data/execution-workspace"

# Base execution files are required as bind-mount sources even when execution profiles stay off.
if [[ ! -s "$EXEC_DIR/control-secret" ]]; then random_hex 32 > "$EXEC_DIR/control-secret"; fi
: > "$EXEC_DIR/users"
chmod 600 "$EXEC_DIR/control-secret" "$EXEC_DIR/users" || true

jwt_secret="$(existing_env_value OMNIROUTE_JWT_SECRET)"; jwt_secret="${jwt_secret:-$(random_hex 32)}"
api_key_secret="$(existing_env_value OMNIROUTE_API_KEY_SECRET)"; api_key_secret="${api_key_secret:-$(random_hex 32)}"
storage_key="$(existing_env_value OMNIROUTE_STORAGE_ENCRYPTION_KEY)"; storage_key="${storage_key:-$(random_hex 32)}"
machine_salt="$(existing_env_value OMNIROUTE_MACHINE_ID_SALT)"; machine_salt="${machine_salt:-$(random_hex 32)}"
ws_bridge_secret="$(existing_env_value OMNIROUTE_WS_BRIDGE_SECRET)"; ws_bridge_secret="${ws_bridge_secret:-$(random_hex 32)}"
smart_secret="$(existing_env_value SMART_ROUTER_HMAC_SECRET)"; smart_secret="${smart_secret:-$(random_hex 32)}"
webui_secret="$(existing_env_value OPENWEBUI_SECRET_KEY)"; webui_secret="${webui_secret:-$(random_hex 32)}"
n8n_key="$(existing_env_value N8N_ENCRYPTION_KEY)"; n8n_key="${n8n_key:-$(random_hex 32)}"
hermes_uid="$(id -u)"; hermes_gid="$(id -g)"
[[ "$hermes_uid" == 0 ]] && hermes_uid=10000
[[ "$hermes_gid" == 0 ]] && hermes_gid=10000

omni_public="http://localhost:$omni_port"
omni_cookie=false
[[ -n "$omni_domain" ]] && { omni_public="https://$omni_domain"; omni_cookie=true; }
webui_url="http://localhost:3000"
[[ -n "$webui_domain" ]] && webui_url="https://$webui_domain"
n8n_url="http://localhost:5678"; n8n_protocol=http; n8n_host=localhost; n8n_cookie=false; n8n_hops=0
[[ -n "$n8n_domain" ]] && { n8n_url="https://$n8n_domain"; n8n_protocol=https; n8n_host="$n8n_domain"; n8n_cookie=true; n8n_hops=1; }

[[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
cat > "$ENV_FILE" <<EOF_ENV
COMPOSE_PROFILES=$profiles_csv

OMNIROUTE_IMAGE=diegosouzapw/omniroute:latest
OMNIROUTE_BIND_IP=$omni_bind
OMNIROUTE_PORT=$omni_port
OMNIROUTE_API_BIND_IP=$omni_api_bind
OMNIROUTE_API_PORT=$omni_api_port
OMNIROUTE_INITIAL_PASSWORD=$(dotenv_quote "$omni_password")
OMNIROUTE_JWT_SECRET=$(dotenv_quote "$jwt_secret")
OMNIROUTE_API_KEY_SECRET=$(dotenv_quote "$api_key_secret")
OMNIROUTE_STORAGE_ENCRYPTION_KEY=$(dotenv_quote "$storage_key")
OMNIROUTE_STORAGE_ENCRYPTION_KEY_VERSION=v1
OMNIROUTE_MACHINE_ID_SALT=$(dotenv_quote "$machine_salt")
OMNIROUTE_WS_BRIDGE_SECRET=$(dotenv_quote "$ws_bridge_secret")
OMNIROUTE_REQUIRE_API_KEY=$omni_require_key
OMNIROUTE_AUTH_COOKIE_SECURE=$omni_cookie
OMNIROUTE_PUBLIC_BASE_URL=$omni_public
OMNIROUTE_ALLOW_API_KEY_REVEAL=false
OMNIROUTE_MEMORY_MB=512

HERMES_IMAGE=nousresearch/hermes-agent:latest
HERMES_BIND_IP=127.0.0.1
HERMES_API_PORT=8642
HERMES_DASHBOARD_PORT=9119
HERMES_DASHBOARD=0
HERMES_UID=$hermes_uid
HERMES_GID=$hermes_gid

EXECUTION_FEATURES=
EXECUTION_POLICY_GENERATION=0
EXECUTION_WORKSPACE_GENERATION=0
EXECUTION_BROKER_IMAGE=afsharidevops/hermes-execution-broker:0.1.1@sha256:dc88519c8f87d0720e0666e081dc74cd867ea8d5b019d59af50ac44a72bb55ed
EXECUTION_SANDBOX_IMAGE=python:3.13.5-slim-bookworm@sha256:4c2cf9917bd1cbacc5e9b07320025bdb7cdf2df7b0ceaccb55e9dd7e30987419
EXECUTION_RUN_AS=10003:10003
EXECUTION_DOCKER_GID=999
EXECUTION_WORKSPACE_HOST_PATH=$ROOT_DIR/data/execution-workspace

SMART_ROUTER_IMAGE=afsharidevops/hermes-smart-router:0.1.0@sha256:4290667e8c90940a5dd97bcd6fd1575c0f1b822db507f9cc5076abe126708bef
SMART_ROUTER_MODE=observe
SMART_ROUTER_HMAC_SECRET=$(dotenv_quote "$smart_secret")
SMART_ROUTER_POLICY_VERSION=1
SMART_ROUTER_OBSERVE_MODEL=$model_name
SMART_ROUTER_FAIL_OPEN_MODEL=$model_name
SMART_ROUTER_FAST_MODEL=$model_name
SMART_ROUTER_STANDARD_MODEL=$model_name
SMART_ROUTER_STRONG_MODEL=$model_name
SMART_ROUTER_SESSION_TTL_SECONDS=2700
SMART_ROUTER_MAX_SESSION_AGE_SECONDS=43200
SMART_ROUTER_DEMOTION_TURNS=5
SMART_ROUTER_FAST_MAX_TOKENS=1024
SMART_ROUTER_STANDARD_MAX_TOKENS=4096
SMART_ROUTER_STRONG_MAX_TOKENS=6144
SMART_ROUTER_CONNECT_TIMEOUT_SECONDS=10
SMART_ROUTER_READ_TIMEOUT_SECONDS=600
SMART_ROUTER_MAX_REQUEST_BYTES=10485760

OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
OPENWEBUI_BIND_IP=127.0.0.1
OPENWEBUI_PORT=3000
OPENWEBUI_URL=$webui_url
OPENWEBUI_SECRET_KEY=$(dotenv_quote "$webui_secret")
OPENWEBUI_OPENAI_BASE_URL=$provider_url
OPENWEBUI_OPENAI_API_KEY=$(dotenv_quote "$omni_endpoint_key")
OPENWEBUI_ENABLE_SIGNUP=$openwebui_signup

N8N_IMAGE=n8nio/n8n:latest
N8N_MCP_MODE=off
N8N_BIND_IP=127.0.0.1
N8N_PORT=5678
N8N_HOSTNAME=$n8n_host
N8N_PROTOCOL=$n8n_protocol
N8N_PUBLIC_URL=$n8n_url
N8N_SECURE_COOKIE=$n8n_cookie
N8N_PROXY_HOPS=$n8n_hops
N8N_TIMEZONE=$(dotenv_quote "$n8n_tz")
N8N_DIAGNOSTICS_ENABLED=false
N8N_VERSION_NOTIFICATIONS_ENABLED=false
N8N_ENCRYPTION_KEY=$(dotenv_quote "$n8n_key")

CADDY_IMAGE=caddy:2-alpine
CADDY_BIND_IP=0.0.0.0
EOF_ENV
chmod 600 "$ENV_FILE"

if [[ "$install_hermes" == true ]]; then
  config="$(<"$ROOT_DIR/templates/hermes-config.yaml.template")"
  config="${config//__PROVIDER_ID__/$(yaml_quote 'custom:OmniRoute')}"
  config="${config//__PROVIDER_NAME__/$(yaml_quote 'OmniRoute')}"
  config="${config//__PROVIDER_BASE_URL__/$(yaml_quote "$provider_url")}"
  config="${config//__MODEL_NAME__/$(yaml_quote "$model_name")}"
  config="${config//__MCP_SERVERS_BLOCK__/}"
  printf '%s\n' "$config" > "$HERMES_DIR/config.yaml"
  {
    printf 'TELEGRAM_BOT_TOKEN=%s\n' "$(dotenv_quote "$telegram_token")"
    printf 'TELEGRAM_ALLOWED_USERS=%s\n' "$telegram_ids"
    [[ -n "$telegram_home" ]] && printf 'TELEGRAM_HOME_CHANNEL=%s\n' "$telegram_home"
    printf 'OMNIROUTE_API_KEY=%s\n' "$(dotenv_quote "$omni_endpoint_key")"
    printf 'OMNIROUTE_URL=%s\n' "$(dotenv_quote 'http://omniroute:20129')"
    printf 'API_SERVER_ENABLED=false\n'
  } > "$HERMES_DIR/.env"
  chmod 600 "$HERMES_DIR/.env"
  chmod 640 "$HERMES_DIR/config.yaml"
fi

if [[ "$install_caddy" == true ]]; then
  : > "$CADDY_DIR/Caddyfile"
  if [[ -n "$omni_domain" ]]; then
    cat >> "$CADDY_DIR/Caddyfile" <<EOF_CADDY
$omni_domain {
    @omniroute_api path /v1 /v1/*
    reverse_proxy @omniroute_api omniroute:20129
    reverse_proxy omniroute:20128
}

EOF_CADDY
  fi
  [[ -n "$webui_domain" ]] && cat >> "$CADDY_DIR/Caddyfile" <<EOF_CADDY
$webui_domain {
    reverse_proxy open-webui:8080
}

EOF_CADDY
  [[ -n "$n8n_domain" ]] && cat >> "$CADDY_DIR/Caddyfile" <<EOF_CADDY
$n8n_domain {
    reverse_proxy n8n:5678
}

EOF_CADDY
else
  [[ -f "$CADDY_DIR/Caddyfile" ]] || printf ':80 { respond "Hermes OmniRoute stack: Caddy not configured" 200 }\n' > "$CADDY_DIR/Caddyfile"
fi

info "Validating Compose configuration..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" config >/dev/null
ok "Compose configuration is valid."

if [[ "$NO_START" == true ]]; then
  ok "Configuration written. Start later with ./manage.sh start"
  exit 0
fi

info "Pulling selected images..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" pull
info "Starting selected profiles..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d --remove-orphans

printf '\n'
ok "Stack started."
printf 'OmniRoute dashboard: %s\n' "$omni_public"
printf 'OmniRoute host API: http://%s:%s/v1\n' "$omni_api_bind" "$omni_api_port"
[[ "$install_webui" == true ]] && printf 'Open WebUI: %s\n' "$webui_url"
[[ "$install_n8n" == true ]] && printf 'n8n: %s\n' "$n8n_url"
printf '\nNext: open OmniRoute, add at least one provider, then use model/route %q (or change it).\n' "$model_name"
if [[ "$omni_require_key" == false ]]; then
  printf 'After creating an OmniRoute endpoint API key, run: ./manage.sh enable-omniroute-api-auth\n'
fi
