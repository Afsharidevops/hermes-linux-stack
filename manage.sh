#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
HERMES_ENV="$ROOT_DIR/data/hermes/.env"
HERMES_CONFIG="$ROOT_DIR/data/hermes/config.yaml"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./manage.sh <command> [args]

Core:
  start                       Start selected profiles
  stop                        Stop the stack
  restart                     Restart selected profiles
  status                      Show container status
  logs [service]              Follow logs (all services or one service)
  update                      Pull images and recreate selected services
  configure                   Run the interactive installer again
  doctor                      Static + Docker/HTTP checks
  backup [output.tar.gz]      Archive configuration and persistent data

OmniRoute migration/operations:
  enable-omniroute-api-auth   Prompt for an existing OmniRoute endpoint API key,
                              configure Hermes/Open WebUI to use it, enable enforcement
  disable-omniroute-api-auth  Disable endpoint-key enforcement (loopback-only recommended)
  set-model <name>            Change Hermes and Smart Router defaults to a model/route name
  migration-status            Report legacy data/9router presence and new data/omniroute state

Hermes:
  show-telegram-users
  set-telegram-users <csv>
  add-telegram-user <id>

Examples:
  ./manage.sh logs omniroute
  ./manage.sh set-model auto
  ./manage.sh enable-omniroute-api-auth
USAGE
}

require_env() { [[ -f "$ENV_FILE" ]] || die "Missing .env. Run ./install.sh first."; }

detect_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is required."
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is required."
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    die "Cannot access Docker daemon."
  fi
}

compose() {
  require_env
  detect_docker
  "${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"
}

env_get() {
  local key="$1" file="${2:-$ENV_FILE}" line value
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" | tail -n1 || true)"
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then value="${value:1:${#value}-2}"; fi
  printf '%s' "$value"
}

dotenv_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\$\$}"
  printf '"%s"' "$value"
}

env_set() {
  local file="$1" key="$2" value="$3" tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  awk -v k="$key" -v v="$value" '
    BEGIN { done=0 }
    $0 ~ "^" k "=" { if (!done) { print k "=" v; done=1 }; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

restart_clients() {
  info "Recreating selected services with the updated router settings..."
  compose up -d --remove-orphans
}

set_omni_key() {
  local key="$1"
  env_set "$ENV_FILE" OMNIROUTE_REQUIRE_API_KEY true
  env_set "$ENV_FILE" OPENWEBUI_OPENAI_API_KEY "$(dotenv_quote "$key")"
  if [[ -f "$HERMES_ENV" ]]; then
    env_set "$HERMES_ENV" OMNIROUTE_API_KEY "$(dotenv_quote "$key")"
  fi
}

disable_omni_key() {
  env_set "$ENV_FILE" OMNIROUTE_REQUIRE_API_KEY false
  env_set "$ENV_FILE" OPENWEBUI_OPENAI_API_KEY "$(dotenv_quote 'omniroute-internal')"
  if [[ -f "$HERMES_ENV" ]]; then
    env_set "$HERMES_ENV" OMNIROUTE_API_KEY "$(dotenv_quote 'omniroute-internal')"
  fi
}

valid_ids() { [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]]; }

set_model() {
  local model="$1"
  [[ -n "$model" ]] || die "Model/route name cannot be empty."
  for k in SMART_ROUTER_OBSERVE_MODEL SMART_ROUTER_FAIL_OPEN_MODEL SMART_ROUTER_FAST_MODEL SMART_ROUTER_STANDARD_MODEL SMART_ROUTER_STRONG_MODEL; do
    env_set "$ENV_FILE" "$k" "$model"
  done
  if [[ -f "$HERMES_CONFIG" ]]; then
    MODEL_VALUE="$model" HERMES_CONFIG_PATH="$HERMES_CONFIG" python3 - <<'PY'
import os, re
from pathlib import Path
p=Path(os.environ['HERMES_CONFIG_PATH'])
s=p.read_text()
model=os.environ['MODEL_VALUE'].replace("'", "''")
s2=re.sub(r'(?m)^(\s*default:\s*).+$', rf"\1'{model}'", s, count=1)
if s2 == s:
    raise SystemExit('Could not find model.default in Hermes config')
p.write_text(s2)
PY
  fi
  ok "Default model/route changed to: $model"
}

doctor() {
  require_env
  local failed=0
  printf 'Hermes OmniRoute stack doctor\n\n'

  if grep -RInE --exclude='MIGRATION.md' --exclude='CHANGELOG.md' --exclude='RELEASE_NOTES.md' \
      --exclude-dir='.git' '(nine-router|NINEROUTER_|decolua/9router)' \
      "$ROOT_DIR/docker-compose.yml" "$ROOT_DIR/templates" "$ROOT_DIR/plugins" "$ROOT_DIR/.env.example" 2>/dev/null; then
    warn "Legacy router identifiers remain in runtime/config templates."
    failed=1
  else
    ok "No legacy router identifiers in runtime/config templates."
  fi

  [[ -d "$ROOT_DIR/data/omniroute" ]] && ok "data/omniroute exists." || { warn "data/omniroute is missing."; failed=1; }
  [[ -s "$ROOT_DIR/data/stack-secrets/execution/control-secret" ]] && ok "Execution control-secret mount source exists." || warn "Execution control-secret not initialized (installer creates it)."

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if compose config >/dev/null; then ok "docker compose config passes."; else failed=1; fi
    compose ps || true
  else
    warn "Docker unavailable; skipped live Compose checks."
  fi

  local dash_bind dash_port api_bind api_port
  dash_bind="$(env_get OMNIROUTE_BIND_IP)"; dash_bind="${dash_bind:-127.0.0.1}"
  dash_port="$(env_get OMNIROUTE_PORT)"; dash_port="${dash_port:-20128}"
  api_bind="$(env_get OMNIROUTE_API_BIND_IP)"; api_bind="${api_bind:-127.0.0.1}"
  api_port="$(env_get OMNIROUTE_API_PORT)"; api_port="${api_port:-20129}"
  [[ "$dash_bind" == 0.0.0.0 ]] && dash_bind=127.0.0.1
  [[ "$api_bind" == 0.0.0.0 ]] && api_bind=127.0.0.1
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 "http://$dash_bind:$dash_port" >/dev/null 2>&1 && ok "OmniRoute dashboard responds." || warn "OmniRoute dashboard did not answer HTTP check."
    curl -fsS --max-time 3 "http://$api_bind:$api_port/v1/models" >/dev/null 2>&1 && ok "OmniRoute /v1 API responds." || warn "OmniRoute /v1/models check failed (auth/provider setup may still be pending)."
  fi

  (( failed == 0 )) || exit 1
}

backup_stack() {
  require_env
  local output="${1:-$ROOT_DIR/hermes-omniroute-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
  tar -C "$ROOT_DIR" -czf "$output" .env data templates docker-compose.yml plugins install.sh manage.sh README.md SECURITY.md MIGRATION.md CHANGELOG.md RELEASE_NOTES.md
  chmod 600 "$output" || true
  ok "Backup written to $output"
}

cmd="${1:-}"
case "$cmd" in
  start) compose up -d --remove-orphans ;;
  stop) compose down ;;
  restart) compose down; compose up -d --remove-orphans ;;
  status) compose ps ;;
  logs)
    shift || true
    if [[ $# -gt 0 ]]; then compose logs -f --tail=200 "$1"; else compose logs -f --tail=200; fi
    ;;
  update)
    compose pull
    compose up -d --remove-orphans
    ;;
  configure)
    exec "$ROOT_DIR/install.sh"
    ;;
  doctor) doctor ;;
  backup)
    shift || true
    backup_stack "${1:-}"
    ;;
  enable-omniroute-api-auth)
    require_env
    printf 'Create an endpoint API key in OmniRoute first.\n'
    read -r -s -p 'OmniRoute endpoint API key: ' key
    printf '\n'
    [[ -n "$key" ]] || die "A key is required."
    set_omni_key "$key"
    restart_clients
    ok "OmniRoute API-key enforcement enabled for the stack clients."
    ;;
  disable-omniroute-api-auth)
    require_env
    disable_omni_key
    restart_clients
    warn "OmniRoute API-key enforcement is disabled. Keep the API bound to loopback/a protected network."
    ;;
  set-model)
    require_env
    [[ $# -eq 2 ]] || die "Usage: ./manage.sh set-model <name>"
    set_model "$2"
    restart_clients
    ;;
  migration-status)
    require_env
    if [[ -d "$ROOT_DIR/data/9router" ]]; then
      warn "Legacy data/9router exists. It is intentionally not mounted by this release. Keep it as a backup until OmniRoute is verified."
    else
      ok "No legacy data/9router directory in this installation."
    fi
    [[ -d "$ROOT_DIR/data/omniroute" ]] && ok "OmniRoute data directory exists: data/omniroute" || warn "data/omniroute is missing."
    printf 'Selected profiles: %s\n' "$(env_get COMPOSE_PROFILES)"
    printf 'OmniRoute API-key enforcement: %s\n' "$(env_get OMNIROUTE_REQUIRE_API_KEY)"
    ;;
  show-telegram-users)
    [[ -f "$HERMES_ENV" ]] || die "Hermes is not configured."
    printf '%s\n' "$(env_get TELEGRAM_ALLOWED_USERS "$HERMES_ENV")"
    ;;
  set-telegram-users)
    [[ $# -eq 2 ]] || die "Usage: ./manage.sh set-telegram-users <id,id,...>"
    valid_ids "$2" || die "Expected comma-separated numeric Telegram user IDs."
    env_set "$HERMES_ENV" TELEGRAM_ALLOWED_USERS "$2"
    compose up -d hermes
    ;;
  add-telegram-user)
    [[ $# -eq 2 && "$2" =~ ^[0-9]+$ ]] || die "Usage: ./manage.sh add-telegram-user <numeric-id>"
    current="$(env_get TELEGRAM_ALLOWED_USERS "$HERMES_ENV")"
    if [[ ",$current," == *",$2,"* ]]; then ok "User $2 is already allowed."; exit 0; fi
    [[ -n "$current" ]] && current="$current,$2" || current="$2"
    env_set "$HERMES_ENV" TELEGRAM_ALLOWED_USERS "$current"
    compose up -d hermes
    ;;
  -h|--help|help|'') usage ;;
  *) die "Unknown command: $cmd (run ./manage.sh help)" ;;
esac
