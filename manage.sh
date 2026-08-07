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
    rm -rf -- "$file"
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
  set-agent-max-turns N         Set the agent iteration budget (10-500; 90 recommended)
  set-upstream-terminal STATE   Enable or disable upstream terminal/code_execution
  execution-status              Show execution features, users, and SSH profiles
  enable-execution FEATURE      Enable sandbox, ssh, docker, or all
  disable-execution FEATURE     Disable sandbox, ssh, docker, or all
  set-execution-users IDS       Replace execution users (Telegram allowlist subset)
  add-execution-user ID         Add one execution user
  remove-execution-user ID      Remove one execution user
  add-ssh-profile NAME          Create/import and pin one SSH profile
  verify-ssh-profile NAME       Verify pinned host key and SSH access
  remove-ssh-profile NAME       Remove one local SSH profile
  set-execution-approval-bot-token Silently configure the dedicated approval bot token
  rotate-execution-broker-secret Rotate control secret and revoke pending operations
  purge-execution               Delete execution state and SSH keys after confirmation
  set-n8n-api-key               Validate and securely store an owner-created API key
  set-n8n-instance-mcp-token    Validate/store an n8n-generated Instance MCP token
  remove-n8n-instance-mcp-token Remove a stored Instance token when mode is not instance
  set-n8n-mcp-mode MODE         Select instance, trigger, or off
  bootstrap-n8n                 Reconcile hosted chat and the selected MCP mode
  reconcile-n8n                 Reconcile existing stack-owned n8n objects
  verify-n8n                    Verify hosted chat and the selected MCP mode
  rotate-n8n-trigger-token      Atomically rotate the Trigger-mode bearer credential
  rotate-n8n-token              Compatibility alias for Trigger-token rotation
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
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
    printf 'Unsafe environment key: %s\n' "$key" >&2
    return 1
  }
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  if ! printf '%s' "$value" | python3 /dev/fd/3 "$file" "$key" 3<<'PY' > "$tmp"
import sys

path, key = sys.argv[1:]
value = sys.stdin.read()
lines = open(path, encoding="utf-8").read().splitlines()
indexes = [index for index, line in enumerate(lines) if line.startswith(f"{key}=")]
if len(indexes) > 1:
    raise SystemExit(f"Duplicate {key} entries are unsafe")
replacement = f"{key}={value}"
if indexes:
    lines[indexes[0]] = replacement
else:
    lines.append(replacement)
print("\n".join(lines) + "\n", end="")
PY
  then
    rm -f -- "$tmp"
    return 1
  fi
  chmod --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  chown --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv "$tmp" "$file"
}

remove_env_values() {
  local file="$1" tmp key pattern=""
  shift
  for key in "$@"; do
    [[ -z "$pattern" ]] || pattern+="|"
    pattern+="${key}="
  done
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  grep -v -E "^(${pattern})" "$file" > "$tmp" || true
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
}

n8n_mcp_mode() {
  local mode legacy
  mode="$(env_value "$ENV_FILE" N8N_MCP_MODE)" || return 1
  if [[ -z "$mode" ]]; then
    legacy="$(env_value "$HERMES_ENV" N8N_MCP_TOKEN)" || return 1
    if [[ -n "$legacy" ]]; then mode=trigger; else mode=off; fi
  fi
  [[ "$mode" == instance || "$mode" == trigger || "$mode" == off ]] || {
    printf 'N8N_MCP_MODE must be instance, trigger, or off.\n' >&2
    return 1
  }
  printf '%s' "$mode"
}

migrate_legacy_trigger_env() {
  local legacy
  legacy="$(env_value "$HERMES_ENV" N8N_MCP_TOKEN)" || return 1
  if [[ -n "$legacy" && -z "$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN)" ]]; then
    replace_env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN "$legacy"
  fi
  replace_env_value "$HERMES_ENV" N8N_TRIGGER_MCP_URL '"http://n8n:5678/mcp/hermes"'
  replace_env_value "$HERMES_ENV" N8N_INSTANCE_MCP_URL '"http://n8n:5678/mcp-server/http"'
}

finish_legacy_trigger_env_migration() {
  remove_env_values "$HERMES_ENV" N8N_MCP_URL N8N_MCP_PATH N8N_MCP_TOKEN
}

render_managed_n8n_mcp_entry() {
  local mode="$1"
  case "$mode" in
    instance) url_var=N8N_INSTANCE_MCP_URL; token_var=N8N_INSTANCE_MCP_TOKEN ;;
    trigger) url_var=N8N_TRIGGER_MCP_URL; token_var=N8N_TRIGGER_MCP_TOKEN ;;
    off) return 0 ;;
  esac
  printf '%s\n' \
    '  # >>> hermes-stack n8n mcp (managed) >>>' \
    '  n8n:' \
    "    url: \"\${$url_var}\"" \
    '    headers:' \
    "      Authorization: \"Bearer \${$token_var}\"" \
    '  # <<< hermes-stack n8n mcp (managed) <<<'
}

set_hermes_n8n_mcp_entry() {
  local mode="$1" file="$ROOT_DIR/data/hermes/config.yaml" tmp entry
  [[ -f "$file" ]] || { printf 'Hermes config is missing.\n' >&2; return 1; }
  entry="$(render_managed_n8n_mcp_entry "$mode")"
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  if ! python3 - "$file" "$mode" "$entry" > "$tmp" <<'PY'
import re
import sys

path, mode, entry = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines()
opens = [i for i, line in enumerate(lines) if line == "  # >>> hermes-stack n8n mcp (managed) >>>"]
closes = [i for i, line in enumerate(lines) if line == "  # <<< hermes-stack n8n mcp (managed) <<<"]
top_opens = [i for i, line in enumerate(lines) if line == "# >>> hermes-stack n8n mcp (managed) >>>"]
top_closes = [i for i, line in enumerate(lines) if line == "# <<< hermes-stack n8n mcp (managed) <<<"]
if len(opens) != len(closes) or len(top_opens) != len(top_closes) or len(opens) + len(top_opens) > 1:
    raise SystemExit("Hermes config has incomplete or duplicate managed n8n MCP markers")
replacement = entry.splitlines() if entry else []
if top_opens:
    start, end = top_opens[0], top_closes[0]
    block = ["mcp_servers:", *replacement] if replacement else []
    lines[start:end + 1] = block
elif opens:
    start, end = opens[0], closes[0]
    lines[start:end + 1] = replacement
elif replacement:
    roots = [i for i, line in enumerate(lines) if re.fullmatch(r"mcp_servers:\s*", line)]
    if len(roots) > 1:
        raise SystemExit("Duplicate top-level mcp_servers sections are unsafe")
    if roots:
        lines[roots[0] + 1:roots[0] + 1] = replacement
    else:
        if lines and lines[-1]: lines.append("")
        lines.extend(["mcp_servers:", *replacement])
print("\n".join(lines) + "\n", end="")
PY
  then
    rm -f -- "$tmp"
    return 1
  fi
  chmod --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  chown --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv "$tmp" "$file"
}

restart_hermes() {
  compose up -d --no-deps --force-recreate hermes
}

# agent.max_turns in config.yaml is authoritative: the gateway bridges it into
# HERMES_MAX_ITERATIONS, which produces the "Iteration budget exhausted" notice.
AGENT_MAX_TURNS_MIN=10
AGENT_MAX_TURNS_MAX=500

hermes_agent_max_turns() {
  local file="$ROOT_DIR/data/hermes/config.yaml"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
in_agent = False
for line in lines:
    if re.fullmatch(r"agent:\s*", line):
        in_agent = True
        continue
    if in_agent:
        if line and not line[0].isspace():
            in_agent = False
            continue
        match = re.fullmatch(r"\s+max_turns:\s*(\d+)\s*", line)
        if match:
            print(match.group(1))
            break
PY
}

set_hermes_agent_max_turns() {
  local value="$1" file="$ROOT_DIR/data/hermes/config.yaml" tmp
  [[ -f "$file" && ! -L "$file" ]] || {
    printf 'Hermes config is missing or unsafe.\n' >&2
    return 1
  }
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  if ! python3 - "$file" "$value" > "$tmp" <<'PY'
import re, sys
path, value = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines()
roots = [i for i, line in enumerate(lines) if re.fullmatch(r"agent:\s*", line)]
if len(roots) > 1:
    raise SystemExit("Duplicate top-level agent sections are unsafe")
if roots:
    start = roots[0]
    end = start + 1
    while end < len(lines) and (not lines[end] or lines[end][0].isspace()):
        end += 1
    body = lines[start + 1:end]
    replaced = False
    for i, line in enumerate(body):
        if re.fullmatch(r"(\s+)max_turns:\s*\d+\s*", line):
            indent = re.match(r"\s+", line).group(0)
            body[i] = f"{indent}max_turns: {value}"
            replaced = True
            break
    if not replaced:
        body.insert(0, f"  max_turns: {value}")
    lines[start + 1:end] = body
else:
    if lines and lines[-1]:
        lines.append("")
    lines.extend(["agent:", f"  max_turns: {value}"])
print("\n".join(lines) + "\n", end="")
PY
  then
    rm -f -- "$tmp"
    return 1
  fi
  chmod --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  chown --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv "$tmp" "$file"
}

# Upstream terminal/code_execution run as the gateway uid inside hermes-agent,
# which owns /opt/data/.env. Enabling them is a deliberate local trade of
# isolation for capability, so it lives behind an explicit command.
set_upstream_terminal() {
  local state="$1" file="$ROOT_DIR/data/hermes/config.yaml" tmp
  [[ -f "$file" && ! -L "$file" ]] || {
    printf 'Hermes config is missing or unsafe.\n' >&2
    return 1
  }
  tmp="$(mktemp "$file.tmp.XXXXXX")"
  if ! python3 - "$file" "$state" > "$tmp" <<'PY'
import re, sys
path, state = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines()
roots = [i for i, line in enumerate(lines) if re.fullmatch(r"agent:\s*", line)]
if len(roots) > 1:
    raise SystemExit("Duplicate top-level agent sections are unsafe")
names = ("terminal", "code_execution")
if roots:
    start = roots[0]
    end = start + 1
    while end < len(lines) and (not lines[end] or lines[end][0].isspace()):
        end += 1
else:
    if lines and lines[-1]:
        lines.append("")
    lines.append("agent:")
    start, end = len(lines) - 1, len(lines)
# Drop any existing disabled_toolsets block, preserving every other agent key.
key = next((i for i in range(start + 1, end)
            if re.fullmatch(r"\s+disabled_toolsets:.*", lines[i])), None)
if key is not None:
    stop = key + 1
    while stop < end and re.fullmatch(r"\s+-\s*[A-Za-z0-9_-]+\s*", lines[stop]):
        stop += 1
    del lines[key:stop]
    end -= stop - key
block = ["  disabled_toolsets: []"] if state == "enabled" else \
        ["  disabled_toolsets:", *(f"    - {name}" for name in names)]
# Append after the section's last real key, not after the blank lines that
# separate it from the next section, so the file stays readable.
insert_at = end
while insert_at > start + 1 and not lines[insert_at - 1].strip():
    insert_at -= 1
lines[insert_at:insert_at] = block
print("\n".join(lines) + "\n", end="")
PY
  then
    rm -f -- "$tmp"
    return 1
  fi
  chmod --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  chown --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv "$tmp" "$file"
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
  if [[ -e "$STACK_SECRETS_DIR" || -L "$STACK_SECRETS_DIR" ]]; then
    [[ -d "$STACK_SECRETS_DIR" && ! -L "$STACK_SECRETS_DIR" ]] || {
      printf 'Refusing unsafe data/stack-secrets path; expected a real directory.\n' >&2
      return 1
    }
  else
    mkdir -p "$STACK_SECRETS_DIR"
  fi
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

execution_root() { printf '%s/execution' "$STACK_SECRETS_DIR"; }

ensure_execution_paths() {
  local root file
  ensure_stack_secrets_dir || return 1
  root="$(execution_root)"
  for file in "$root" "$root/docker-state" "$root/ssh-state" "$root/approver-state" "$root/ssh"; do
    [[ ! -L "$file" ]] || { printf 'Refusing unsafe execution symlink: %s\n' "$file" >&2; return 1; }
    install -d -m 0700 "$file"
  done
  for file in "$root/control-secret" "$root/approval-request-secret" \
    "$root/approval-signing-key.pem" "$root/approval-public-key.pem" \
    "$root/approval-bot-token" "$root/users"; do
    [[ ! -L "$file" && ( ! -e "$file" || -f "$file" ) ]] || {
      printf 'Refusing unsafe execution policy path: %s\n' "$file" >&2; return 1;
    }
    [[ -e "$file" ]] || install -m 0600 /dev/null "$file"
    chmod 600 "$file"
  done
  install -d -m 0700 "$ROOT_DIR/data/execution-workspace"
}

execution_features() { env_value "$ENV_FILE" EXECUTION_FEATURES; }
execution_users() { [[ -f "$(execution_root)/users" ]] && tr -d '[:space:]' < "$(execution_root)/users" || true; }

telegram_users() {
  local value
  value="$(env_value "$HERMES_ENV" TELEGRAM_ALLOWED_USERS)"
  value="${value#[}"; value="${value%]}"; value="${value//\"/}"; value="${value// /}"
  printf '%s' "$value"
}

execution_users_valid() {
  local users="$1" allowed user
  valid_ids "$users" || return 1
  allowed=",$(telegram_users),"
  IFS=, read -ra entries <<< "$users"
  for user in "${entries[@]}"; do [[ "$allowed" == *",$user,"* ]] || return 1; done
}

write_execution_users() {
  local users="$1" root tmp
  ensure_execution_paths || return 1
  root="$(execution_root)"
  tmp="$(mktemp "$root/users.tmp.XXXXXX")"
  printf '%s\n' "$users" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$root/users"
}

rotate_execution_generation() {
  local current workspace
  current="$(env_value "$ENV_FILE" EXECUTION_POLICY_GENERATION)"; current="${current:-0}"
  workspace="$(env_value "$ENV_FILE" EXECUTION_WORKSPACE_GENERATION)"; workspace="${workspace:-0}"
  [[ "$current" =~ ^[0-9]+$ ]] || current=0
  [[ "$workspace" =~ ^[0-9]+$ ]] || workspace=0
  replace_env_value "$ENV_FILE" EXECUTION_POLICY_GENERATION "$((current + 1))"
  replace_env_value "$ENV_FILE" EXECUTION_WORKSPACE_GENERATION "$((workspace + 1))"
}

sync_execution_profiles() {
  local features profiles base
  features="$(execution_features)"
  profiles="$(env_value "$ENV_FILE" COMPOSE_PROFILES)"
  base="$(printf '%s' "$profiles" | tr ',' '\n' | grep -v -E '^execution-(docker|ssh|approval)$' | paste -sd, -)"
  if [[ -n "$features" ]]; then base="${base:+$base,}execution-approval"; fi
  [[ ",$features," == *,local,* || ",$features," == *,docker,* ]] \
    && base="${base:+$base,}execution-docker"
  [[ ",$features," == *,ssh,* ]] && base="${base:+$base,}execution-ssh"
  replace_env_value "$ENV_FILE" COMPOSE_PROFILES "$base"
}

apply_execution_features() {
  local features="$1"
  replace_env_value "$ENV_FILE" EXECUTION_FEATURES "$features"
  rotate_execution_generation
  sync_execution_profiles
  if [[ -n "$features" ]]; then
    compose build execution-approver execution-docker-broker execution-ssh-broker
  fi
  compose up -d --remove-orphans
}

set_execution_feature() {
  local requested="$1" enabled="$2" current item output=""
  [[ "$requested" == sandbox ]] && requested=local
  current="$(execution_features)"
  for item in local ssh docker; do
    if [[ "$enabled" == true && ( "$requested" == all || "$requested" == "$item" ) ]]; then
      [[ ",$current," == *",$item,"* ]] || output="${output:+$output,}$item"
    elif [[ "$enabled" != true && ( "$requested" == all || "$requested" == "$item" ) ]]; then
      continue
    elif [[ ",$current," == *",$item,"* ]]; then
      output="${output:+$output,}$item"
    fi
  done
  printf '%s' "$output"
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

n8n_instance_mcp_check() {
  local token="$1" image env_file status
  image="$(env_value "$ENV_FILE" N8N_IMAGE)"; image="${image:-n8nio/n8n:latest}"
  ensure_stack_secrets_dir || return 1
  env_file="$(mktemp "$STACK_SECRETS_DIR/n8n-instance-mcp-check.env.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$env_file")
  chmod 600 "$env_file"
  printf 'N8N_INSTANCE_MCP_TOKEN=%s\n' "$token" > "$env_file"
  if "${DOCKER[@]}" run --rm --network hermes-9router-net \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --env-file "$env_file" --entrypoint node "$image" -e '
      const url = "http://n8n:5678/mcp-server/http";
      const initialize = {jsonrpc:"2.0",id:1,method:"initialize",params:{
        protocolVersion:"2025-03-26",capabilities:{},
        clientInfo:{name:"hermes-n8n-token-validator",version:"1"}}};
      const baseHeaders = {Accept:"application/json, text/event-stream","Content-Type":"application/json"};
      const fail = message => { console.error(message); process.exit(1); };
      const messages = async response => {
        const text = await response.text();
        if (!text.trim()) return [];
        if ((response.headers.get("content-type") || "").includes("text/event-stream")) {
          return text.split(/\r?\n/).filter(line => line.startsWith("data:"))
            .map(line => line.slice(5).trim()).filter(value => value && value !== "[DONE]")
            .map(value => JSON.parse(value));
        }
        return [JSON.parse(text)];
      };
      (async () => {
        let session;
        let failure;
        try {
          const anonymous = await fetch(url,{method:"POST",headers:baseHeaders,
            body:JSON.stringify(initialize),redirect:"manual",signal:AbortSignal.timeout(15000)});
          await anonymous.body?.cancel();
          if (![401,403].includes(anonymous.status)) throw new Error("Instance MCP did not reject an unauthenticated request");
          const request = async body => {
            const response = await fetch(url,{method:"POST",headers:{...baseHeaders,
              Authorization:`Bearer ${process.env.N8N_INSTANCE_MCP_TOKEN}`,
              ...(session?{"Mcp-Session-Id":session}:{})},body:JSON.stringify(body),
              redirect:"manual",signal:AbortSignal.timeout(15000)});
            if (!response.ok) throw new Error(`Instance MCP returned HTTP ${response.status}`);
            session = response.headers.get("mcp-session-id") || session;
            return messages(response);
          };
          const initialized = await request(initialize);
          if (!initialized.some(item => item?.id === 1 && item?.result?.protocolVersion)) throw new Error("Instance MCP initialize failed");
          await request({jsonrpc:"2.0",method:"notifications/initialized",params:{}});
          const listed = await request({jsonrpc:"2.0",id:2,method:"tools/list",params:{}});
          const tools = listed.find(item => item?.id === 2)?.result?.tools;
          for (const name of ["search_workflows","get_workflow_details","execute_workflow",
            "publish_workflow","unpublish_workflow","list_credentials","search_executions"]) {
            if (!Array.isArray(tools) || !tools.some(tool => tool?.name === name)) throw new Error(`Instance MCP tool ${name} is missing`);
          }
        } catch (error) {
          failure = error;
        }
        if (session) {
          try {
            const closed = await fetch(url,{method:"DELETE",headers:{
              Authorization:`Bearer ${process.env.N8N_INSTANCE_MCP_TOKEN}`,"Mcp-Session-Id":session},
              redirect:"manual",signal:AbortSignal.timeout(15000)});
            if (!closed.ok) throw new Error(`Instance MCP session close returned HTTP ${closed.status}`);
          } catch (error) {
            failure ||= error;
          }
        }
        if (failure) throw failure;
      })().catch(error => fail(error.message));'; then
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
  local mcp_token="$1" previous_mcp_token="${2:-$1}" requested_mode="${3:-}" mode api_key router_key image env_file status
  local profiles router_base_url router_model previous_router_base_url state_dir state_tmp
  mode="${requested_mode:-$(n8n_mcp_mode)}"
  api_key="$(n8n_api_key)"
  [[ -n "$api_key" ]] || {
    printf 'No n8n bootstrap API key is stored. Run ./manage.sh set-n8n-api-key.\n' >&2
    return 1
  }
  router_key="$(provision_n8n_router_key)" || return 1
  profiles="$(env_value "$ENV_FILE" COMPOSE_PROFILES)"
  if [[ ",$profiles," == *,smart-router,* ]]; then
    router_base_url="http://smart-router:8080/v1"
    router_model="auto"
  else
    router_base_url="http://nine-router:20128/v1"
    router_model="ai"
  fi
  previous_router_base_url="$router_base_url"
  if [[ -f "$N8N_BOOTSTRAP_STATE" ]]; then
    previous_router_base_url="$(python3 - "$N8N_BOOTSTRAP_STATE" "$router_base_url" <<'PY'
import json
import sys
try:
    state = json.load(open(sys.argv[1], encoding="utf-8"))
    print(state.get("routerBaseUrl") or sys.argv[2])
except Exception:
    print(sys.argv[2])
PY
)"
  fi
  ensure_stack_secrets_dir || return 1
  if [[ -e "$N8N_BOOTSTRAP_STATE" ]]; then
    [[ -f "$N8N_BOOTSTRAP_STATE" && ! -L "$N8N_BOOTSTRAP_STATE" ]] || {
      printf 'Refusing unsafe n8n bootstrap state path.\n' >&2
      return 1
    }
    chmod 600 "$N8N_BOOTSTRAP_STATE"
  fi
  state_dir="$(mktemp -d "$STACK_SECRETS_DIR/n8n-reconcile-state.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$state_dir")
  chmod 700 "$state_dir"
  if [[ -f "$N8N_BOOTSTRAP_STATE" ]]; then
    cp --preserve=mode,timestamps "$N8N_BOOTSTRAP_STATE" "$state_dir/n8n-bootstrap-state.json"
  fi
  env_file="$(mktemp "$STACK_SECRETS_DIR/n8n-reconcile.env.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$env_file")
  chmod 600 "$env_file"
  {
    printf 'N8N_API_URL=http://n8n:5678/api/v1\n'
    printf 'N8N_API_KEY=%s\n' "$api_key"
    printf 'N8N_MCP_MODE=%s\n' "$mode"
    [[ -n "$mcp_token" ]] && printf 'N8N_TRIGGER_MCP_TOKEN=%s\n' "$mcp_token"
    [[ -n "$previous_mcp_token" ]] && printf 'N8N_PREVIOUS_TRIGGER_MCP_TOKEN=%s\n' "$previous_mcp_token"
    printf 'NINEROUTER_API_KEY=%s\n' "$router_key"
    printf 'N8N_ROUTER_BASE_URL=%s\n' "$router_base_url"
    printf 'N8N_PREVIOUS_ROUTER_BASE_URL=%s\n' "$previous_router_base_url"
    printf 'N8N_CHAT_MODEL=%s\n' "$router_model"
    printf 'N8N_STATE_FILE=/state/n8n-bootstrap-state.json\n'
  } > "$env_file"
  image="$(env_value "$ENV_FILE" N8N_IMAGE)"; image="${image:-n8nio/n8n:latest}"
  if "${DOCKER[@]}" run --rm --network hermes-9router-net \
    --user "$(id -u):$(id -g)" \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --tmpfs /tmp:size=16m,mode=1777 \
    -v "$ROOT_DIR/scripts:/stack/scripts:ro" \
    -v "$state_dir:/state" \
    --env-file "$env_file" \
    --entrypoint node "$image" \
    /stack/scripts/bootstrap-n8n.mjs; then
    status=0
    state_tmp="$(mktemp "$STACK_SECRETS_DIR/n8n-bootstrap-state.tmp.XXXXXX")"
    if cp "$state_dir/n8n-bootstrap-state.json" "$state_tmp"; then
      chmod 600 "$state_tmp"
      mv "$state_tmp" "$N8N_BOOTSTRAP_STATE"
    else
      rm -f -- "$state_tmp"
      status=1
    fi
  else
    status=$?
  fi
  rm -f -- "$env_file"
  rm -rf -- "$state_dir"
  return "$status"
}

run_n8n_reconciler() {
  local mode mcp_token
  mode="$(n8n_mcp_mode)" || return 1
  migrate_legacy_trigger_env || return 1
  mcp_token="$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN)"
  if [[ "$mode" == trigger && -z "$mcp_token" ]]; then
    printf 'No Trigger MCP token is configured. Run ./manage.sh configure and select Trigger mode.\n' >&2
    return 1
  fi
  run_n8n_reconciler_with_token "$mcp_token" "$mcp_token" "$mode"
}

run_n8n_verifier() {
  local api_key mode mcp_token="" mcp_url="" image env_file status profiles router_health_url state_dir
  [[ -f "$N8N_BOOTSTRAP_STATE" && ! -L "$N8N_BOOTSTRAP_STATE" ]] || {
    printf 'Managed n8n state is missing or unsafe; run bootstrap-n8n.\n' >&2
    return 1
  }
  mode="$(n8n_mcp_mode)" || return 1
  migrate_legacy_trigger_env || return 1
  case "$mode" in
    instance)
      mcp_token="$(env_value "$HERMES_ENV" N8N_INSTANCE_MCP_TOKEN)"
      mcp_url="$(env_value "$HERMES_ENV" N8N_INSTANCE_MCP_URL)"
      ;;
    trigger)
      mcp_token="$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN)"
      mcp_url="$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_URL)"
      ;;
  esac
  if [[ "$mode" != off && ( -z "$mcp_token" || -z "$mcp_url" ) ]]; then
    printf 'Hermes n8n %s MCP configuration is incomplete.\n' "$mode" >&2
    return 1
  fi
  api_key="$(n8n_api_key)"
  profiles="$(env_value "$ENV_FILE" COMPOSE_PROFILES)"
  if [[ ",$profiles," == *,smart-router,* ]]; then
    router_health_url="http://smart-router:8080/ready"
  else
    router_health_url="http://nine-router:20128/api/health"
  fi
  ensure_stack_secrets_dir || return 1
  env_file="$(mktemp "$STACK_SECRETS_DIR/n8n-verify.env.tmp.XXXXXX")"
  TEMP_SECRET_FILES+=("$env_file")
  chmod 600 "$env_file"
  {
    printf 'N8N_API_URL=http://n8n:5678/api/v1\n'
    [[ -n "$api_key" ]] && printf 'N8N_API_KEY=%s\n' "$api_key"
    printf 'N8N_MCP_MODE=%s\n' "$mode"
    case "$mode" in
      instance)
        printf 'N8N_INSTANCE_MCP_URL=%s\n' "$mcp_url"
        printf 'N8N_INSTANCE_MCP_TOKEN=%s\n' "$mcp_token"
        ;;
      trigger)
        printf 'N8N_TRIGGER_MCP_URL=%s\n' "$mcp_url"
        printf 'N8N_TRIGGER_MCP_TOKEN=%s\n' "$mcp_token"
        ;;
    esac
    printf 'N8N_STATE_FILE=/state/n8n-bootstrap-state.json\n'
    printf 'N8N_ROUTER_HEALTH_URL=%s\n' "$router_health_url"
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
      configured_turns="$(hermes_agent_max_turns || true)"
      effective_turns="$(compose exec -T hermes sh -lc 'printf "%s" "${HERMES_MAX_ITERATIONS:-}"' 2>/dev/null || true)"
      printf 'Hermes agent iteration budget: configured %s, effective %s\n' \
        "${configured_turns:-unset}" "${effective_turns:-unknown}"
      if [[ -n "$configured_turns" ]] && (( configured_turns <= 30 )); then
        printf 'WARNING: an iteration budget of %s stops multi-step tool tasks early. Raise it with ./manage.sh set-agent-max-turns 90.\n' \
          "$configured_turns"
      fi
      if [[ -n "$configured_turns" && -n "$effective_turns" && "$configured_turns" != "$effective_turns" ]]; then
        printf 'WARNING: the running gateway budget does not match config.yaml; recreate Hermes.\n'
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
        /opt/hermes/.venv/bin/hermes tools list --platform telegram 2>/dev/null \
          | grep -Eq "enabled[[:space:]]+stack_packages([[:space:]]|$)"
      '; then
        printf 'Hermes package broker: enabled\n'
      else
        printf 'WARNING: the stack package broker is not enabled in the tool registry.\n'
      fi
      # Upstream terminal/code_execution are a local decision, so report their
      # real state rather than asserting one. Enabled means an approved command
      # runs as the gateway uid, which can read /opt/data/.env.
      upstream_terminal="$(compose exec -T hermes sh -lc '
        cd /opt/hermes
        tools="$(/opt/hermes/.venv/bin/hermes tools list --platform telegram 2>/dev/null)"
        printf "%s\n" "$tools" | grep -Eq "disabled[[:space:]]+terminal([[:space:]]|$)" \
          && printf "%s\n" "$tools" | grep -Eq "disabled[[:space:]]+code_execution([[:space:]]|$)" \
          && printf disabled || printf enabled
      ' 2>/dev/null || printf unknown)"
      if [[ "$upstream_terminal" == disabled ]]; then
        printf 'Upstream terminal/code execution: disabled (isolated stack tools only)\n'
      elif [[ "$upstream_terminal" == enabled ]]; then
        printf 'Upstream terminal/code execution: ENABLED — approved commands run as the\n'
        printf '  gateway uid inside hermes-agent and can read /opt/data/.env. Keep\n'
        printf '  approvals.mode=manual and the Telegram allowlist tight.\n'
      else
        printf 'WARNING: could not determine the upstream terminal state.\n'
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
      if [[ -d "$(execution_root)" ]]; then
        printf 'Execution features: %s\n' "$(execution_features | sed 's/^$/off/')"
        for execution_file in "$(execution_root)/control-secret" \
          "$(execution_root)/approval-request-secret" "$(execution_root)/approval-signing-key.pem" \
          "$(execution_root)/approval-public-key.pem" "$(execution_root)/approval-bot-token" \
          "$(execution_root)/users"; do
          if [[ -f "$execution_file" && ! -L "$execution_file" && "$(stat -c %a "$execution_file")" == 600 ]]; then
            printf 'Execution policy %s: safe mode 600\n' "${execution_file##*/}"
          else
            printf 'WARNING: execution policy %s is missing, unsafe, or not mode 600.\n' "${execution_file##*/}"
          fi
        done
        users="$(execution_users)"
        if [[ -z "$users" ]] || execution_users_valid "$users"; then
          printf 'Execution user policy: valid Telegram subset\n'
        else
          printf 'WARNING: execution users are not a subset of TELEGRAM_ALLOWED_USERS.\n'
        fi
        rendered="$(compose config 2>/dev/null || true)"
        socket_count="$(grep -c '/var/run/docker.sock:/var/run/docker.sock' <<< "$rendered" || true)"
        [[ "$socket_count" == 1 ]] \
          && printf 'Docker socket boundary: mounted once, Docker broker only\n' \
          || printf 'WARNING: expected exactly one Docker socket mount; found %s.\n' "$socket_count"
        if grep -A35 '^  hermes:' <<< "$rendered" | grep -q docker.sock; then
          printf 'WARNING: Hermes has the Docker socket; remove it immediately.\n'
        fi
        if grep -A50 '^  execution-ssh-broker:' <<< "$rendered" | grep -q docker.sock; then
          printf 'WARNING: SSH broker has the Docker socket; remove it immediately.\n'
        fi
        approval_token_count="$(grep -c '/run/secrets/execution-approval-bot-token' <<< "$rendered" || true)"
        [[ "$approval_token_count" == 2 ]] \
          && printf 'Approval bot token boundary: approver mount and environment only\n' \
          || printf 'WARNING: approval bot token wiring count is unexpected: %s.\n' "$approval_token_count"
        hermes_block="$(grep -A55 '^  hermes:' <<< "$rendered")"
        if grep -q 'execution-approval\|execution-approval-bot-token' <<< "$hermes_block"; then
          printf 'WARNING: Hermes has independent approval authority; disable execution immediately.\n'
        fi
        approver_block="$(grep -A55 '^  execution-approver:' <<< "$rendered")"
        if grep -q 'docker.sock\|/profiles' <<< "$approver_block"; then
          printf 'WARNING: the approver has Docker or SSH execution authority.\n'
        fi
        if grep -q '^[[:space:]]*- stack-execution-policy[[:space:]]*$' "$ROOT_DIR/data/hermes/config.yaml"; then
          printf 'Hermes execution policy plugin: enabled in config\n'
        else
          printf 'WARNING: stack-execution-policy is not enabled in Hermes config.\n'
        fi
      fi
    fi
    if [[ "$profiles" == *execution-approval* ]]; then
      compose exec -T execution-approver python -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8751/health", timeout=5)'
      printf 'Independent execution approver: healthy\n'
    fi
    if [[ "$profiles" == *execution-docker* ]]; then
      compose exec -T execution-docker-broker python -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8750/health", timeout=5)'
      printf 'Docker execution broker: healthy\n'
    fi
    if [[ "$profiles" == *execution-ssh* ]]; then
      compose exec -T execution-ssh-broker python -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8750/health", timeout=5)'
      printf 'SSH execution broker: healthy\n'
    fi
    if [[ "$profiles" == *n8n* ]]; then
      compose exec -T n8n node -e \
        "fetch('http://127.0.0.1:5678/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
      printf 'n8n health: valid\n'
      if [[ "$profiles" == *hermes* && -f "$HERMES_ENV" ]]; then
        selected_mcp_mode="$(n8n_mcp_mode 2>/dev/null || true)"
        printf 'Hermes n8n MCP mode: %s\n' "${selected_mcp_mode:-invalid}"
        mcp_url=""
        case "$selected_mcp_mode" in
          instance)
            mcp_url="$(env_value "$HERMES_ENV" N8N_INSTANCE_MCP_URL)"
            if [[ -z "$(env_value "$HERMES_ENV" N8N_INSTANCE_MCP_TOKEN)" ]]; then
              printf 'WARNING: Instance MCP mode is pending a token. Enable it in n8n and run ./manage.sh set-n8n-instance-mcp-token.\n'
            fi
            ;;
          trigger)
            mcp_url="$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_URL)"
            [[ -n "$mcp_url" ]] || mcp_url="$(env_value "$HERMES_ENV" N8N_MCP_URL)"
            ;;
          off) printf 'Hermes -> n8n MCP: disabled; retained n8n objects are not deleted.\n' ;;
        esac
        if [[ -n "$mcp_url" ]]; then
          code="$(compose exec -T -e HERMES_N8N_MCP_URL="$mcp_url" hermes sh -c \
            'curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"doctor\",\"version\":\"1\"}}}" "$HERMES_N8N_MCP_URL"' \
            2>/dev/null || true)"
          case "$code" in
            401|403) printf 'Hermes -> n8n %s MCP endpoint: reachable and rejects anonymous access (HTTP %s)\n' "$selected_mcp_mode" "$code" ;;
            404)
              if [[ "$selected_mcp_mode" == trigger ]]; then
                printf 'Hermes -> n8n Trigger MCP endpoint: HTTP 404; reconcile Trigger mode to publish it.\n'
              else
                printf 'Hermes -> n8n Instance MCP endpoint: HTTP 404; enable Instance-level MCP in n8n Settings.\n'
              fi
              ;;
            000|"") printf 'WARNING: Hermes cannot reach %s over the Docker network.\n' "$mcp_url" ;;
            *) printf 'Hermes -> n8n %s MCP endpoint: unexpected anonymous HTTP %s\n' "$selected_mcp_mode" "$code" ;;
          esac
        fi
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
  set-agent-max-turns)
    require_profiles hermes
    turns="${2:-}"
    [[ -z "${3:-}" && "$turns" =~ ^[0-9]+$ ]] || {
      printf 'Usage: ./manage.sh set-agent-max-turns N\n' >&2
      exit 2
    }
    turns=$((10#$turns))
    (( turns >= AGENT_MAX_TURNS_MIN && turns <= AGENT_MAX_TURNS_MAX )) || {
      printf 'Choose a budget between %s and %s. 90 suits most tasks; 150 suits long exploration. An unbounded budget amplifies stuck tool loops and cost.\n' \
        "$AGENT_MAX_TURNS_MIN" "$AGENT_MAX_TURNS_MAX" >&2
      exit 2
    }
    config_file="$ROOT_DIR/data/hermes/config.yaml"
    ensure_stack_secrets_dir
    turns_backup="$(mktemp "$STACK_SECRETS_DIR/max-turns-config.backup.XXXXXX")"
    TEMP_SECRET_FILES+=("$turns_backup")
    cp --preserve=mode,ownership,timestamps "$config_file" "$turns_backup"
    set_hermes_agent_max_turns "$turns" || {
      cp --preserve=mode,ownership,timestamps "$turns_backup" "$config_file"
      printf 'Hermes config was not modified.\n' >&2
      exit 1
    }
    if ! restart_hermes; then
      cp --preserve=mode,ownership,timestamps "$turns_backup" "$config_file"
      restart_hermes || true
      printf 'Hermes failed to start with the new budget; the prior config was restored.\n' >&2
      exit 1
    fi
    effective="$(compose exec -T hermes sh -lc 'printf "%s" "${HERMES_MAX_ITERATIONS:-}"' 2>/dev/null || true)"
    if [[ -n "$effective" && "$effective" != "$turns" ]]; then
      printf 'WARNING: config.yaml requests %s turns but the gateway reports %s.\n' \
        "$turns" "$effective" >&2
    fi
    printf 'Agent iteration budget set to %s. Reaching it stops the turn safely; send a new message to continue from the summary.\n' "$turns"
    ;;
  set-upstream-terminal)
    require_profiles hermes
    state="${2:-}"
    [[ -z "${3:-}" && ( "$state" == enabled || "$state" == disabled ) ]] || {
      printf 'Usage: ./manage.sh set-upstream-terminal enabled|disabled\n' >&2
      exit 2
    }
    if [[ "$state" == enabled ]]; then
      printf 'Enabling upstream terminal and code_execution.\n'
      printf 'They run as the gateway uid inside hermes-agent, which owns /opt/data/.env:\n'
      printf '  the Telegram bot token, 9router key, API server key, and n8n Instance token.\n'
      printf 'Every call still passes the hardline floor and a manual approval prompt, but an\n'
      printf 'approved command can read those secrets, and prompt injection reaching the model\n'
      printf 'can request one. Rotating afterwards does not undo an exfiltration.\n'
      read -r -p 'Type ENABLE to confirm: ' confirm
      [[ "$confirm" == ENABLE ]] || { printf 'Unchanged.\n' >&2; exit 1; }
    fi
    config_file="$ROOT_DIR/data/hermes/config.yaml"
    ensure_stack_secrets_dir
    terminal_backup="$(mktemp "$STACK_SECRETS_DIR/terminal-config.backup.XXXXXX")"
    TEMP_SECRET_FILES+=("$terminal_backup")
    cp --preserve=mode,ownership,timestamps "$config_file" "$terminal_backup"
    set_upstream_terminal "$state" || {
      cp --preserve=mode,ownership,timestamps "$terminal_backup" "$config_file"
      printf 'Hermes config was not modified.\n' >&2
      exit 1
    }
    if ! restart_hermes; then
      cp --preserve=mode,ownership,timestamps "$terminal_backup" "$config_file"
      restart_hermes || true
      printf 'Hermes failed to start; the prior config was restored.\n' >&2
      exit 1
    fi
    printf 'Upstream terminal/code execution: %s. Run ./manage.sh doctor to confirm.\n' "$state"
    ;;
  execution-status)
    printf 'Execution features: %s\n' "$(execution_features | sed 's/^$/off/')"
    printf 'Execution users: %s\n' "$(execution_users | sed 's/^$/none/')"
    printf 'Policy generation: %s\n' "$(env_value "$ENV_FILE" EXECUTION_POLICY_GENERATION)"
    if [[ -d "$(execution_root)/ssh" ]]; then
      printf 'SSH profiles:'
      found=false
      for profile_dir in "$(execution_root)/ssh"/*; do
        [[ -d "$profile_dir" && ! -L "$profile_dir" ]] || continue
        printf ' %s' "${profile_dir##*/}"; found=true
      done
      [[ "$found" == true ]] || printf ' none'
      printf '\n'
    fi
    ;;
  set-execution-users)
    users="${2:-}"
    [[ -z "${3:-}" && -n "$users" ]] || { printf 'Usage: ./manage.sh set-execution-users ID1,ID2,...\n' >&2; exit 2; }
    execution_users_valid "$users" || {
      printf 'Execution users must be numeric and a subset of TELEGRAM_ALLOWED_USERS.\n' >&2; exit 2;
    }
    write_execution_users "$users"
    rotate_execution_generation
    restart_hermes
    printf 'Execution users updated; all pending operations were revoked.\n'
    ;;
  add-execution-user)
    user="${2:-}"
    [[ -z "${3:-}" && "$user" =~ ^[0-9]+$ ]] || { printf 'Usage: ./manage.sh add-execution-user ID\n' >&2; exit 2; }
    users="$(execution_users)"
    [[ ",$users," == *",$user,"* ]] || users="${users:+$users,}$user"
    execution_users_valid "$users" || { printf 'ID must already be in TELEGRAM_ALLOWED_USERS.\n' >&2; exit 2; }
    write_execution_users "$users"; rotate_execution_generation; restart_hermes
    printf 'Execution user %s added.\n' "$user"
    ;;
  remove-execution-user)
    user="${2:-}"
    [[ -z "${3:-}" && "$user" =~ ^[0-9]+$ ]] || { printf 'Usage: ./manage.sh remove-execution-user ID\n' >&2; exit 2; }
    users="$(execution_users | tr ',' '\n' | grep -vx "$user" | paste -sd, -)"
    [[ -n "$users" ]] && write_execution_users "$users" || write_execution_users ""
    rotate_execution_generation; restart_hermes
    printf 'Execution user %s removed; pending operations revoked.\n' "$user"
    ;;
  enable-execution|disable-execution)
    feature="${2:-}"
    [[ -z "${3:-}" && "$feature" =~ ^(sandbox|ssh|docker|all)$ ]] || {
      printf 'Usage: ./manage.sh %s sandbox|ssh|docker|all\n' "$1" >&2; exit 2;
    }
    ensure_execution_paths
    if [[ "$1" == enable-execution ]]; then
      [[ -n "$(execution_users)" ]] || { printf 'Set execution users first.\n' >&2; exit 1; }
      [[ -s "$(execution_root)/approval-bot-token" \
        && -s "$(execution_root)/approval-request-secret" \
        && -s "$(execution_root)/approval-signing-key.pem" \
        && -s "$(execution_root)/approval-public-key.pem" ]] || {
        printf 'Configure the dedicated approval bot first: ./manage.sh set-execution-approval-bot-token\n' >&2; exit 1;
      }
      features="$(set_execution_feature "$feature" true)"
    else
      features="$(set_execution_feature "$feature" false)"
    fi
    apply_execution_features "$features"
    printf 'Execution features now: %s\n' "${features:-off}"
    ;;
  set-execution-approval-bot-token)
    [[ -z "${2:-}" ]] || { printf 'Do not pass Telegram tokens in argv.\n' >&2; exit 2; }
    ensure_execution_paths
    read -r -s -p 'Dedicated execution approval Telegram bot token: ' token
    printf '\n' >&2
    [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]] || {
      printf 'The Telegram bot token format is invalid.\n' >&2; exit 2;
    }
    hermes_bot_token="$(env_value "$HERMES_ENV" TELEGRAM_BOT_TOKEN)"
    [[ -z "$hermes_bot_token" || "$token" != "$hermes_bot_token" ]] || {
      printf 'The execution approver must use a different Telegram bot from Hermes.\n' >&2
      exit 2
    }
    root="$(execution_root)"
    tmp="$(mktemp "$root/approval-bot-token.tmp.XXXXXX")"
    printf '%s\n' "$token" > "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$root/approval-bot-token"
    if [[ ! -s "$root/approval-request-secret" ]]; then
      tmp="$(mktemp "$root/approval-request-secret.tmp.XXXXXX")"
      random_hex 32 > "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$root/approval-request-secret"
    fi
    if [[ ! -s "$root/approval-signing-key.pem" || ! -s "$root/approval-public-key.pem" ]]; then
      private_tmp="$(mktemp "$root/approval-signing-key.tmp.XXXXXX")"
      public_tmp="$(mktemp "$root/approval-public-key.tmp.XXXXXX")"
      openssl genpkey -algorithm ED25519 -out "$private_tmp" >/dev/null 2>&1
      openssl pkey -in "$private_tmp" -pubout -out "$public_tmp" >/dev/null 2>&1
      chmod 600 "$private_tmp" "$public_tmp"
      mv "$private_tmp" "$root/approval-signing-key.pem"
      mv "$public_tmp" "$root/approval-public-key.pem"
    fi
    rotate_execution_generation
    printf 'Dedicated execution approval bot configured without printing its token. Execution remains off until explicitly enabled.\n'
    ;;
  rotate-execution-broker-secret)
    [[ -z "${2:-}" ]] || { printf 'Do not pass broker secrets in argv.\n' >&2; exit 2; }
    ensure_execution_paths
    secret_file="$(execution_root)/control-secret"
    tmp="$(mktemp "$(execution_root)/control-secret.tmp.XXXXXX")"
    random_hex 32 > "$tmp"; chmod 600 "$tmp"; mv "$tmp" "$secret_file"
    rotate_execution_generation
    compose up -d --force-recreate hermes execution-approver execution-docker-broker execution-ssh-broker
    printf 'Execution broker secret rotated; pending operations revoked.\n'
    ;;
  add-ssh-profile)
    name="${2:-}"
    [[ -z "${3:-}" && "$name" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]] || { printf 'Use a lowercase safe profile name.\n' >&2; exit 2; }
    ensure_execution_paths
    root="$(execution_root)/ssh"; target="$root/$name"
    [[ ! -e "$target" && ! -L "$target" ]] || { printf 'Profile already exists.\n' >&2; exit 1; }
    read -r -p 'SSH host: ' host
    read -r -p 'SSH port [22]: ' port; port="${port:-22}"
    read -r -p 'SSH user: ' ssh_user
    read -r -p 'Authority [user|root|sudo-nopasswd]: ' authority
    [[ "$host" =~ ^[A-Za-z0-9._:-]+$ && "$port" =~ ^[0-9]+$ && "$ssh_user" =~ ^[A-Za-z0-9._-]+$ \
      && "$authority" =~ ^(user|root|sudo-nopasswd)$ ]] || { printf 'Invalid profile values.\n' >&2; exit 2; }
    stage="$(mktemp -d "$root/.${name}.tmp.XXXXXX")"; chmod 700 "$stage"
    if read -r -p 'Generate a dedicated Ed25519 key? [Y/n] ' answer && [[ "${answer:-y}" =~ ^[Yy]$ ]]; then
      ssh-keygen -q -t ed25519 -N '' -f "$stage/identity"
    else
      printf 'Paste private key, then Ctrl-D:\n' >&2
      umask 077; cat > "$stage/identity"
      ssh-keygen -y -f "$stage/identity" > "$stage/identity.pub"
    fi
    chmod 600 "$stage/identity" "$stage/identity.pub"
    ssh-keyscan -p "$port" -T 10 -- "$host" > "$stage/known_hosts.scan" 2>/dev/null || { rm -rf "$stage"; printf 'Host-key scan failed.\n' >&2; exit 1; }
    read -r -p 'Enter the independently verified SHA256 host fingerprint: ' expected
    [[ "$expected" =~ ^SHA256:[A-Za-z0-9+/]{20,}={0,2}$ ]] || { rm -rf "$stage"; printf 'Invalid host fingerprint.\n' >&2; exit 2; }
    python3 - "$stage/known_hosts.scan" "$stage/known_hosts" "$expected" <<'PY'
import subprocess, sys
source, target, expected = sys.argv[1:]
matches = []
for line in open(source, encoding="utf-8"):
    if not line.strip():
        continue
    completed = subprocess.run(
        ["ssh-keygen", "-lf", "-", "-E", "sha256"], input=line,
        text=True, encoding="utf-8", stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, check=False,
    )
    fields = completed.stdout.split()
    if completed.returncode == 0 and len(fields) > 1 and fields[1] == expected:
        matches.append(line)
if len(matches) != 1:
    raise SystemExit("The independently verified fingerprint did not select exactly one scanned host key.")
open(target, "w", encoding="utf-8").write(matches[0])
PY
    status=$?; rm -f "$stage/known_hosts.scan"
    [[ "$status" -eq 0 ]] || { rm -rf "$stage"; printf 'Host fingerprint mismatch or ambiguity.\n' >&2; exit 1; }
    fingerprint="$expected"
    printf 'Pinned independently verified host fingerprint: %s\n' "$fingerprint"
    python3 - "$stage/profile.json" "$host" "$port" "$ssh_user" "$authority" "$fingerprint" <<'PY'
import json, sys
path, host, port, user, authority, fingerprint = sys.argv[1:]
open(path, "w", encoding="utf-8").write(json.dumps({"host": host, "port": int(port), "user": user, "authority": authority, "fingerprint": fingerprint}, indent=2) + "\n")
PY
    chmod 600 "$stage/profile.json" "$stage/known_hosts"
    printf 'Install this public key on %s@%s, then verify:\n' "$ssh_user" "$host"
    cat "$stage/identity.pub"
    mv "$stage" "$target"
    printf 'Profile %s stored. Run ./manage.sh verify-ssh-profile %s.\n' "$name" "$name"
    ;;
  verify-ssh-profile)
    name="${2:-}"; target="$(execution_root)/ssh/$name"
    [[ -z "${3:-}" && "$name" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ && -d "$target" && ! -L "$target" ]] || { printf 'Unknown or unsafe profile.\n' >&2; exit 2; }
    mapfile -t meta < <(python3 - "$target/profile.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); print(x["host"]); print(x["port"]); print(x["user"]); print(x["authority"])
PY
)
    probe=id; [[ "${meta[3]}" == sudo-nopasswd ]] && probe='sudo -n true && id'
    ssh -n -T -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
      -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o ForwardAgent=no \
      -o ForwardX11=no -o PermitLocalCommand=no -o ClearAllForwardings=yes -o RequestTTY=no \
      -o "UserKnownHostsFile=$target/known_hosts" -i "$target/identity" -p "${meta[1]}" \
      "${meta[2]}@${meta[0]}" -- "$probe"
    printf 'SSH profile %s verified.\n' "$name"
    ;;
  remove-ssh-profile)
    name="${2:-}"; target="$(execution_root)/ssh/$name"
    [[ -z "${3:-}" && "$name" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ && -d "$target" && ! -L "$target" ]] || { printf 'Unknown or unsafe profile.\n' >&2; exit 2; }
    rm -rf -- "$target"; rotate_execution_generation
    compose up -d --force-recreate execution-ssh-broker hermes
    printf 'Local profile removed. Revoke its public key from the remote authorized_keys separately.\n'
    ;;
  purge-execution)
    [[ -z "${2:-}" ]] || { printf 'Usage: ./manage.sh purge-execution\n' >&2; exit 2; }
    read -r -p 'Type PURGE-EXECUTION to delete keys, state, and workspace: ' confirm
    [[ "$confirm" == PURGE-EXECUTION ]] || { printf 'Unchanged.\n' >&2; exit 1; }
    replace_env_value "$ENV_FILE" EXECUTION_FEATURES ""; sync_execution_profiles
    COMPOSE_PROFILES=execution-approval,execution-docker,execution-ssh compose rm -sf execution-approver execution-docker-broker execution-ssh-broker || true
    rm -rf -- "$(execution_root)" "$ROOT_DIR/data/execution-workspace"
    ensure_execution_paths; restart_hermes
    printf 'Execution state purged. Remote authorized_keys and prior Docker effects are not reverted.\n'
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
  set-n8n-instance-mcp-token)
    require_profiles 9router hermes n8n
    if [[ -n "${2:-}" ]]; then
      printf 'For safety, do not pass the Instance MCP token in argv. Run without an argument.\n' >&2
      exit 2
    fi
    read -r -s -p 'n8n Instance-level MCP token: ' token
    printf '\n' >&2
    [[ -n "$token" && "$token" != *[[:space:]]* ]] || {
      printf 'A non-empty token without whitespace is required.\n' >&2; exit 2;
    }
    [[ "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] || {
      printf 'Paste only the n8n Instance MCP token, without Bearer, quotes, JSON, or the connection URL.\n' >&2
      exit 2
    }
    n8n_instance_mcp_check "$token" || {
      printf 'n8n rejected the Instance MCP token or required tools are unavailable; nothing was stored.\n' >&2
      exit 1
    }
    [[ -f "$HERMES_ENV" && ! -L "$HERMES_ENV" ]] || {
      printf 'Hermes secret configuration is missing or unsafe.\n' >&2; exit 1;
    }
    migrate_legacy_trigger_env
    replace_env_value "$HERMES_ENV" N8N_INSTANCE_MCP_TOKEN "$token"
    chmod 600 "$HERMES_ENV"
    mode="$(n8n_mcp_mode)"
    if [[ "$mode" == instance ]]; then
      if ! run_n8n_reconciler; then
        printf 'The validated replacement token remains stored because regenerating an Instance token revokes the old token immediately; n8n reconciliation failed before Hermes was recreated.\n' >&2
        exit 1
      fi
      if ! set_hermes_n8n_mcp_entry instance; then
        printf 'The validated replacement token remains stored because regenerating an Instance token revokes the old token immediately; Hermes configuration reconciliation failed.\n' >&2
        exit 1
      fi
      finish_legacy_trigger_env_migration
      if ! restart_hermes; then
        printf 'The validated replacement token remains stored because regenerating an Instance token revokes the old token immediately; Hermes recreation failed.\n' >&2
        exit 1
      fi
      if ! "$ROOT_DIR/manage.sh" verify-n8n; then
        printf 'The validated replacement token remains stored because regenerating an Instance token revokes the old token immediately; Instance verification failed.\n' >&2
        exit 1
      fi
      printf 'n8n Instance MCP token validated, stored with mode 0600, and connected to Hermes.\n'
    else
      printf 'n8n Instance MCP token validated and stored with mode 0600. Activate it with ./manage.sh set-n8n-mcp-mode instance.\n'
    fi
    ;;
  remove-n8n-instance-mcp-token)
    require_profiles hermes n8n
    [[ -z "${2:-}" ]] || {
      printf 'Usage: ./manage.sh remove-n8n-instance-mcp-token\n' >&2
      exit 2
    }
    [[ "$(n8n_mcp_mode)" != instance ]] || {
      printf 'Instance MCP mode is active. Switch to trigger or off before removing its token.\n' >&2
      exit 1
    }
    [[ -f "$HERMES_ENV" && ! -L "$HERMES_ENV" ]] || {
      printf 'Hermes secret configuration is missing or unsafe.\n' >&2
      exit 1
    }
    if [[ -n "$(env_value "$HERMES_ENV" N8N_INSTANCE_MCP_TOKEN)" ]]; then
      remove_env_values "$HERMES_ENV" N8N_INSTANCE_MCP_TOKEN
      chmod 600 "$HERMES_ENV"
      printf 'Stored n8n Instance MCP token removed. Instance-level MCP in n8n was not disabled.\n'
    else
      printf 'No stored n8n Instance MCP token was present.\n'
    fi
    ;;
  set-n8n-mcp-mode)
    require_profiles 9router hermes n8n
    target_mode="${2:-}"
    [[ -z "${3:-}" && ( "$target_mode" == instance || "$target_mode" == trigger || "$target_mode" == off ) ]] || {
      printf 'Usage: ./manage.sh set-n8n-mcp-mode instance|trigger|off\n' >&2
      exit 2
    }
    current_mode="$(n8n_mcp_mode)"
    trigger_token="$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN)"
    if [[ -z "$trigger_token" ]]; then
      trigger_token="$(env_value "$HERMES_ENV" N8N_MCP_TOKEN)"
    fi
    instance_token="$(env_value "$HERMES_ENV" N8N_INSTANCE_MCP_TOKEN)"
    [[ -n "$(n8n_api_key)" ]] || {
      printf 'A stored owner API key is required to reconcile hosted chat and trigger publication. Run ./manage.sh set-n8n-api-key.\n' >&2
      exit 1
    }
    case "$target_mode" in
      instance)
        [[ -n "$instance_token" ]] || {
          printf 'No Instance MCP token is stored. Enable Instance-level MCP in n8n, generate its token, then run ./manage.sh set-n8n-instance-mcp-token.\n' >&2
          exit 1
        }
        n8n_instance_mcp_check "$instance_token" || {
          printf 'The stored Instance MCP token failed validation; mode was not changed.\n' >&2
          exit 1
        }
        ;;
      trigger)
        [[ -n "$trigger_token" ]] || {
          printf 'No Trigger MCP token is stored. Run ./manage.sh configure and select Trigger mode.\n' >&2
          exit 1
        }
        ;;
    esac
    ensure_stack_secrets_dir
    env_backup="$(mktemp "$STACK_SECRETS_DIR/mode-env.backup.XXXXXX")"
    hermes_backup="$(mktemp "$STACK_SECRETS_DIR/mode-hermes-env.backup.XXXXXX")"
    config_backup="$(mktemp "$STACK_SECRETS_DIR/mode-hermes-config.backup.XXXXXX")"
    TEMP_SECRET_FILES+=("$env_backup" "$hermes_backup" "$config_backup")
    cp --preserve=mode,ownership,timestamps "$ENV_FILE" "$env_backup"
    cp --preserve=mode,ownership,timestamps "$HERMES_ENV" "$hermes_backup"
    cp --preserve=mode,ownership,timestamps "$ROOT_DIR/data/hermes/config.yaml" "$config_backup"
    if ! run_n8n_reconciler_with_token "$trigger_token" "$trigger_token" "$target_mode"; then
      printf 'n8n rejected the mode transition before local configuration changed.\n' >&2
      exit 1
    fi
    migrate_legacy_trigger_env
    replace_env_value "$ENV_FILE" N8N_MCP_MODE "$target_mode"
    if set_hermes_n8n_mcp_entry "$target_mode"; then
      finish_legacy_trigger_env_migration
    else
      cp --preserve=mode,ownership,timestamps "$env_backup" "$ENV_FILE"
      cp --preserve=mode,ownership,timestamps "$hermes_backup" "$HERMES_ENV"
      cp --preserve=mode,ownership,timestamps "$config_backup" "$ROOT_DIR/data/hermes/config.yaml"
      if run_n8n_reconciler_with_token "$trigger_token" "$trigger_token" "$current_mode" >/dev/null; then
        printf 'Hermes configuration update failed; prior files and controllable trigger publication state were restored.\n' >&2
      else
        printf 'Hermes configuration update failed; prior local files were restored, but trigger publication rollback could not be verified. Manual recovery is required.\n' >&2
      fi
      exit 1
    fi
    if restart_hermes && "$ROOT_DIR/manage.sh" verify-n8n; then
      printf 'Hermes n8n MCP mode changed to %s.\n' "$target_mode"
    else
      cp --preserve=mode,ownership,timestamps "$env_backup" "$ENV_FILE"
      cp --preserve=mode,ownership,timestamps "$hermes_backup" "$HERMES_ENV"
      cp --preserve=mode,ownership,timestamps "$config_backup" "$ROOT_DIR/data/hermes/config.yaml"
      if run_n8n_reconciler_with_token "$trigger_token" "$trigger_token" "$current_mode" && restart_hermes && "$ROOT_DIR/manage.sh" verify-n8n; then
        printf 'Mode verification failed; the prior local configuration and controllable trigger publication state were restored and verified.\n' >&2
      else
        printf 'Mode verification failed and rollback could not be fully verified; manual recovery is required.\n' >&2
      fi
      exit 1
    fi
    ;;
  bootstrap-n8n|reconcile-n8n)
    require_profiles 9router hermes n8n
    run_n8n_reconciler
    restart_hermes
    "$ROOT_DIR/manage.sh" verify-n8n
    ;;
  verify-n8n)
    require_profiles hermes n8n
    run_n8n_verifier
    ;;
  rotate-n8n-trigger-token|rotate-n8n-token)
    require_profiles 9router hermes n8n
    [[ -f "$HERMES_ENV" ]] || { printf 'Hermes is not configured.\n' >&2; exit 1; }
    migrate_legacy_trigger_env
    old_token="$(env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN)"
    [[ -n "$old_token" ]] || { printf 'No Trigger MCP token is configured. Run bootstrap-n8n first.\n' >&2; exit 1; }
    current_mode="$(n8n_mcp_mode)"
    if [[ "$current_mode" == instance ]]; then
      printf 'This rotates only the retained Trigger credential. To replace the Instance token, regenerate it in n8n and run ./manage.sh set-n8n-instance-mcp-token.\n' >&2
    fi
    new_token="$(random_hex 32)"
    if run_n8n_reconciler_with_token "$new_token" "$old_token" "$current_mode"; then
      replace_env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN "$new_token"
      finish_legacy_trigger_env_migration
      if restart_hermes && "$ROOT_DIR/manage.sh" verify-n8n; then
        printf 'n8n Trigger MCP bearer token rotated without printing it.\n'
      else
        if run_n8n_reconciler_with_token "$old_token" "$new_token" "$current_mode"; then
          replace_env_value "$HERMES_ENV" N8N_TRIGGER_MCP_TOKEN "$old_token"
          if restart_hermes && "$ROOT_DIR/manage.sh" verify-n8n; then
            printf 'Rotation verification failed; the prior n8n Trigger credential and Hermes token were restored and verified.\n' >&2
          else
            printf 'Rotation verification failed; the prior values were restored, but their operation could not be verified. Manual recovery is required.\n' >&2
          fi
        else
          printf 'Rotation verification failed, and n8n Trigger credential rollback also failed. Hermes retains the new token; manual recovery is required.\n' >&2
        fi
        exit 1
      fi
    else
      printf 'Rotation failed before Hermes changed; the prior Trigger token remains active.\n' >&2
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
