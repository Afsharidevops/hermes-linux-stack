#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
HERMES_ENV="$ROOT_DIR/data/hermes/.env"

usage() {
  cat <<'EOF'
Usage: ./manage.sh COMMAND [ARGUMENT]

Commands:
  menu                          Open the interactive server-management menu
  start                         Start selected services
  stop                          Stop selected services
  restart                       Restart selected services
  update                        Pull current official images and recreate
  status                        Show container status
  logs [hermes|9router|webui]  Follow all or one service's logs
  doctor                        Validate files and show diagnostics
  configure                     Run the interactive installer again
  add-telegram-user ID          Add one numeric Telegram user ID
  set-telegram-users ID1,ID2    Replace the complete Telegram allowlist
  show-telegram-users           Display the current Telegram allowlist
  set-backend-api-key KEY       Update Hermes's 9router/OpenAI endpoint key
EOF
}

case "${1:-}" in
  -h|--help|help|"") usage; exit 0 ;;
esac

[[ -f "$ENV_FILE" ]] || {
  printf 'Not configured. Run ./install.sh first.\n' >&2
  exit 1
}

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  printf 'Cannot access the Docker daemon.\n' >&2
  exit 1
fi

compose() {
  "${DOCKER[@]}" compose -f "$ROOT_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"
}

valid_ids() { [[ "$1" =~ ^[0-9]+(,[0-9]+)*$ ]]; }

interactive_menu() {
  local choice value service
  while true; do
    printf '\nHermes Linux Stack Manager\n'
    printf '%s\n' '=========================='
    printf '%s\n' '1) Service status'
    printf '%s\n' '2) Show Telegram users'
    printf '%s\n' '3) Add Telegram user'
    printf '%s\n' '4) Replace Telegram users'
    printf '%s\n' '5) Restart services'
    printf '%s\n' '6) Update official images'
    printf '%s\n' '7) Follow logs'
    printf '%s\n' '8) Reconfigure installation'
    printf '%s\n' '0) Exit'
    read -r -p 'Choose: ' choice
    case "$choice" in
      1) "$ROOT_DIR/manage.sh" status ;;
      2) "$ROOT_DIR/manage.sh" show-telegram-users ;;
      3)
        read -r -p 'Numeric Telegram user ID: ' value
        "$ROOT_DIR/manage.sh" add-telegram-user "$value"
        ;;
      4)
        read -r -p 'Complete comma-separated ID list: ' value
        "$ROOT_DIR/manage.sh" set-telegram-users "$value"
        ;;
      5) "$ROOT_DIR/manage.sh" restart ;;
      6)
        read -r -p 'Pull and recreate selected services? [y/N]: ' value
        [[ "$value" =~ ^[Yy]$ ]] && "$ROOT_DIR/manage.sh" update
        ;;
      7)
        read -r -p 'Service (all/hermes/9router/webui) [all]: ' service
        if [[ -n "$service" && "$service" != all ]]; then
          "$ROOT_DIR/manage.sh" logs "$service" || true
        else
          "$ROOT_DIR/manage.sh" logs || true
        fi
        ;;
      8) exec "$ROOT_DIR/install.sh" ;;
      0) return 0 ;;
      *) printf 'Unknown choice.\n' >&2 ;;
    esac
  done
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

restart_hermes() {
  compose up -d --no-deps --force-recreate hermes
}

command="${1:-}"
case "$command" in
  menu) interactive_menu ;;
  start) compose up -d ;;
  stop) compose stop ;;
  restart) compose restart ;;
  update)
    compose pull
    compose up -d --remove-orphans
    ;;
  status) compose ps ;;
  logs)
    case "${2:-}" in
      "") compose logs -f --tail=100 ;;
      hermes) compose logs -f --tail=100 hermes ;;
      9router|nine-router) compose logs -f --tail=100 nine-router ;;
      webui|open-webui) compose logs -f --tail=100 open-webui ;;
      *) printf 'Choose hermes, 9router, or webui.\n' >&2; exit 2 ;;
    esac
    ;;
  doctor)
    compose config --quiet
    printf 'Compose configuration: valid\n'
    compose ps
    if [[ -f "$HERMES_ENV" ]]; then
      mode="$(stat -c '%a' "$HERMES_ENV")"
      printf 'Hermes secret file mode: %s\n' "$mode"
      [[ "$mode" == 600 ]] || printf 'WARNING: expected data/hermes/.env mode 600\n'
    fi
    ;;
  configure) exec "$ROOT_DIR/install.sh" ;;
  show-telegram-users)
    [[ -f "$HERMES_ENV" ]] || { printf 'Hermes is not configured.\n' >&2; exit 1; }
    grep '^TELEGRAM_ALLOWED_USERS=' "$HERMES_ENV" || true
    ;;
  set-telegram-users)
    ids="${2:-}"
    ids="${ids//[[:space:]]/}"
    valid_ids "$ids" || { printf 'Use numeric comma-separated IDs.\n' >&2; exit 2; }
    [[ -f "$HERMES_ENV" ]] || { printf 'Hermes is not configured.\n' >&2; exit 1; }
    replace_env_value "$HERMES_ENV" TELEGRAM_ALLOWED_USERS "$ids"
    restart_hermes
    printf 'Telegram allowlist replaced: %s\n' "$ids"
    ;;
  add-telegram-user)
    new_id="${2:-}"
    [[ "$new_id" =~ ^[0-9]+$ ]] || { printf 'A numeric Telegram ID is required.\n' >&2; exit 2; }
    [[ -f "$HERMES_ENV" ]] || { printf 'Hermes is not configured.\n' >&2; exit 1; }
    current="$(sed -n 's/^TELEGRAM_ALLOWED_USERS=//p' "$HERMES_ENV" | head -n1)"
    if [[ ",$current," == *",$new_id,"* ]]; then
      printf 'Telegram ID %s is already allowed.\n' "$new_id"
      exit 0
    fi
    if [[ -n "$current" ]]; then updated="$current,$new_id"; else updated="$new_id"; fi
    replace_env_value "$HERMES_ENV" TELEGRAM_ALLOWED_USERS "$updated"
    restart_hermes
    printf 'Telegram ID %s added.\n' "$new_id"
    ;;
  set-backend-api-key)
    new_key="${2:-}"
    [[ "$new_key" =~ ^[A-Za-z0-9._:-]+$ ]] || {
      printf 'Provide a non-empty API key containing letters, digits, dot, underscore, colon, or hyphen.\n' >&2
      exit 2
    }
    profiles="$(sed -n 's/^COMPOSE_PROFILES=//p' "$ENV_FILE")"
    if [[ "$profiles" == *hermes* && -f "$HERMES_ENV" ]]; then
      replace_env_value "$HERMES_ENV" NINEROUTER_API_KEY "$new_key"
      restart_hermes
      printf 'Hermes backend API key updated.\n'
    else
      printf 'Hermes is not selected.\n' >&2
      exit 1
    fi
    ;;
  *) printf 'Unknown command: %s\n' "$command" >&2; usage >&2; exit 2 ;;
esac
