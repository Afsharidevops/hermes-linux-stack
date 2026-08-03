#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY_URL="${HERMES_STACK_REPOSITORY_URL:-https://github.com/Afsharidevops/hermes-linux-stack.git}"
SOURCE_PATH="${BASH_SOURCE[0]:-}"
SOURCE_DIR="$(cd -- "$(dirname -- "${SOURCE_PATH:-.}")" 2>/dev/null && pwd || pwd)"

# When install.sh is streamed with curl, fetch the complete repository first.
# The real wizard is then executed from the clone with prompts attached to the
# user's terminal instead of the exhausted curl pipe.
if [[ ! -f "$SOURCE_DIR/docker-compose.yml" ]]; then
  command -v git >/dev/null 2>&1 || {
    printf 'git is required. Install git, then run this command again.\n' >&2
    exit 1
  }
  [[ -r /dev/tty ]] || {
    printf 'Interactive installation requires a terminal. Clone the repository and run ./install.sh.\n' >&2
    exit 1
  }

  INSTALL_TARGET="${HERMES_STACK_DIR:-$HOME/hermes-linux-stack}"
  if [[ -d "$INSTALL_TARGET/.git" ]]; then
    printf '[INFO] Updating existing installation in %s\n' "$INSTALL_TARGET"
    git -C "$INSTALL_TARGET" pull --ff-only
  elif [[ -e "$INSTALL_TARGET" ]]; then
    printf 'Target exists but is not a Git repository: %s\n' "$INSTALL_TARGET" >&2
    printf 'Set HERMES_STACK_DIR to another path or move the existing directory.\n' >&2
    exit 1
  else
    printf '[INFO] Cloning into %s\n' "$INSTALL_TARGET"
    git clone --depth 1 "$REPOSITORY_URL" "$INSTALL_TARGET"
  fi

  chmod +x "$INSTALL_TARGET/install.sh" "$INSTALL_TARGET/manage.sh"
  exec "$INSTALL_TARGET/install.sh" "$@" </dev/tty >/dev/tty
fi

ROOT_DIR="$SOURCE_DIR"
ENV_FILE="$ROOT_DIR/.env"
HERMES_DIR="$ROOT_DIR/data/hermes"
NINEROUTER_DIR="$ROOT_DIR/data/9router"
OPENWEBUI_DIR="$ROOT_DIR/data/open-webui"
CADDY_DIR="$ROOT_DIR/data/caddy"
DRY_RUN=false
NO_START=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --no-start) NO_START=true ;;
    -h|--help)
      printf '%s\n' "Usage: ./install.sh [--dry-run] [--no-start]"
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

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
    warn "A value is required."
  done
}

confirm() {
  local label="$1" default="${2:-n}" answer suffix
  if [[ "$default" == y ]]; then suffix="Y/n"; else suffix="y/N"; fi
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

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

valid_ids() {
  [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]]
}

valid_domain() {
  [[ ${#1} -le 253 && "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

prompt_domain() {
  local label="$1" value
  while true; do
    value="$(prompt "$label")"
    value="${value,,}"
    if valid_domain "$value"; then
      printf '%s' "$value"
      return 0
    fi
    warn "Enter a domain only, such as chat.example.com, without https://, a port, or a path." >&2
  done
}

install_docker() {
  command -v curl >/dev/null 2>&1 || die "curl is required to install Docker."
  local installer
  installer="$(mktemp)"
  curl -fsSL https://get.docker.com -o "$installer"
  if [[ "$(id -u)" -eq 0 ]]; then
    sh "$installer"
  elif command -v sudo >/dev/null 2>&1; then
    sudo sh "$installer"
  else
    rm -f "$installer"
    die "Docker installation requires root or sudo."
  fi
  rm -f "$installer"
}

detect_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    confirm "Docker is not installed. Install it using Docker's official installer?" y \
      || die "Install Docker Engine and the Compose plugin, then rerun this script."
    install_docker
  fi
  docker compose version >/dev/null 2>&1 \
    || die "The Docker Compose plugin is required (the command must be 'docker compose')."
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    die "Docker exists but this user cannot access the daemon. Add the user to the docker group or run with sudo."
  fi
}

backup_existing() {
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  [[ -f "$ENV_FILE" ]] && cp -p "$ENV_FILE" "$ENV_FILE.backup-$stamp"
  [[ -f "$HERMES_DIR/.env" ]] && cp -p "$HERMES_DIR/.env" "$HERMES_DIR/.env.backup-$stamp"
  [[ -f "$HERMES_DIR/config.yaml" ]] && cp -p "$HERMES_DIR/config.yaml" "$HERMES_DIR/config.yaml.backup-$stamp"
  [[ -f "$CADDY_DIR/Caddyfile" ]] && cp -p "$CADDY_DIR/Caddyfile" "$CADDY_DIR/Caddyfile.backup-$stamp"
  return 0
}

existing_env_value() {
  local key="$1" value=""
  if [[ -f "$ENV_FILE" ]]; then
    value="$(sed -n "s/^${key}=//p" "$ENV_FILE" | head -n1)"
    value="${value#\"}"
    value="${value%\"}"
  fi
  printf '%s' "$value"
}

existing_hermes_env_value() {
  local key="$1" value=""
  if [[ -f "$HERMES_DIR/.env" ]]; then
    value="$(sed -n "s/^${key}=//p" "$HERMES_DIR/.env" | head -n1)"
    value="${value#\"}"
    value="${value%\"}"
  fi
  printf '%s' "$value"
}

profile_enabled() {
  local profile="$1" configured
  configured="$(existing_env_value COMPOSE_PROFILES)"
  [[ ",$configured," == *",$profile,"* ]]
}

printf '\nHermes + 9router Linux Installer\n'
printf '%s\n' '================================'
configure_nine=false
configure_hermes=false
configure_webui=false
configure_caddy=false
existing_install=false

if [[ -f "$ENV_FILE" ]]; then
  existing_install=true
  install_nine=false; profile_enabled 9router && install_nine=true
  install_hermes=false; profile_enabled hermes && install_hermes=true
  install_webui=false; profile_enabled open-webui && install_webui=true
  install_caddy=false; profile_enabled caddy && install_caddy=true

  printf 'Existing components: %s\n' "$(existing_env_value COMPOSE_PROFILES)"
  printf '%s\n' 'The wizard keeps existing components, secrets, and data by default.'

  if [[ "$install_nine" == true ]]; then
    confirm "Reconfigure existing 9router settings?" n && configure_nine=true
  elif confirm "Add 9router?" n; then
    install_nine=true; configure_nine=true
  fi
  if [[ "$install_hermes" == true ]]; then
    confirm "Reconfigure existing Hermes Agent settings?" n && configure_hermes=true
  elif confirm "Add Hermes Agent?" n; then
    install_hermes=true; configure_hermes=true
  fi
  if [[ "$install_webui" == true ]]; then
    confirm "Reconfigure existing Open WebUI settings?" n && configure_webui=true
  elif confirm "Add Open WebUI?" n; then
    install_webui=true; configure_webui=true
  fi
else
  printf '%s\n' '1) Install both 9router and Hermes Agent (recommended)'
  printf '%s\n' '2) Install 9router only'
  printf '%s\n' '3) Install Hermes Agent only'
  printf '%s\n' '4) Install Open WebUI only'
  selection="$(prompt "Choose installation" "1")"

  case "$selection" in
    1) install_nine=true; install_hermes=true; install_webui=false ;;
    2) install_nine=true; install_hermes=false; install_webui=false ;;
    3) install_nine=false; install_hermes=true; install_webui=false ;;
    4) install_nine=false; install_hermes=false; install_webui=true ;;
    *) die "Choose 1, 2, 3, or 4." ;;
  esac

  if [[ "$selection" != 4 ]] && confirm "Also install Open WebUI?" n; then
    install_webui=true
  fi
  configure_nine="$install_nine"
  configure_hermes="$install_hermes"
  configure_webui="$install_webui"
  install_caddy=false
fi

profiles=""
[[ "$install_nine" == true ]] && profiles="9router"
[[ "$install_hermes" == true ]] && profiles="${profiles:+$profiles,}hermes"
[[ "$install_webui" == true ]] && profiles="${profiles:+$profiles,}open-webui"

mkdir -p "$HERMES_DIR" "$NINEROUTER_DIR" "$OPENWEBUI_DIR" "$CADDY_DIR"
backup_existing

nine_bind="$(existing_env_value NINEROUTER_BIND_IP)"; nine_bind="${nine_bind:-127.0.0.1}"
nine_port="$(existing_env_value NINEROUTER_PORT)"; nine_port="${nine_port:-20128}"
nine_password="$(existing_env_value NINEROUTER_INITIAL_PASSWORD)"; nine_password="${nine_password:-not-installed}"
nine_require_key="$(existing_env_value NINEROUTER_REQUIRE_API_KEY)"; nine_require_key="${nine_require_key:-false}"
nine_cookie_secure="$(existing_env_value NINEROUTER_AUTH_COOKIE_SECURE)"; nine_cookie_secure="${nine_cookie_secure:-false}"
nine_public_url="$(existing_env_value NINEROUTER_PUBLIC_BASE_URL)"; nine_public_url="${nine_public_url:-http://localhost:20128}"
existing_nine_jwt="$(existing_env_value NINEROUTER_JWT_SECRET)"
existing_nine_key_secret="$(existing_env_value NINEROUTER_API_KEY_SECRET)"
existing_nine_salt="$(existing_env_value NINEROUTER_MACHINE_ID_SALT)"
nine_jwt="${existing_nine_jwt:-$(random_hex 32)}"
nine_key_secret="${existing_nine_key_secret:-$(random_hex 32)}"
nine_salt="${existing_nine_salt:-$(random_hex 32)}"

if [[ "$configure_nine" == true ]]; then
  printf '\n9router settings\n'
  printf '%s\n' '----------------'
  nine_bind="$(prompt "Host bind address (127.0.0.1 is safest)" "127.0.0.1")"
  nine_port="$(prompt "Dashboard/API port" "20128")"
  valid_port "$nine_port" || die "Invalid 9router port: $nine_port"
  nine_password="$(prompt_secret "Initial 9router dashboard password")"
  nine_public_url="$(prompt "Public dashboard URL (or local URL)" "http://localhost:$nine_port")"
  if [[ "$nine_public_url" == https://* ]]; then nine_cookie_secure="true"; fi
  if confirm "Require a 9router Bearer API key on /v1 routes?" n; then
    nine_require_key="true"
  fi
fi

openwebui_bind="$(existing_env_value OPENWEBUI_BIND_IP)"; openwebui_bind="${openwebui_bind:-127.0.0.1}"
openwebui_port="$(existing_env_value OPENWEBUI_PORT)"; openwebui_port="${openwebui_port:-3000}"
openwebui_url="$(existing_env_value OPENWEBUI_URL)"; openwebui_url="${openwebui_url:-http://localhost:3000}"
existing_openwebui_secret="$(existing_env_value OPENWEBUI_SECRET_KEY)"
openwebui_secret="${existing_openwebui_secret:-$(random_hex 32)}"
openwebui_api_url="$(existing_env_value OPENWEBUI_OPENAI_BASE_URL)"; openwebui_api_url="${openwebui_api_url:-http://nine-router:20128/v1}"
openwebui_api_key="$(existing_env_value OPENWEBUI_OPENAI_API_KEY)"; openwebui_api_key="${openwebui_api_key:-local-no-auth}"
openwebui_signup="$(existing_env_value OPENWEBUI_ENABLE_SIGNUP)"; openwebui_signup="${openwebui_signup:-true}"

hermes_bind="$(existing_env_value HERMES_BIND_IP)"; hermes_bind="${hermes_bind:-127.0.0.1}"
hermes_api_port="$(existing_env_value HERMES_API_PORT)"; hermes_api_port="${hermes_api_port:-8642}"
hermes_dashboard_port="$(existing_env_value HERMES_DASHBOARD_PORT)"; hermes_dashboard_port="${hermes_dashboard_port:-9119}"
hermes_dashboard="$(existing_env_value HERMES_DASHBOARD)"; hermes_dashboard="${hermes_dashboard:-0}"
provider_name="9router"
provider_url="http://nine-router:20128/v1"
provider_key="local-no-auth"
model_name="ai"
telegram_token="$(existing_hermes_env_value TELEGRAM_BOT_TOKEN)"
telegram_ids="$(existing_hermes_env_value TELEGRAM_ALLOWED_USERS)"
telegram_home="$(existing_hermes_env_value TELEGRAM_HOME_CHANNEL)"
api_enabled="$(existing_hermes_env_value API_SERVER_ENABLED)"; api_enabled="${api_enabled:-false}"
api_key="$(existing_hermes_env_value API_SERVER_KEY)"

if [[ "$configure_hermes" == true ]]; then
  printf '\nHermes Agent settings\n'
  printf '%s\n' '---------------------'
  if [[ "$install_nine" == true ]]; then
    provider_url="http://nine-router:20128/v1"
    info "Hermes will reach 9router through the private Docker network."
  else
    provider_url="$(prompt "OpenAI-compatible API base URL (include /v1)" "http://host.docker.internal:20128/v1")"
  fi
  provider_name="$(prompt "Hermes provider name" "9router")"
  model_name="$(prompt "9router model/combo name" "ai")"

  if [[ "$nine_require_key" == true || "$install_nine" == false ]]; then
    provider_key="$(prompt_secret "9router/OpenAI-compatible API key")"
  else
    entered_key="$(prompt_secret "9router API key (Enter for local-no-auth)" true)"
    provider_key="${entered_key:-local-no-auth}"
  fi

  if confirm "Enable Telegram connectivity?" y; then
    while true; do
      telegram_token="$(prompt_secret "Telegram BotFather token")"
      [[ "$telegram_token" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]] && break
      warn "The token format does not look valid. Expected digits, a colon, then the token."
    done
    while true; do
      telegram_ids="$(prompt "Allowed numeric Telegram user IDs, comma-separated")"
      telegram_ids="${telegram_ids//[[:space:]]/}"
      valid_ids "$telegram_ids" && break
      warn "Use numeric IDs separated by commas, without usernames."
    done
    telegram_home="$(prompt "Optional Telegram home chat ID for cron results (Enter to skip)")"
    if [[ -n "$telegram_home" && ! "$telegram_home" =~ ^-?[0-9]+$ ]]; then
      die "Telegram home chat ID must be numeric."
    fi
  fi

  if confirm "Enable the Hermes web dashboard?" n; then
    hermes_dashboard="1"
    hermes_dashboard_port="$(prompt "Hermes dashboard port" "9119")"
    valid_port "$hermes_dashboard_port" || die "Invalid dashboard port."
    warn "The dashboard binds to localhost by default. Use an authenticated HTTPS reverse proxy for public access."
  fi

  if confirm "Enable the Hermes OpenAI-compatible API?" n; then
    api_enabled="true"
    hermes_api_port="$(prompt "Hermes API port" "8642")"
    valid_port "$hermes_api_port" || die "Invalid Hermes API port."
    api_key="$(random_hex 32)"
  fi
fi

if [[ "$configure_webui" == true ]]; then
  printf '\nOpen WebUI settings\n'
  printf '%s\n' '-------------------'
  openwebui_bind="$(prompt "Open WebUI host bind address (127.0.0.1 is safest)" "127.0.0.1")"
  openwebui_port="$(prompt "Open WebUI port" "3000")"
  valid_port "$openwebui_port" || die "Invalid Open WebUI port."
  openwebui_url="$(prompt "Open WebUI public URL (or local URL)" "http://localhost:$openwebui_port")"

  if [[ "$install_nine" == true ]]; then
    openwebui_api_url="http://nine-router:20128/v1"
    if [[ "$install_hermes" == true ]]; then
      openwebui_api_key="$provider_key"
    elif [[ "$nine_require_key" == true ]]; then
      openwebui_api_key="$(prompt_secret "9router API key for Open WebUI")"
    else
      entered_webui_key="$(prompt_secret "9router API key for Open WebUI (Enter for local-no-auth)" true)"
      openwebui_api_key="${entered_webui_key:-local-no-auth}"
    fi
    info "Open WebUI will reach 9router through the private Docker network."
  else
    openwebui_api_url="$(prompt "OpenAI-compatible API base URL for Open WebUI" "http://host.docker.internal:20128/v1")"
    openwebui_api_key="$(prompt_secret "OpenAI-compatible API key for Open WebUI")"
  fi

  if ! confirm "Allow account signup on first boot? (keep yes until an admin exists)" y; then
    openwebui_signup="false"
    warn "With signup disabled, create or confirm an administrator account before exposing Open WebUI."
  fi
fi

caddy_email=""
caddy_nine_domain=""
caddy_webui_domain=""
caddy_hermes_dashboard_domain=""
caddy_hermes_api_domain=""

if [[ "$install_nine" == true || "$install_webui" == true || "$hermes_dashboard" == 1 || "$api_enabled" == true ]]; then
  if [[ "$install_caddy" == true ]]; then
    confirm "Reconfigure existing Caddy domains?" n && configure_caddy=true
  elif confirm "Add optional Caddy domains with automatic HTTPS?" n; then
    configure_caddy=true
  fi

  if [[ "$configure_caddy" == true ]]; then
    install_caddy=true
    printf '\nCaddy domain settings\n'
    printf '%s\n' '---------------------'
    caddy_email="$(prompt "Optional ACME email for certificate notices (Enter to skip)")"
    if [[ -n "$caddy_email" && ( "$caddy_email" != *@* || "$caddy_email" == *[[:space:]]* ) ]]; then
      die "The Caddy certificate email is not valid."
    fi

    declare -A selected_domains=()
    if [[ "$install_nine" == true ]] && confirm "Publish 9router with a domain?" y; then
      caddy_nine_domain="$(prompt_domain "9router domain")"
      selected_domains["$caddy_nine_domain"]=1
      nine_public_url="https://$caddy_nine_domain"
      nine_cookie_secure="true"
    fi
    if [[ "$install_webui" == true ]] && confirm "Publish Open WebUI with a domain?" y; then
      caddy_webui_domain="$(prompt_domain "Open WebUI domain")"
      [[ -z "${selected_domains[$caddy_webui_domain]+x}" ]] || die "Each service needs a unique domain."
      selected_domains["$caddy_webui_domain"]=1
      openwebui_url="https://$caddy_webui_domain"
    fi
    if [[ "$hermes_dashboard" == 1 ]] && confirm "Publish the Hermes dashboard with a domain?" n; then
      caddy_hermes_dashboard_domain="$(prompt_domain "Hermes dashboard domain")"
      [[ -z "${selected_domains[$caddy_hermes_dashboard_domain]+x}" ]] || die "Each service needs a unique domain."
      selected_domains["$caddy_hermes_dashboard_domain"]=1
    fi
    if [[ "$api_enabled" == true ]] && confirm "Publish the Hermes API with a domain?" n; then
      caddy_hermes_api_domain="$(prompt_domain "Hermes API domain")"
      [[ -z "${selected_domains[$caddy_hermes_api_domain]+x}" ]] || die "Each service needs a unique domain."
      selected_domains["$caddy_hermes_api_domain"]=1
    fi

    if ((${#selected_domains[@]} == 0)); then
      warn "No domains were selected; Caddy will not be installed."
      install_caddy=false
    else
      warn "Caddy needs public DNS records plus inbound TCP 80/443 and UDP 443."
      if [[ -n "$caddy_nine_domain" && "$nine_require_key" != true ]]; then
        warn "9router /v1 will be public without Bearer-key enforcement. Enable REQUIRE_API_KEY after creating a 9router endpoint key."
      fi
      if [[ -n "$caddy_webui_domain" && "$openwebui_signup" == true ]]; then
        warn "Create the first Open WebUI administrator promptly, then disable signup in its Admin Panel."
      fi
    fi
  fi
fi

[[ "$install_caddy" == true ]] && profiles="${profiles:+$profiles,}caddy"

uid="${SUDO_UID:-$(id -u)}"
gid="${SUDO_GID:-$(id -g)}"
tmp_env="$(mktemp "$ROOT_DIR/.env.tmp.XXXXXX")"
{
  printf 'COMPOSE_PROFILES=%s\n' "$profiles"
  printf 'NINEROUTER_IMAGE=decolua/9router:latest\n'
  printf 'NINEROUTER_BIND_IP=%s\n' "$nine_bind"
  printf 'NINEROUTER_PORT=%s\n' "$nine_port"
  printf 'NINEROUTER_INITIAL_PASSWORD=%s\n' "$(dotenv_quote "$nine_password")"
  printf 'NINEROUTER_JWT_SECRET=%s\n' "$nine_jwt"
  printf 'NINEROUTER_API_KEY_SECRET=%s\n' "$nine_key_secret"
  printf 'NINEROUTER_MACHINE_ID_SALT=%s\n' "$nine_salt"
  printf 'NINEROUTER_REQUIRE_API_KEY=%s\n' "$nine_require_key"
  printf 'NINEROUTER_AUTH_COOKIE_SECURE=%s\n' "$nine_cookie_secure"
  printf 'NINEROUTER_PUBLIC_BASE_URL=%s\n' "$(dotenv_quote "$nine_public_url")"
  printf 'NINEROUTER_ENABLE_REQUEST_LOGS=false\n'
  printf 'NINEROUTER_OBSERVABILITY_ENABLED=true\n'
  printf 'HERMES_IMAGE=nousresearch/hermes-agent:latest\n'
  printf 'HERMES_BIND_IP=%s\n' "$hermes_bind"
  printf 'HERMES_API_PORT=%s\n' "$hermes_api_port"
  printf 'HERMES_DASHBOARD_PORT=%s\n' "$hermes_dashboard_port"
  printf 'HERMES_DASHBOARD=%s\n' "$hermes_dashboard"
  printf 'HERMES_UID=%s\n' "$uid"
  printf 'HERMES_GID=%s\n' "$gid"
  printf 'OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main\n'
  printf 'OPENWEBUI_BIND_IP=%s\n' "$openwebui_bind"
  printf 'OPENWEBUI_PORT=%s\n' "$openwebui_port"
  printf 'OPENWEBUI_URL=%s\n' "$(dotenv_quote "$openwebui_url")"
  printf 'OPENWEBUI_SECRET_KEY=%s\n' "$openwebui_secret"
  printf 'OPENWEBUI_OPENAI_BASE_URL=%s\n' "$(dotenv_quote "$openwebui_api_url")"
  printf 'OPENWEBUI_OPENAI_API_KEY=%s\n' "$(dotenv_quote "$openwebui_api_key")"
  printf 'OPENWEBUI_ENABLE_SIGNUP=%s\n' "$openwebui_signup"
  printf 'CADDY_IMAGE=caddy:2-alpine\n'
} > "$tmp_env"
chmod 600 "$tmp_env"
mv "$tmp_env" "$ENV_FILE"

if [[ "$configure_hermes" == true ]]; then
  config="$(<"$ROOT_DIR/templates/hermes-config.yaml.template")"
  config="${config//__PROVIDER_NAME__/$(yaml_quote "$provider_name")}"
  config="${config//__PROVIDER_BASE_URL__/$(yaml_quote "$provider_url")}"
  config="${config//__MODEL_NAME__/$(yaml_quote "$model_name")}"
  printf '%s\n' "$config" > "$HERMES_DIR/config.yaml"

  {
    printf 'TELEGRAM_BOT_TOKEN=%s\n' "$(dotenv_quote "$telegram_token")"
    printf 'TELEGRAM_ALLOWED_USERS=%s\n' "$telegram_ids"
    printf 'NINEROUTER_API_KEY=%s\n' "$(dotenv_quote "$provider_key")"
    [[ -n "$telegram_home" ]] && printf 'TELEGRAM_HOME_CHANNEL=%s\n' "$telegram_home"
    printf 'API_SERVER_ENABLED=%s\n' "$api_enabled"
    if [[ "$api_enabled" == true ]]; then
      printf 'API_SERVER_HOST=0.0.0.0\n'
      printf 'API_SERVER_KEY=%s\n' "$api_key"
      printf 'API_SERVER_CORS_ORIGINS=[]\n'
    fi
  } > "$HERMES_DIR/.env"
  chmod 600 "$HERMES_DIR/.env"
  chmod 644 "$HERMES_DIR/config.yaml"
fi

if [[ "$configure_caddy" == true && "$install_caddy" == true ]]; then
  {
    if [[ -n "$caddy_email" ]]; then
      printf '{\n\temail %s\n}\n\n' "$caddy_email"
    fi
    if [[ -n "$caddy_nine_domain" ]]; then
      printf '%s {\n\tencode zstd gzip\n\treverse_proxy nine-router:20128\n}\n\n' "$caddy_nine_domain"
    fi
    if [[ -n "$caddy_webui_domain" ]]; then
      printf '%s {\n\tencode zstd gzip\n\treverse_proxy open-webui:8080\n}\n\n' "$caddy_webui_domain"
    fi
    if [[ -n "$caddy_hermes_dashboard_domain" ]]; then
      printf '%s {\n\tencode zstd gzip\n\treverse_proxy hermes:9119\n}\n\n' "$caddy_hermes_dashboard_domain"
    fi
    if [[ -n "$caddy_hermes_api_domain" ]]; then
      printf '%s {\n\tencode zstd gzip\n\treverse_proxy hermes:8642\n}\n\n' "$caddy_hermes_api_domain"
    fi
  } > "$CADDY_DIR/Caddyfile"
  sed -i '${/^$/d;}' "$CADDY_DIR/Caddyfile"
  chmod 644 "$CADDY_DIR/Caddyfile"
fi

ok "Configuration generated."

if [[ "$DRY_RUN" == true ]]; then
  ok "Dry run complete. Docker was not changed."
  exit 0
fi

detect_docker
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" config --quiet
ok "Docker Compose configuration is valid."

if [[ "$NO_START" == true ]]; then
  ok "Configuration complete. Start later with ./manage.sh start"
  exit 0
fi

info "Pulling official container images..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" pull
if [[ "$configure_caddy" == true && "$install_caddy" == true ]]; then
  info "Validating generated Caddy configuration..."
  "${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile
fi
info "Starting selected services..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d --remove-orphans

printf '\n'
ok "Installation complete."
[[ "$install_nine" == true ]] && printf '9router dashboard: %s\n' "$nine_public_url"
if [[ "$install_hermes" == true && -n "$telegram_token" ]]; then
  printf '%s\n' 'Telegram: open your bot and send /start'
fi
[[ "$hermes_dashboard" == 1 ]] && printf 'Hermes dashboard: http://%s:%s\n' "$hermes_bind" "$hermes_dashboard_port"
[[ "$api_enabled" == true ]] && printf 'Hermes API key (save now): %s\n' "$api_key"
if [[ "$install_webui" == true ]]; then
  printf 'Open WebUI: %s\n' "$openwebui_url"
  [[ "$openwebui_signup" == true ]] && printf '%s\n' 'Open WebUI: the first registered account becomes administrator; disable signup afterward.'
fi
if [[ "$install_caddy" == true ]]; then
  [[ -n "$caddy_nine_domain" ]] && printf '9router HTTPS: https://%s\n' "$caddy_nine_domain"
  [[ -n "$caddy_webui_domain" ]] && printf 'Open WebUI HTTPS: https://%s\n' "$caddy_webui_domain"
  [[ -n "$caddy_hermes_dashboard_domain" ]] && printf 'Hermes dashboard HTTPS: https://%s\n' "$caddy_hermes_dashboard_domain"
  [[ -n "$caddy_hermes_api_domain" ]] && printf 'Hermes API HTTPS: https://%s\n' "$caddy_hermes_api_domain"
  printf '%s\n' 'Caddy requires public DNS plus inbound TCP 80/443 and UDP 443.'
fi
printf '%s\n' 'Status: ./manage.sh status'
printf '%s\n' 'Logs:   ./manage.sh logs'
