#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
HERMES_ENV="$ROOT_DIR/data/hermes/.env"
STACK_SECRETS_DIR="$ROOT_DIR/data/stack-secrets"
N8N_BOOTSTRAP_ENV="$STACK_SECRETS_DIR/n8n-bootstrap.env"
N8N_BOOTSTRAP_STATE="$STACK_SECRETS_DIR/n8n-bootstrap-state.json"
TEMP_SECRET_FILES=()

cleanup_temp_secrets() {
  local file
  for file in "${TEMP_SECRET_FILES[@]}"; do
    rm -f -- "$file"
  done
}
trap cleanup_temp_secrets EXIT

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
  logs [hermes|9router|smart-router|webui|n8n|caddy]
                                Follow all or one service's logs
  set-router-mode MODE          Set Smart Router mode to observe or route
  doctor                        Validate files and show diagnostics
  configure                     Run the interactive installer again
  add-telegram-user ID          Add one numeric Telegram user ID
  set-telegram-users ID1,ID2    Replace the complete Telegram allowlist
  show-telegram-users           Display the current Telegram allowlist
  set-backend-api-key KEY       Update Hermes's 9router/OpenAI endpoint key
  restart-hermes                Recreate Hermes so config and MCP tools reload
  set-n8n-api-key               Validate and securely store an owner-created API key
  bootstrap-n8n                 Create/publish managed MCP and hosted-chat workflows
  reconcile-n8n                 Reconcile existing stack-owned n8n objects
  verify-n8n                    Verify managed n8n state and private connectivity
  rotate-n8n-token              Atomically rotate the MCP bearer credential
  remove-n8n-bootstrap-key      Remove the stored owner API key, retaining state
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
    printf '%s\n' '9) Change Smart Router mode'
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
        read -r -p 'Service (all/hermes/9router/smart-router/webui/n8n/caddy) [all]: ' service
        if [[ -n "$service" && "$service" != all ]]; then
          "$ROOT_DIR/manage.sh" logs "$service" || true
        else
          "$ROOT_DIR/manage.sh" logs || true
        fi
        ;;
      8) exec "$ROOT_DIR/install.sh" ;;
      9)
        read -r -p 'Smart Router mode (observe/route) [observe]: ' value
        "$ROOT_DIR/manage.sh" set-router-mode "${value:-observe}"
        ;;
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

env_value() {
  local file="$1" key="$2" value="" count
  [[ -f "$file" ]] || return 0
  count="$(grep -c "^${key}=" "$file" || true)"
  if (( count > 1 )); then
    printf 'Duplicate %s entries in %s are unsafe; keep exactly one value.\n' \
      "$key" "${file#$ROOT_DIR/}" >&2
    return 1
  fi
  value="$(sed -n "s/^${key}=//p" "$file")"
  value="${value#\"}"; value="${value%\"}"
  printf '%s' "$value"
}

require_profiles() {
  local profiles required
  profiles="$(env_value "$ENV_FILE" COMPOSE_PROFILES)"
  for required in "$@"; do
    [[ ",$profiles," == *",$required,"* ]] || {
      printf '%s is not selected. Run ./manage.sh configure first.\n' "$required" >&2
      exit 1
    }
  done
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "${1:-32}"
  else
    od -An -N "${1:-32}" -tx1 /dev/urandom | tr -d ' \n'
  fi
}

# The reconciler and verifier containers run --cap-drop ALL, so their uid has no
# CAP_DAC_OVERRIDE and cannot traverse a mode-0700 /state owned by anyone else.
# Keep the directory and its secrets owned by whoever invokes manage.sh.
ensure_stack_secrets_dir() {
  local owner
  mkdir -p "$STACK_SECRETS_DIR"
  chmod 700 "$STACK_SECRETS_DIR"
  owner="$(stat -c '%u:%g' "$STACK_SECRETS_DIR")"
  if [[ "$owner" != "$(id -u):$(id -g)" ]]; then
    chown -R "$(id -u):$(id -g)" "$STACK_SECRETS_DIR" 2>/dev/null || {
      printf 'data/stack-secrets is owned by %s; rerun as that user or fix its ownership.\n' \
        "$owner" >&2
      return 1
    }
  fi
}

write_n8n_bootstrap_key() {
  local key="$1" tmp
  ensure_stack_secrets_dir || return 1
  if [[ -e "$N8N_BOOTSTRAP_ENV" && ( ! -f "$N8N_BOOTSTRAP_ENV" || -L "$N8N_BOOTSTRAP_ENV" ) ]]; then
    printf 'Refusing unsafe n8n bootstrap secret path.\n' >&2
    return 1
  fi
  tmp="$(mktemp "$STACK_SECRETS_DIR/n8n-bootstrap.env.tmp.XXXXXX")"
  printf 'N8N_API_KEY=%s\n' "$key" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$N8N_BOOTSTRAP_ENV"
}

n8n_api_key() {
  env_value "$N8N_BOOTSTRAP_ENV" N8N_API_KEY
}

n8n_api_check() {
  local key="$1" image env_file status
  image="$(env_value "$ENV_FILE" N8N_IMAGE)"; image="${image:-n8nio/n8n:latest}"
  ensure_stack_secrets_dir || return 1
  env_file="$(mktemp "$STACK_SECRETS_DIR/n8n-api-check.env.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$env_file")
  chmod 600 "$env_file"
  printf 'N8N_API_KEY=%s\n' "$key" > "$env_file"
  if "${DOCKER[@]}" run --rm --network hermes-9router-net \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --env-file "$env_file" --entrypoint node "$image" -e '
      fetch("http://n8n:5678/api/v1/workflows?limit=1", {
        headers: {"X-N8N-API-KEY": process.env.N8N_API_KEY},
      }).then(async response => {
        if (!response.ok) throw new Error(`n8n API returned ${response.status}`);
        return response.json();
      }).then(() => process.exit(0)).catch(error => {
        console.error(error.message); process.exit(1);
      });'; then
    status=0
  else
    status=$?
  fi
  rm -f -- "$env_file"
  return "$status"
}

provision_n8n_router_key() {
  local output key
  output="$(compose exec -T -e PROVISION_HERMES=false -e PROVISION_OPENWEBUI=false \
    -e PROVISION_SMART_ROUTER=false -e PROVISION_N8N=true nine-router \
    node --input-type=module < "$ROOT_DIR/scripts/bootstrap-openwebui.mjs")"
  key="$(sed -n 's/^N8N_API_KEY=//p' <<< "$output" | tail -n1)"
  [[ -n "$key" ]] || { printf '9router did not return the dedicated n8n key.\n' >&2; return 1; }
  printf '%s' "$key"
}

run_n8n_reconciler_with_token() {
  local mcp_token="$1" previous_mcp_token="${2:-$1}" api_key router_key image env_file status
  api_key="$(n8n_api_key)"
  [[ -n "$api_key" ]] || {
    printf 'No n8n bootstrap API key is stored. Run ./manage.sh set-n8n-api-key.\n' >&2
    return 1
  }
  router_key="$(provision_n8n_router_key)" || return 1
  ensure_stack_secrets_dir || return 1
  if [[ -e "$N8N_BOOTSTRAP_STATE" ]]; then
    [[ -f "$N8N_BOOTSTRAP_STATE" && ! -L "$N8N_BOOTSTRAP_STATE" ]] || {
      printf 'Refusing unsafe n8n bootstrap state path.\n' >&2
      return 1
    }
    chmod 600 "$N8N_BOOTSTRAP_STATE"
  fi
  env_file="$(mktemp "$STACK_SECRETS_DIR/n8n-reconcile.env.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$env_file")
  chmod 600 "$env_file"
  {
    printf 'N8N_API_URL=http://n8n:5678/api/v1\n'
    printf 'N8N_API_KEY=%s\n' "$api_key"
    printf 'N8N_MCP_TOKEN=%s\n' "$mcp_token"
    printf 'N8N_PREVIOUS_MCP_TOKEN=%s\n' "$previous_mcp_token"
    printf 'NINEROUTER_API_KEY=%s\n' "$router_key"
    printf 'N8N_STATE_FILE=/state/n8n-bootstrap-state.json\n'
  } > "$env_file"
  image="$(env_value "$ENV_FILE" N8N_IMAGE)"; image="${image:-n8nio/n8n:latest}"
  if "${DOCKER[@]}" run --rm --network hermes-9router-net \
    --user "$(id -u):$(id -g)" \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --tmpfs /tmp:size=16m,mode=1777 \
    -v "$ROOT_DIR/scripts:/stack/scripts:ro" \
    -v "$STACK_SECRETS_DIR:/state" \
    --env-file "$env_file" \
    --entrypoint node "$image" \
    /stack/scripts/bootstrap-n8n.mjs; then
    status=0
  else
    status=$?
  fi
  rm -f -- "$env_file"
  return "$status"
}

run_n8n_reconciler() {
  local mcp_token
  mcp_token="$(env_value "$HERMES_ENV" N8N_MCP_TOKEN)"
  [[ -n "$mcp_token" ]] || {
    printf 'No MCP token is configured. Run ./manage.sh configure and enable the n8n MCP bridge.\n' >&2
    return 1
  }
  run_n8n_reconciler_with_token "$mcp_token"
}

run_n8n_verifier() {
  local api_key mcp_token mcp_url image env_file status
  [[ -f "$N8N_BOOTSTRAP_STATE" && ! -L "$N8N_BOOTSTRAP_STATE" ]] || {
    printf 'Managed n8n state is missing or unsafe; run bootstrap-n8n.\n' >&2
    return 1
  }
  mcp_token="$(env_value "$HERMES_ENV" N8N_MCP_TOKEN)"
  mcp_url="$(env_value "$HERMES_ENV" N8N_MCP_URL)"
  [[ -n "$mcp_token" && -n "$mcp_url" ]] || {
    printf 'Hermes n8n MCP configuration is incomplete. Run ./manage.sh configure.\n' >&2
    return 1
  }
  api_key="$(n8n_api_key)"
  ensure_stack_secrets_dir || return 1
  env_file="$(mktemp "$STACK_SECRETS_DIR/n8n-verify.env.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$env_file")
  chmod 600 "$env_file"
  {
    printf 'N8N_API_URL=http://n8n:5678/api/v1\n'
    [[ -n "$api_key" ]] && printf 'N8N_API_KEY=%s\n' "$api_key"
    printf 'N8N_MCP_URL=%s\n' "$mcp_url"
    printf 'N8N_MCP_TOKEN=%s\n' "$mcp_token"
    printf 'N8N_STATE_FILE=/state/n8n-bootstrap-state.json\n'
    printf 'SMART_ROUTER_URL=http://smart-router:8080\n'
  } > "$env_file"
  image="$(env_value "$ENV_FILE" N8N_IMAGE)"; image="${image:-n8nio/n8n:latest}"
  if "${DOCKER[@]}" run --rm --network hermes-9router-net \
    --user "$(id -u):$(id -g)" \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --tmpfs /tmp:size=16m,mode=1777 \
    -v "$ROOT_DIR/scripts:/stack/scripts:ro" \
    -v "$STACK_SECRETS_DIR:/state:ro" \
    --env-file "$env_file" \
    --entrypoint node "$image" \
    /stack/scripts/verify-n8n.mjs; then
    status=0
  else
    status=$?
  fi
  rm -f -- "$env_file"
  return "$status"
}

check_hermes_file() {
  local path="$1" label="$2" container_path
  [[ -f "$path" ]] || return 0
  container_path="/opt/data/${path#"$ROOT_DIR/data/hermes/"}"
  if compose exec -T hermes setpriv --reuid=hermes --regid=hermes --clear-groups \
    test -r "$container_path" >/dev/null 2>&1; then
    printf '%s: readable by Hermes gateway\n' "$label"
  else
    printf 'WARNING: %s is not readable by the Hermes gateway user. Run ./manage.sh configure to repair ownership.\n' "$label"
  fi
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
      smart-router|router) compose logs -f --tail=100 smart-router ;;
      webui|open-webui) compose logs -f --tail=100 open-webui ;;
      n8n) compose logs -f --tail=100 n8n ;;
      caddy) compose logs -f --tail=100 caddy ;;
      *) printf 'Choose hermes, 9router, smart-router, webui, n8n, or caddy.\n' >&2; exit 2 ;;
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
    profiles="$(sed -n 's/^COMPOSE_PROFILES=//p' "$ENV_FILE")"
    if [[ "$profiles" == *hermes* ]]; then
      check_hermes_file "$ROOT_DIR/data/hermes/config.yaml" "Hermes config"
      check_hermes_file "$HERMES_ENV" "Hermes secret file"
      if compose exec -T hermes sh -c \
        'test -f /opt/data/plugins/stack-package-policy/plugin.yaml && test ! -w /opt/data/plugins/stack-package-policy/plugin.yaml' \
        >/dev/null 2>&1; then
        printf 'Hermes package policy plugin: mounted read-only\n'
      else
        printf 'WARNING: stack-package-policy is missing or writable inside Hermes.\n'
      fi
      if grep -q '^[[:space:]]*- stack-package-policy[[:space:]]*$' "$ROOT_DIR/data/hermes/config.yaml"; then
        printf 'Hermes package policy plugin: enabled in config\n'
      else
        printf 'WARNING: stack-package-policy is not enabled in Hermes config.\n'
      fi
      if compose exec -T hermes sh -lc '
        cd /opt/hermes
        /opt/hermes/.venv/bin/hermes plugins list --enabled --user --plain 2>/dev/null \
          | grep -Eq "enabled[[:space:]]+user[[:space:]]+[^[:space:]]+[[:space:]]+stack-package-policy"
      '; then
        printf 'Hermes package policy plugin: registered at runtime\n'
      else
        printf 'WARNING: stack-package-policy is not registered as an enabled user plugin.\n'
      fi
      if compose exec -T hermes sh -lc '
        cd /opt/hermes
        tools="$(/opt/hermes/.venv/bin/hermes tools list --platform telegram 2>/dev/null)"
        printf "%s\n" "$tools" | grep -Eq "disabled[[:space:]]+terminal([[:space:]]|$)" \
          && printf "%s\n" "$tools" | grep -Eq "disabled[[:space:]]+code_execution([[:space:]]|$)" \
          && printf "%s\n" "$tools" | grep -Eq "enabled[[:space:]]+stack_packages([[:space:]]|$)"
      '; then
        printf 'Hermes package boundary: terminal/code execution disabled; broker enabled\n'
      else
        printf 'WARNING: effective Hermes tool registry does not enforce the package boundary.\n'
      fi
    fi
    if [[ "$profiles" == *smart-router* ]]; then
      compose exec -T smart-router python -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=5)'
      compose exec -T smart-router python -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8080/ready", timeout=5)'
      printf 'Smart Router health/readiness: valid\n'
    fi
    if [[ -d "$STACK_SECRETS_DIR" ]]; then
      secret_dir_mode="$(stat -c '%a' "$STACK_SECRETS_DIR")"
      printf 'Stack secret directory mode: %s\n' "$secret_dir_mode"
      [[ "$secret_dir_mode" == 700 ]] || printf 'WARNING: expected data/stack-secrets mode 700\n'
      # The bootstrap containers drop all capabilities, so a mismatched owner
      # makes mode 700 unreadable to them even when manage.sh runs as root.
      secret_dir_owner="$(stat -c '%u:%g' "$STACK_SECRETS_DIR")"
      if [[ "$secret_dir_owner" == "$(id -u):$(id -g)" ]]; then
        printf 'Stack secret directory owner: matches the invoking user\n'
      else
        printf 'WARNING: data/stack-secrets is owned by %s, not %s:%s; n8n bootstrap will fail with EACCES\n' \
          "$secret_dir_owner" "$(id -u)" "$(id -g)"
      fi
      if [[ -f "$N8N_BOOTSTRAP_ENV" ]]; then
        bootstrap_mode="$(stat -c '%a' "$N8N_BOOTSTRAP_ENV")"
        printf 'n8n bootstrap secret mode: %s\n' "$bootstrap_mode"
        [[ "$bootstrap_mode" == 600 ]] || printf 'WARNING: expected n8n bootstrap secret mode 600\n'
      fi
    fi
    if [[ "$profiles" == *n8n* ]]; then
      compose exec -T n8n node -e \
        "fetch('http://127.0.0.1:5678/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
      printf 'n8n health: valid\n'
      if [[ "$profiles" == *hermes* ]] && grep -q '^N8N_MCP_URL=' "$HERMES_ENV" 2>/dev/null; then
        mcp_url="$(sed -n 's/^N8N_MCP_URL=//p' "$HERMES_ENV" | head -n1)"
        mcp_url="${mcp_url%\"}"; mcp_url="${mcp_url#\"}"
        # 401 means the endpoint is live and rejecting an unauthenticated probe;
        # 404 means the workflow exists but was never published.
        code="$(compose exec -T hermes sh -c \
          "curl -s -o /dev/null -w '%{http_code}' --max-time 5 '$mcp_url'" 2>/dev/null || true)"
        case "$code" in
          200|401|403|406) printf 'Hermes -> n8n MCP endpoint: reachable (HTTP %s)\n' "$code" ;;
          404) printf 'Hermes -> n8n MCP endpoint: HTTP 404. Publish the MCP Server Trigger workflow in n8n.\n' ;;
          000|"") printf 'WARNING: Hermes cannot reach %s over the Docker network.\n' "$mcp_url" ;;
          *) printf 'Hermes -> n8n MCP endpoint: unexpected HTTP %s\n' "$code" ;;
        esac
      fi
    fi
    if [[ "$profiles" == *caddy* ]]; then
      compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile
    fi
    ;;
  configure) exec "$ROOT_DIR/install.sh" ;;
  set-router-mode)
    mode="${2:-}"
    [[ "$mode" == observe || "$mode" == route ]] || {
      printf 'Mode must be observe or route.\n' >&2
      exit 2
    }
    profiles="$(sed -n 's/^COMPOSE_PROFILES=//p' "$ENV_FILE")"
    [[ ",$profiles," == *,smart-router,* ]] || {
      printf 'Smart Router is not selected. Run ./manage.sh configure first.\n' >&2
      exit 1
    }
    replace_env_value "$ENV_FILE" SMART_ROUTER_MODE "$mode"
    compose up -d nine-router smart-router
    ready=false
    for _ in {1..60}; do
      if compose exec -T smart-router python -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8080/ready", timeout=5)' \
        >/dev/null 2>&1; then
        ready=true
        break
      fi
      sleep 2
    done
    [[ "$ready" == true ]] || {
      printf 'Smart Router was recreated but did not become ready.\n' >&2
      exit 1
    }
    printf 'Smart Router mode changed to %s and is ready.\n' "$mode"
    ;;
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
  restart-hermes)
    profiles="$(sed -n 's/^COMPOSE_PROFILES=//p' "$ENV_FILE")"
    [[ "$profiles" == *hermes* ]] || { printf 'Hermes is not selected.\n' >&2; exit 1; }
    restart_hermes
    printf 'Hermes recreated; config.yaml and MCP tools were reloaded.\n'
    ;;
  set-n8n-api-key)
    require_profiles n8n
    if [[ -n "${2:-}" ]]; then
      printf 'For safety, do not pass the n8n API key in argv. Run without an argument.\n' >&2
      exit 2
    fi
    read -r -s -p 'n8n owner API key: ' key
    printf '\n' >&2
    [[ -n "$key" && "$key" != *[[:space:]]* ]] || {
      printf 'A non-empty API key without whitespace is required.\n' >&2; exit 2;
    }
    n8n_api_check "$key" || { printf 'n8n rejected the API key; nothing was stored.\n' >&2; exit 1; }
    write_n8n_bootstrap_key "$key"
    printf 'n8n bootstrap API key validated and stored with mode 0600.\n'
    ;;
  bootstrap-n8n|reconcile-n8n)
    require_profiles 9router smart-router hermes n8n
    run_n8n_reconciler
    restart_hermes
    "$ROOT_DIR/manage.sh" verify-n8n
    ;;
  verify-n8n)
    require_profiles smart-router hermes n8n
    run_n8n_verifier
    ;;
  rotate-n8n-token)
    require_profiles 9router smart-router hermes n8n
    [[ -f "$HERMES_ENV" ]] || { printf 'Hermes is not configured.\n' >&2; exit 1; }
    old_token="$(env_value "$HERMES_ENV" N8N_MCP_TOKEN)"
    [[ -n "$old_token" ]] || { printf 'No MCP token is configured. Run bootstrap-n8n first.\n' >&2; exit 1; }
    new_token="$(random_hex 32)"
    if run_n8n_reconciler_with_token "$new_token" "$old_token"; then
      replace_env_value "$HERMES_ENV" N8N_MCP_TOKEN "$new_token"
      if restart_hermes && "$ROOT_DIR/manage.sh" verify-n8n; then
        printf 'n8n MCP bearer token rotated without printing it.\n'
      else
        if run_n8n_reconciler_with_token "$old_token" "$new_token"; then
          replace_env_value "$HERMES_ENV" N8N_MCP_TOKEN "$old_token"
          if restart_hermes && "$ROOT_DIR/manage.sh" verify-n8n; then
            printf 'Rotation verification failed; the prior n8n credential and Hermes token were restored and verified.\n' >&2
          else
            printf 'Rotation verification failed; the prior values were restored, but their operation could not be verified. Manual recovery is required.\n' >&2
          fi
        else
          printf 'Rotation verification failed, and n8n credential rollback also failed. Hermes retains the new token; manual recovery is required.\n' >&2
        fi
        exit 1
      fi
    else
      printf 'Rotation failed before Hermes changed; the prior token remains active.\n' >&2
      exit 1
    fi
    ;;
  remove-n8n-bootstrap-key)
    if [[ -f "$N8N_BOOTSTRAP_ENV" ]]; then
      rm -f "$N8N_BOOTSTRAP_ENV"
      printf 'Stored n8n API key removed. Managed IDs and fingerprints were retained.\n'
    else
      printf 'No stored n8n API key was present.\n'
    fi
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
