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
SMART_ROUTER_DIR="$ROOT_DIR/data/smart-router"
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

valid_bind_ip() {
  local ip="$1" octet
  local -a octets
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] && ((10#$octet <= 255)) || return 1
  done
}

private_ipv4() {
  local first second
  IFS=. read -r first second _ <<< "$1"
  (( 10#$first == 10 \
    || (10#$first == 172 && 16 <= 10#$second && 10#$second <= 31) \
    || (10#$first == 192 && 10#$second == 168) ))
}

detect_lan_ipv4() {
  local candidate
  if [[ -n "${HERMES_STACK_LAN_IP:-}" ]]; then
    valid_bind_ip "$HERMES_STACK_LAN_IP" \
      || die "HERMES_STACK_LAN_IP is not a valid IPv4 address: $HERMES_STACK_LAN_IP"
    printf '%s' "$HERMES_STACK_LAN_IP"
    return 0
  fi

  if command -v ip >/dev/null 2>&1; then
    candidate="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{ for (i=1; i<=NF; i++) if ($i == "src") { print $(i+1); exit } }')"
    if valid_bind_ip "$candidate" && private_ipv4 "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi

    while read -r candidate; do
      if valid_bind_ip "$candidate" && private_ipv4 "$candidate"; then
        printf '%s' "$candidate"
        return 0
      fi
    done < <(ip -o -4 addr show scope global 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4 }')
  fi

  if command -v hostname >/dev/null 2>&1; then
    for candidate in $(hostname -I 2>/dev/null); do
      if valid_bind_ip "$candidate" && private_ipv4 "$candidate"; then
        printf '%s' "$candidate"
        return 0
      fi
    done
  fi
  return 1
}

suggested_bind_ip() {
  local current="$1"
  if [[ -n "$lan_ip" && "$current" == 127.0.0.1 ]]; then
    printf '%s' "$lan_ip"
  else
    printf '%s' "$current"
  fi
}

service_url_host() {
  local bind_ip="$1"
  if [[ "$bind_ip" == 127.0.0.1 ]]; then
    printf 'localhost'
  elif [[ "$bind_ip" == 0.0.0.0 ]]; then
    printf '%s' "${lan_ip:-localhost}"
  else
    printf '%s' "$bind_ip"
  fi
}

prompt_bind_ip() {
  local label="$1" default="$2" value
  while true; do
    value="$(prompt "$label" "$default")"
    if valid_bind_ip "$value"; then
      printf '%s' "$value"
      return 0
    fi
    warn "Enter an IPv4 address such as 127.0.0.1, 192.168.1.10, or 0.0.0.0." >&2
  done
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

replace_env_value() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { changed=0 }
    index($0, key "=") == 1 { print key "=" value; changed=1; next }
    { print }
    END { if (!changed) print key "=" value }
  ' "$file" > "$tmp"
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
}

profile_enabled() {
  local profile="$1" configured
  configured="$(existing_env_value COMPOSE_PROFILES)"
  [[ ",$configured," == *",$profile,"* ]]
}

printf '\nHermes + 9router Linux Installer\n'
printf '%s\n' '================================'
lan_ip="$(detect_lan_ipv4 || true)"
if [[ -n "$lan_ip" ]]; then
  info "Detected LAN IPv4 address: $lan_ip (press Enter to use it when suggested)."
else
  warn "No private LAN IPv4 address was detected; localhost will be suggested."
fi
configure_nine=false
configure_hermes=false
configure_webui=false
configure_smart_router=false
configure_caddy=false
existing_install=false
smart_router_was_enabled=false
change_bind_ips=false

if [[ -f "$ENV_FILE" ]]; then
  existing_install=true
  install_nine=false; profile_enabled 9router && install_nine=true
  install_hermes=false; profile_enabled hermes && install_hermes=true
  install_webui=false; profile_enabled open-webui && install_webui=true
  install_smart_router=false; profile_enabled smart-router && install_smart_router=true
  smart_router_was_enabled="$install_smart_router"
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
  if [[ "$install_smart_router" == true ]]; then
    if ! confirm "Keep the Hermes Smart Router enabled?" y; then
      install_smart_router=false
      configure_smart_router=true
    elif confirm "Reconfigure existing Smart Router settings?" n; then
      configure_smart_router=true
    fi
  elif [[ "$install_nine" == true && "$install_hermes" == true ]] \
    && confirm "Add optional Hermes Smart Router (observation mode first)?" n; then
    install_smart_router=true
    configure_smart_router=true
  fi
  confirm "Change published container bind IPs only?" n && change_bind_ips=true
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
  install_smart_router=false
  if [[ "$install_nine" == true && "$install_hermes" == true ]] \
    && confirm "Add optional Hermes Smart Router (observation mode first)?" n; then
    install_smart_router=true
    configure_smart_router=true
  fi
  install_caddy=false
fi

profiles=""
[[ "$install_nine" == true ]] && profiles="9router"
[[ "$install_smart_router" == true ]] && profiles="${profiles:+$profiles,}smart-router"
[[ "$install_hermes" == true ]] && profiles="${profiles:+$profiles,}hermes"
[[ "$install_webui" == true ]] && profiles="${profiles:+$profiles,}open-webui"

mkdir -p "$HERMES_DIR" "$NINEROUTER_DIR" "$OPENWEBUI_DIR" "$SMART_ROUTER_DIR" "$CADDY_DIR"
backup_existing

nine_bind="$(existing_env_value NINEROUTER_BIND_IP)"; nine_bind="${nine_bind:-${lan_ip:-127.0.0.1}}"
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
  nine_bind="$(prompt_bind_ip "9router host bind address" "$(suggested_bind_ip "$nine_bind")")"
  nine_port="$(prompt "Dashboard/API port" "20128")"
  valid_port "$nine_port" || die "Invalid 9router port: $nine_port"
  nine_password="$(prompt_secret "Initial 9router dashboard password")"
  nine_public_url="$(prompt "Public dashboard URL (or local URL)" "http://$(service_url_host "$nine_bind"):$nine_port")"
  if [[ "$nine_public_url" == https://* ]]; then nine_cookie_secure="true"; fi
  if confirm "Require a 9router Bearer API key on /v1 routes?" n; then
    nine_require_key="true"
  fi
fi

openwebui_bind="$(existing_env_value OPENWEBUI_BIND_IP)"; openwebui_bind="${openwebui_bind:-${lan_ip:-127.0.0.1}}"
openwebui_port="$(existing_env_value OPENWEBUI_PORT)"; openwebui_port="${openwebui_port:-3000}"
openwebui_url="$(existing_env_value OPENWEBUI_URL)"; openwebui_url="${openwebui_url:-http://localhost:3000}"
existing_openwebui_secret="$(existing_env_value OPENWEBUI_SECRET_KEY)"
openwebui_secret="${existing_openwebui_secret:-$(random_hex 32)}"
openwebui_api_url="$(existing_env_value OPENWEBUI_OPENAI_BASE_URL)"; openwebui_api_url="${openwebui_api_url:-http://nine-router:20128/v1}"
openwebui_api_key="$(existing_env_value OPENWEBUI_OPENAI_API_KEY)"; openwebui_api_key="${openwebui_api_key:-local-no-auth}"
openwebui_signup="$(existing_env_value OPENWEBUI_ENABLE_SIGNUP)"; openwebui_signup="${openwebui_signup:-true}"

hermes_bind="$(existing_env_value HERMES_BIND_IP)"; hermes_bind="${hermes_bind:-${lan_ip:-127.0.0.1}}"
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
smart_router_image="$(existing_env_value SMART_ROUTER_IMAGE)"; smart_router_image="${smart_router_image:-afsharidevops/hermes-smart-router:0.1.0}"
smart_router_mode="$(existing_env_value SMART_ROUTER_MODE)"; smart_router_mode="${smart_router_mode:-observe}"
smart_router_secret="$(existing_env_value SMART_ROUTER_HMAC_SECRET)"; smart_router_secret="${smart_router_secret:-$(random_hex 32)}"
smart_router_policy="$(existing_env_value SMART_ROUTER_POLICY_VERSION)"; smart_router_policy="${smart_router_policy:-1}"
smart_router_fast_model="$(existing_env_value SMART_ROUTER_FAST_MODEL)"; smart_router_fast_model="${smart_router_fast_model:-combo-fast}"
smart_router_standard_model="$(existing_env_value SMART_ROUTER_STANDARD_MODEL)"; smart_router_standard_model="${smart_router_standard_model:-combo-standard}"
smart_router_strong_model="$(existing_env_value SMART_ROUTER_STRONG_MODEL)"; smart_router_strong_model="${smart_router_strong_model:-combo-strong}"
smart_router_observe_model="$(existing_env_value SMART_ROUTER_OBSERVE_MODEL)"; smart_router_observe_model="${smart_router_observe_model:-ai}"
smart_router_fail_open_model="$(existing_env_value SMART_ROUTER_FAIL_OPEN_MODEL)"; smart_router_fail_open_model="${smart_router_fail_open_model:-ai}"
smart_router_ttl="$(existing_env_value SMART_ROUTER_SESSION_TTL_SECONDS)"; smart_router_ttl="${smart_router_ttl:-2700}"
smart_router_max_age="$(existing_env_value SMART_ROUTER_MAX_SESSION_AGE_SECONDS)"; smart_router_max_age="${smart_router_max_age:-43200}"
smart_router_demotion="$(existing_env_value SMART_ROUTER_DEMOTION_TURNS)"; smart_router_demotion="${smart_router_demotion:-5}"
smart_router_fast_tokens="$(existing_env_value SMART_ROUTER_FAST_MAX_TOKENS)"; smart_router_fast_tokens="${smart_router_fast_tokens:-1024}"
smart_router_standard_tokens="$(existing_env_value SMART_ROUTER_STANDARD_MAX_TOKENS)"; smart_router_standard_tokens="${smart_router_standard_tokens:-4096}"
smart_router_strong_tokens="$(existing_env_value SMART_ROUTER_STRONG_MAX_TOKENS)"; smart_router_strong_tokens="${smart_router_strong_tokens:-6144}"
smart_router_connect_timeout="$(existing_env_value SMART_ROUTER_CONNECT_TIMEOUT_SECONDS)"; smart_router_connect_timeout="${smart_router_connect_timeout:-10}"
smart_router_read_timeout="$(existing_env_value SMART_ROUTER_READ_TIMEOUT_SECONDS)"; smart_router_read_timeout="${smart_router_read_timeout:-600}"
smart_router_max_bytes="$(existing_env_value SMART_ROUTER_MAX_REQUEST_BYTES)"; smart_router_max_bytes="${smart_router_max_bytes:-10485760}"
nine_image="$(existing_env_value NINEROUTER_IMAGE)"; nine_image="${nine_image:-decolua/9router:latest}"
hermes_image="$(existing_env_value HERMES_IMAGE)"; hermes_image="${hermes_image:-nousresearch/hermes-agent:latest}"
openwebui_image="$(existing_env_value OPENWEBUI_IMAGE)"; openwebui_image="${openwebui_image:-ghcr.io/open-webui/open-webui:main}"
caddy_image="$(existing_env_value CADDY_IMAGE)"; caddy_image="${caddy_image:-caddy:2-alpine}"
caddy_bind="$(existing_env_value CADDY_BIND_IP)"; caddy_bind="${caddy_bind:-0.0.0.0}"

if [[ "$configure_smart_router" == true && "$install_smart_router" == true ]]; then
  printf '\nHermes Smart Router settings\n'
  printf '%s\n' '----------------------------'
  smart_router_mode="$(prompt "Initial mode (observe is safest)" "$smart_router_mode")"
  [[ "$smart_router_mode" == observe || "$smart_router_mode" == route ]] \
    || die "Smart Router mode must be observe or route."
  smart_router_fast_model="$(prompt "Fast-tier 9router combo" "$smart_router_fast_model")"
  smart_router_standard_model="$(prompt "Standard-tier 9router combo" "$smart_router_standard_model")"
  smart_router_strong_model="$(prompt "Strong-tier 9router combo" "$smart_router_strong_model")"
  warn "The installer initially clones ai into all three tier combos; customize their model lists in 9router before route mode provides meaningful tier differences."
fi

if [[ "$install_smart_router" == true ]]; then
  provider_url="http://smart-router:8080/v1"
  openwebui_api_url="http://smart-router:8080/v1"
  model_name="auto"
elif [[ "$install_nine" == true ]]; then
  openwebui_api_url="http://nine-router:20128/v1"
  provider_url="http://nine-router:20128/v1"
  [[ "$model_name" == auto* ]] && model_name="ai"
fi

if [[ "$change_bind_ips" == true ]]; then
  printf '\nPublished container bind IPs\n'
  printf '%s\n' '----------------------------'
  if [[ "$install_nine" == true && "$configure_nine" != true ]]; then
    nine_bind="$(prompt_bind_ip "9router bind IP" "$(suggested_bind_ip "$nine_bind")")"
  fi
  if [[ "$install_hermes" == true && "$configure_hermes" != true ]]; then
    hermes_bind="$(prompt_bind_ip "Hermes API/dashboard bind IP" "$(suggested_bind_ip "$hermes_bind")")"
  fi
  if [[ "$install_webui" == true && "$configure_webui" != true ]]; then
    openwebui_bind="$(prompt_bind_ip "Open WebUI bind IP" "$(suggested_bind_ip "$openwebui_bind")")"
  fi
  if [[ "$install_caddy" == true && "$configure_caddy" != true ]]; then
    caddy_bind="$(prompt_bind_ip "Caddy HTTP/HTTPS bind IP" "$caddy_bind")"
  fi
  if [[ ( "$install_nine" == true && "$nine_bind" == 0.0.0.0 ) \
    || ( "$install_hermes" == true && "$hermes_bind" == 0.0.0.0 ) \
    || ( "$install_webui" == true && "$openwebui_bind" == 0.0.0.0 ) \
    || ( "$install_caddy" == true && "$caddy_bind" == 0.0.0.0 ) ]]; then
    warn "0.0.0.0 publishes a service on every host interface; protect it with a firewall and authentication."
  fi
fi

if [[ "$configure_hermes" == true ]]; then
  printf '\nHermes Agent settings\n'
  printf '%s\n' '---------------------'
  hermes_bind="$(prompt_bind_ip "Hermes API/dashboard host bind address" "$(suggested_bind_ip "$hermes_bind")")"
  if [[ "$install_smart_router" == true ]]; then
    provider_url="http://smart-router:8080/v1"
    info "Hermes will reach 9router through the Smart Router in observation mode."
  elif [[ "$install_nine" == true ]]; then
    provider_url="http://nine-router:20128/v1"
    info "Hermes will reach 9router through the private Docker network."
  else
    provider_url="$(prompt "OpenAI-compatible API base URL (include /v1)" "http://host.docker.internal:20128/v1")"
  fi
  provider_name="$(prompt "Hermes provider name" "9router")"
  if [[ "$install_smart_router" == true ]]; then
    model_name="auto"
    info "Hermes model is set to auto; explicit /model selections still pass through unchanged."
  else
    model_name="$(prompt "9router model/combo name" "ai")"
  fi

  if [[ "$install_nine" == true ]]; then
    provider_key="auto-generated-after-9router-starts"
    info "A dedicated 9router API key will be configured automatically for Hermes."
  else
    provider_key="$(prompt_secret "9router/OpenAI-compatible API key")"
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
  openwebui_bind="$(prompt_bind_ip "Open WebUI host bind address" "$(suggested_bind_ip "$openwebui_bind")")"
  openwebui_port="$(prompt "Open WebUI port" "3000")"
  valid_port "$openwebui_port" || die "Invalid Open WebUI port."
  openwebui_url="$(prompt "Open WebUI public URL (or local URL)" "http://$(service_url_host "$openwebui_bind"):$openwebui_port")"

  if [[ "$install_nine" == true ]]; then
    if [[ "$install_smart_router" == true ]]; then
      openwebui_api_url="http://smart-router:8080/v1"
      info "Open WebUI will reach 9router through the Smart Router."
    else
      openwebui_api_url="http://nine-router:20128/v1"
      info "Open WebUI will reach 9router through the private Docker network."
    fi
    openwebui_api_key="auto-generated-after-9router-starts"
    info "A dedicated 9router API key and OpenCode-Free model will be configured automatically."
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
    caddy_bind="$(prompt_bind_ip "Caddy HTTP/HTTPS host bind address (public HTTPS normally needs 0.0.0.0)" "$caddy_bind")"
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
  printf 'NINEROUTER_IMAGE=%s\n' "$nine_image"
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
  printf 'HERMES_IMAGE=%s\n' "$hermes_image"
  printf 'HERMES_BIND_IP=%s\n' "$hermes_bind"
  printf 'HERMES_API_PORT=%s\n' "$hermes_api_port"
  printf 'HERMES_DASHBOARD_PORT=%s\n' "$hermes_dashboard_port"
  printf 'HERMES_DASHBOARD=%s\n' "$hermes_dashboard"
  printf 'HERMES_UID=%s\n' "$uid"
  printf 'HERMES_GID=%s\n' "$gid"
  printf 'SMART_ROUTER_IMAGE=%s\n' "$smart_router_image"
  printf 'SMART_ROUTER_MODE=%s\n' "$smart_router_mode"
  printf 'SMART_ROUTER_HMAC_SECRET=%s\n' "$smart_router_secret"
  printf 'SMART_ROUTER_POLICY_VERSION=%s\n' "$smart_router_policy"
  printf 'SMART_ROUTER_OBSERVE_MODEL=%s\n' "$smart_router_observe_model"
  printf 'SMART_ROUTER_FAIL_OPEN_MODEL=%s\n' "$smart_router_fail_open_model"
  printf 'SMART_ROUTER_FAST_MODEL=%s\n' "$smart_router_fast_model"
  printf 'SMART_ROUTER_STANDARD_MODEL=%s\n' "$smart_router_standard_model"
  printf 'SMART_ROUTER_STRONG_MODEL=%s\n' "$smart_router_strong_model"
  printf 'SMART_ROUTER_SESSION_TTL_SECONDS=%s\n' "$smart_router_ttl"
  printf 'SMART_ROUTER_MAX_SESSION_AGE_SECONDS=%s\n' "$smart_router_max_age"
  printf 'SMART_ROUTER_DEMOTION_TURNS=%s\n' "$smart_router_demotion"
  printf 'SMART_ROUTER_FAST_MAX_TOKENS=%s\n' "$smart_router_fast_tokens"
  printf 'SMART_ROUTER_STANDARD_MAX_TOKENS=%s\n' "$smart_router_standard_tokens"
  printf 'SMART_ROUTER_STRONG_MAX_TOKENS=%s\n' "$smart_router_strong_tokens"
  printf 'SMART_ROUTER_CONNECT_TIMEOUT_SECONDS=%s\n' "$smart_router_connect_timeout"
  printf 'SMART_ROUTER_READ_TIMEOUT_SECONDS=%s\n' "$smart_router_read_timeout"
  printf 'SMART_ROUTER_MAX_REQUEST_BYTES=%s\n' "$smart_router_max_bytes"
  printf 'OPENWEBUI_IMAGE=%s\n' "$openwebui_image"
  printf 'OPENWEBUI_BIND_IP=%s\n' "$openwebui_bind"
  printf 'OPENWEBUI_PORT=%s\n' "$openwebui_port"
  printf 'OPENWEBUI_URL=%s\n' "$(dotenv_quote "$openwebui_url")"
  printf 'OPENWEBUI_SECRET_KEY=%s\n' "$openwebui_secret"
  printf 'OPENWEBUI_OPENAI_BASE_URL=%s\n' "$(dotenv_quote "$openwebui_api_url")"
  printf 'OPENWEBUI_OPENAI_API_KEY=%s\n' "$(dotenv_quote "$openwebui_api_key")"
  printf 'OPENWEBUI_ENABLE_SIGNUP=%s\n' "$openwebui_signup"
  printf 'CADDY_IMAGE=%s\n' "$caddy_image"
  printf 'CADDY_BIND_IP=%s\n' "$caddy_bind"
} > "$tmp_env"
chmod 600 "$tmp_env"
mv "$tmp_env" "$ENV_FILE"

if [[ "$configure_hermes" == true ]]; then
  config="$(<"$ROOT_DIR/templates/hermes-config.yaml.template")"
  config="${config//__PROVIDER_ID__/$(yaml_quote "custom:$provider_name")}"
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

if [[ "$configure_smart_router" == true && "$configure_hermes" != true \
  && -f "$HERMES_DIR/config.yaml" ]]; then
  # Update only the active provider's base_url and the model default so Telegram
  # secrets and any additional custom providers stay untouched.
  tmp_config="$(mktemp "$HERMES_DIR/config.yaml.tmp.XXXXXX")"
  awk -v model="$model_name" -v url="$provider_url" -v provider="$provider_name" '
    BEGIN { in_model = 0; in_providers = 0; active = 0 }
    /^[^[:space:]#]/ {
      in_model = ($0 ~ /^model:/)
      in_providers = ($0 ~ /^custom_providers:/)
      active = 0
    }
    in_model && /^  default:/ { print "  default: '\''" model "'\''"; next }
    in_providers && /^  - name:/ {
      line = $0
      gsub(/^  - name:[[:space:]]*/, "", line)
      gsub(/^'\''|'\''$|^"|"$/, "", line)
      active = (line == provider)
    }
    in_providers && active && /^    base_url:/ {
      print "    base_url: '\''" url "'\''"
      next
    }
    { print }
  ' "$HERMES_DIR/config.yaml" > "$tmp_config"
  chmod --reference="$HERMES_DIR/config.yaml" "$tmp_config"
  mv "$tmp_config" "$HERMES_DIR/config.yaml"
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
  if [[ "$install_nine" == true && ( "$install_hermes" == true || "$install_webui" == true ) ]]; then
    warn "Automatic 9router key/model provisioning requires a normal installer run when services are started."
  fi
  ok "Configuration complete. Start later with ./manage.sh start"
  exit 0
fi

info "Pulling selected container images..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" pull

openwebui_key_status=""
hermes_key_status=""
opencode_combo_status="not-requested"
ai_combo_status="not-requested"
opencode_free_model_count="0"
if [[ "$install_nine" == true && ( "$install_hermes" == true || "$install_webui" == true ) ]]; then
  openwebui_db_preexisting=false
  [[ -f "$OPENWEBUI_DIR/webui.db" ]] && openwebui_db_preexisting=true

  info "Starting 9router to provision service access..."
  "${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d --no-deps nine-router
  # 9router answers /api/health before it has created and migrated its SQLite
  # database, so a health probe alone lets the installer race ahead and fail in
  # the provisioning script. Also require the tables that script writes to.
  nine_ready=false
  for _ in {1..90}; do
    if "${DOCKER[@]}" exec nine-router node -e \
      'const Database=require("node:module").createRequire("/app/package.json")("better-sqlite3");
       const db=new Database("/app/data/db/data.sqlite",{readonly:true,fileMustExist:true});
       try{db.prepare("SELECT 1 FROM apiKeys LIMIT 1").get();db.prepare("SELECT 1 FROM combos LIMIT 1").get();}finally{db.close();}
       fetch("http://127.0.0.1:20128/api/health").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))' \
      >/dev/null 2>&1; then
      nine_ready=true
      break
    fi
    sleep 2
  done
  [[ "$nine_ready" == true ]] || die "9router did not become ready for service provisioning."

  info "Generating/reusing dedicated 9router keys and configuring model combos..."
  bootstrap_output="$("${DOCKER[@]}" exec -i \
    -e PROVISION_HERMES="$install_hermes" \
    -e PROVISION_OPENWEBUI="$install_webui" \
    -e PROVISION_SMART_ROUTER="$install_smart_router" \
    -e SMART_ROUTER_FAST_MODEL="$smart_router_fast_model" \
    -e SMART_ROUTER_STANDARD_MODEL="$smart_router_standard_model" \
    -e SMART_ROUTER_STRONG_MODEL="$smart_router_strong_model" \
    -e HERMES_MODEL_NAME="$model_name" \
    nine-router node --input-type=module < "$ROOT_DIR/scripts/bootstrap-openwebui.mjs")"
  openwebui_api_key="$(sed -n 's/^OPENWEBUI_API_KEY=//p' <<< "$bootstrap_output" | tail -n1)"
  openwebui_key_status="$(sed -n 's/^OPENWEBUI_KEY_STATUS=//p' <<< "$bootstrap_output" | tail -n1)"
  hermes_api_key="$(sed -n 's/^HERMES_API_KEY=//p' <<< "$bootstrap_output" | tail -n1)"
  hermes_key_status="$(sed -n 's/^HERMES_KEY_STATUS=//p' <<< "$bootstrap_output" | tail -n1)"
  opencode_combo_status="$(sed -n 's/^OPENCODE_COMBO_STATUS=//p' <<< "$bootstrap_output" | tail -n1)"
  ai_combo_status="$(sed -n 's/^AI_COMBO_STATUS=//p' <<< "$bootstrap_output" | tail -n1)"
  smart_router_combo_status="$(sed -n 's/^SMART_ROUTER_COMBO_STATUS=//p' <<< "$bootstrap_output" | tail -n1)"
  opencode_free_model_count="$(sed -n 's/^OPENCODE_FREE_MODEL_COUNT=//p' <<< "$bootstrap_output" | tail -n1)"

  if [[ "$install_webui" == true ]]; then
    [[ -n "$openwebui_api_key" ]] || die "9router did not return the generated Open WebUI API key."
    replace_env_value "$ENV_FILE" OPENWEBUI_OPENAI_API_KEY "$(dotenv_quote "$openwebui_api_key")"
  fi
  if [[ "$install_hermes" == true ]]; then
    [[ -n "$hermes_api_key" ]] || die "9router did not return the generated Hermes API key."
    replace_env_value "$HERMES_DIR/.env" NINEROUTER_API_KEY "$(dotenv_quote "$hermes_api_key")"
  fi
fi

if [[ "$configure_caddy" == true && "$install_caddy" == true ]]; then
  info "Validating generated Caddy configuration..."
  "${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile
fi
if [[ "$smart_router_was_enabled" == true && "$install_smart_router" != true ]]; then
  info "Stopping the disabled Hermes Smart Router..."
  COMPOSE_PROFILES=smart-router "${DOCKER[@]}" compose \
    -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
    rm -sf smart-router smart-router-init
fi

info "Starting selected services..."
"${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d --remove-orphans

if [[ "$install_smart_router" == true ]]; then
  info "Waiting for the Hermes Smart Router to become ready..."
  smart_router_ready=false
  for _ in {1..60}; do
    if "${DOCKER[@]}" exec hermes-smart-router python -c \
      'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8080/ready", timeout=5)' \
      >/dev/null 2>&1; then
      smart_router_ready=true
      break
    fi
    sleep 2
  done
  [[ "$smart_router_ready" == true ]] || die "Hermes Smart Router did not become ready."
fi

if [[ "$install_nine" == true && "$install_webui" == true ]]; then
  if [[ "$openwebui_db_preexisting" == true || "$configure_smart_router" == true ]]; then
    info "Synchronizing the Open WebUI backend connection without deleting its data..."
    webui_db_ready=false
    for _ in {1..60}; do
      if "${DOCKER[@]}" exec open-webui python -c \
        'import sqlite3; db=sqlite3.connect("/app/backend/data/webui.db"); db.execute("select 1 from config limit 1").fetchone(); db.close()' \
        >/dev/null 2>&1; then
        webui_db_ready=true
        break
      fi
      sleep 2
    done
    [[ "$webui_db_ready" == true ]] || die "Open WebUI database did not become ready for connection migration."
    "${DOCKER[@]}" exec -i open-webui python < "$ROOT_DIR/scripts/sync-openwebui-config.py"
    "${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" restart open-webui
  fi

  if [[ "$opencode_combo_status" != unavailable ]]; then
    info "Verifying Open WebUI can authenticate to 9router and discover OpenCode-Free..."
    "${DOCKER[@]}" exec -i open-webui python < "$ROOT_DIR/scripts/verify-openwebui-backend.py"
  else
    warn "The 9router key is configured, but OpenCode-Free could not be refreshed from the upstream catalog."
  fi
fi

printf '\n'
ok "Installation complete."
[[ "$install_nine" == true ]] && printf '9router dashboard: %s\n' "$nine_public_url"
if [[ -n "$hermes_key_status" ]]; then
  printf 'Hermes 9router key: %s (stored securely; not printed)\n' "$hermes_key_status"
  if [[ "$model_name" == ai || "$install_smart_router" == true ]]; then
    printf 'Hermes ai combo: %s (%s free upstream models)\n' "$ai_combo_status" "$opencode_free_model_count"
  fi
fi
if [[ "$install_smart_router" == true ]]; then
  printf 'Hermes Smart Router: enabled (%s mode)\n' "$smart_router_mode"
  printf 'Smart Router tier combos: %s (initially cloned from ai)\n' "$smart_router_combo_status"
  warn "Customize combo-fast, combo-standard, and combo-strong in 9router before enabling route mode."
fi
if [[ "$install_hermes" == true && -n "$telegram_token" ]]; then
  printf '%s\n' 'Telegram: open your bot and send /start'
fi
[[ "$hermes_dashboard" == 1 ]] && printf 'Hermes dashboard: http://%s:%s\n' "$hermes_bind" "$hermes_dashboard_port"
[[ "$configure_hermes" == true && "$api_enabled" == true ]] && printf 'Hermes API key (save now): %s\n' "$api_key"
if [[ "$install_webui" == true ]]; then
  printf 'Open WebUI: %s\n' "$openwebui_url"
  if [[ -n "$openwebui_key_status" ]]; then
    printf 'Open WebUI 9router key: %s (stored securely; not printed)\n' "$openwebui_key_status"
    printf 'OpenCode-Free model: %s (%s free upstream models)\n' "$opencode_combo_status" "$opencode_free_model_count"
  fi
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
