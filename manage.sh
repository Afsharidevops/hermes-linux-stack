#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
cd "$ROOT_DIR"

usage() { cat <<'EOF'
Usage: ./manage.sh COMMAND [ARG]
  start | stop | restart | status [--json] | health [--json] | update [options]
  version | backup [options] | backup-list [options] | restore ARCHIVE [options]
  rollback [STATE_ID] | lock-images | verify-images
  logs [gateway|smart-router|hermes|webui|n8n|caddy]
  restart-hermes | doctor
  router-mode observe|route | set-router-mode observe|route
  router-policy heuristic|calibrated|learned
  router-info
  router-calibrate LABELED.jsonl
  router-report LABELED.jsonl
  router-replay REQUESTS.jsonl [OUTPUT.jsonl]
  execution-status
  enable-execution sandbox|ssh|docker
  disable-execution sandbox|ssh|docker
  set-execution-approval-bot-token
  set-execution-users USER_ID [USER_ID ...]
EOF
}

[[ -f "$ENV_FILE" ]] || { echo "Run ./install.sh first." >&2; exit 1; }
compose() { docker compose --env-file "$ENV_FILE" "$@"; }
ops() { "$ROOT_DIR/scripts/stack-ops.sh" "$@"; }
env_value() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1; }
set_env() {
  local key="$1" value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PYENV'
import sys
p,k,v=sys.argv[1:]
lines=open(p,encoding='utf-8').read().splitlines(); found=False; out=[]
for line in lines:
    if line.startswith(k+'='):
        out.append(k+'='+v); found=True
    else: out.append(line)
if not found: out.append(k+'='+v)
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PYENV
  chmod 600 "$ENV_FILE"
}
set_csv_item() {
  local key="$1" item="$2" enable="$3"
  python3 - "$ENV_FILE" "$key" "$item" "$enable" <<'PYCSV'
import sys
p,key,item,enable=sys.argv[1:]
lines=open(p,encoding='utf-8').read().splitlines(); out=[]; found=False
for line in lines:
    if line.startswith(key+'='):
        values={x.strip() for x in line.split('=',1)[1].split(',') if x.strip()}
        if enable=='1': values.add(item)
        else: values.discard(item)
        line=key+'='+','.join(sorted(values)); found=True
    out.append(line)
if not found: out.append(key+'='+(item if enable=='1' else ''))
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PYCSV
}
secure_write() {
  local path="$1" value="$2"
  umask 077; mkdir -p "$(dirname "$path")"; printf '%s' "$value" > "$path"; chmod 600 "$path"
}
execution_secret_root() { printf '%s/data/stack-secrets/execution' "$ROOT_DIR"; }
execution_feature_name() { [[ "$1" == sandbox ]] && printf local || printf '%s' "$1"; }
execution_profile_name() { [[ "$1" == ssh ]] && printf execution-ssh || printf execution-docker; }
ensure_execution_secrets() {
  local d uidgid uid gid
  d="$(execution_secret_root)"
  mkdir -p "$d" "$d/docker-state" "$d/ssh-state" "$d/ssh"
  chmod 700 "$d" "$d/docker-state" "$d/ssh-state" "$d/ssh" 2>/dev/null || true
  [[ -s "$d/control-secret" ]] || secure_write "$d/control-secret" "$(openssl rand -hex 32)"
  [[ -s "$d/approval-request-secret" ]] || secure_write "$d/approval-request-secret" "$(openssl rand -hex 32)"
  [[ -s "$d/ssh-profile-integrity-secret" ]] || secure_write "$d/ssh-profile-integrity-secret" "$(openssl rand -hex 32)"
  if [[ ! -s "$d/approval-signing-key.pem" || ! -s "$d/approval-public-key.pem" ]]; then
    command -v openssl >/dev/null || { echo "openssl is required to initialize execution approval keys." >&2; exit 1; }
    umask 077
    openssl genpkey -algorithm Ed25519 -out "$d/approval-signing-key.pem" >/dev/null 2>&1
    openssl pkey -in "$d/approval-signing-key.pem" -pubout -out "$d/approval-public-key.pem" >/dev/null 2>&1
    chmod 600 "$d/approval-signing-key.pem" "$d/approval-public-key.pem"
  fi
  [[ -e "$d/approval-bot-token" ]] || secure_write "$d/approval-bot-token" ""
  [[ -e "$d/users" ]] || secure_write "$d/users" ""
  uidgid="$(env_value EXECUTION_RUN_AS)"; uidgid="${uidgid:-10003:10003}"; uid="${uidgid%%:*}"; gid="${uidgid##*:}"
  if [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]]; then
    if chown -R "$uid:$gid" "$d" 2>/dev/null; then :
    elif command -v sudo >/dev/null 2>&1; then
      sudo chown -R "$uid:$gid" "$d"
    else
      echo "WARNING: execution secret ownership must be $uid:$gid; run: sudo chown -R $uid:$gid '$d'" >&2
    fi
  fi
}
execution_validate_ready() {
  local feature="$1" d
  d="$(execution_secret_root)"
  [[ -s "$d/approval-bot-token" ]] || { echo "Configure the dedicated approval bot first: ./manage.sh set-execution-approval-bot-token" >&2; exit 1; }
  [[ -s "$d/users" ]] || { echo "Configure numeric approval users first: ./manage.sh set-execution-users USER_ID ..." >&2; exit 1; }
  if [[ "$feature" == docker ]]; then
    [[ -S /var/run/docker.sock ]] || { echo "Docker socket is not available on this host." >&2; exit 1; }
    local actual_gid configured_gid
    actual_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || stat -f '%g' /var/run/docker.sock)"
    configured_gid="$(env_value EXECUTION_DOCKER_GID)"
    [[ "$configured_gid" == "$actual_gid" ]] || { echo "EXECUTION_DOCKER_GID=$configured_gid does not match host socket GID=$actual_gid. Re-run ./install.sh --no-start." >&2; exit 1; }
  fi
  if [[ "$feature" == sandbox ]]; then
    local workspace
    workspace="$(env_value EXECUTION_WORKSPACE_HOST_PATH)"
    [[ "$workspace" == /* && "$workspace" != *'/absolute/path/to/'* ]] || { echo "Set EXECUTION_WORKSPACE_HOST_PATH to an absolute workspace path before enabling sandbox." >&2; exit 1; }
    mkdir -p "$workspace"
    [[ "$(env_value EXECUTION_WORKSPACE_GENERATION)" != 0 ]] || set_env EXECUTION_WORKSPACE_GENERATION "$(date +%s)"
  fi
}

doctor() {
  local failed=0 actual_gid configured_gid
  printf 'Hermes Linux Stack Doctor\n\n'
  printf '%-31s ' 'Environment file permissions'; [[ "$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)" == 600 ]] && echo OK || { echo 'WARN (expected 600)'; failed=1; }
  if grep -Eq '^[A-Z0-9_]+=(CHANGE_ME|CHANGE_ME_)' "$ENV_FILE"; then printf '%-31s %s\n' 'Placeholder secrets' 'FAIL'; failed=1; else printf '%-31s %s\n' 'Placeholder secrets' 'OK'; fi
  configured_gid="$(env_value EXECUTION_DOCKER_GID)"
  actual_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
  if [[ -n "$actual_gid" ]]; then
    [[ "$configured_gid" == "$actual_gid" ]] && printf '%-31s %s\n' 'Docker socket GID' 'OK' || { printf '%-31s %s\n' 'Docker socket GID' "FAIL (configured $configured_gid, host $actual_gid)"; failed=1; }
  else printf '%-31s %s\n' 'Docker socket GID' 'N/A (socket absent)'; fi
  if docker compose version >/dev/null 2>&1 && compose config --quiet; then printf '%-31s %s\n' 'Compose configuration' 'OK'; else printf '%-31s %s\n' 'Compose configuration' 'FAIL'; failed=1; fi
  if compose ps -q smart-router 2>/dev/null | grep -q .; then
    if compose exec -T smart-router python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health',timeout=4).read()" >/dev/null 2>&1; then printf '%-31s %s\n' 'Smart Router 0.5.2' 'OK'; else printf '%-31s %s\n' 'Smart Router 0.5.2' 'FAIL'; failed=1; fi
    if compose exec -T smart-router python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/ready',timeout=4).read()" >/dev/null 2>&1; then printf '%-31s %s\n' 'Upstream readiness' 'OK'; else printf '%-31s %s\n' 'Upstream readiness' 'DEGRADED'; fi
  else printf '%-31s %s\n' 'Smart Router 0.5.2' 'STOPPED'; fi
  if grep -Eq '^([A-Z0-9_]+_IMAGE_TAG)=(latest|main)$' "$ENV_FILE"; then printf '%-31s %s\n' 'Mutable image tags' 'INTENTIONAL (pin in .env when desired)'; else printf '%-31s %s\n' 'Mutable image tags' 'PINNED'; fi
  printf '\nUse ./manage.sh health for per-container health and ./manage.sh router-info for router policy/version.\n'
  return "$failed"
}

case "${1:-}" in
  start) compose up -d --build ;;
  stop) compose stop ;;
  restart) compose restart ;;
  restart-hermes) compose restart hermes ;;
  status) if [[ "${2:-}" == --json ]]; then ops status --json; else compose ps; fi ;;
  health) shift; ops health "$@" ;;
  version) ops version ;;
  update) shift; ops update "$@" ;;
  backup|backup-list|restore|rollback|lock-images|verify-images) cmd="$1"; shift; ops "$cmd" "$@" ;;
  logs)
    case "${2:-}" in
      gateway|9router|omniroute) svc=nine-router ;;
      smart-router) svc=smart-router ;;
      hermes) svc=hermes ;;
      webui|open-webui) svc=open-webui ;;
      n8n) svc=n8n ;;
      caddy) svc=caddy ;;
      "") compose logs -f --tail=150; exit ;;
      *) echo "Unknown service" >&2; exit 2 ;;
    esac
    compose logs -f --tail=150 "$svc" ;;
  doctor) doctor ;;
  router-mode|set-router-mode)
    mode="${2:-}"; [[ "$mode" == observe || "$mode" == route ]] || { echo "observe|route required" >&2; exit 2; }
    set_env SMART_ROUTER_MODE "$mode"; compose up -d --no-deps --force-recreate smart-router; echo "router mode: $mode" ;;
  router-policy)
    policy="${2:-}"; [[ "$policy" == heuristic || "$policy" == calibrated || "$policy" == learned ]] || { echo "heuristic|calibrated|learned required" >&2; exit 2; }
    [[ "$policy" != calibrated || -s smart-router/policy/calibrated.json ]] || { echo "calibrated policy missing" >&2; exit 1; }
    set_env SMART_ROUTER_POLICY "$policy"; compose up -d --no-deps --force-recreate smart-router; echo "router policy: $policy" ;;
  router-info)
    compose exec -T smart-router python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/router/info',timeout=5).read().decode())" ;;
  router-calibrate)
    dataset="${2:-}"; [[ -f "$dataset" ]] || { echo "Labeled JSONL file required" >&2; exit 2; }
    dataset="$(cd "$(dirname "$dataset")" && pwd)/$(basename "$dataset")"
    compose run --rm --no-deps -v "$dataset:/work/input.jsonl:ro" -v "$ROOT_DIR/smart-router/policy:/out" smart-router python -m smart_router.eval.calibrate /work/input.jsonl -o /out/calibrated.json
    echo "Wrote smart-router/policy/calibrated.json; review it before enabling calibrated policy." ;;
  router-report)
    dataset="${2:-}"; [[ -f "$dataset" ]] || { echo "Labeled JSONL file required" >&2; exit 2; }
    dataset="$(cd "$(dirname "$dataset")" && pwd)/$(basename "$dataset")"
    compose run --rm --no-deps -v "$dataset:/work/input.jsonl:ro" -v "$ROOT_DIR/smart-router/policy:/work/policy:ro" smart-router python -m smart_router.eval.report /work/input.jsonl --policy /work/policy/calibrated.json ;;
  router-replay)
    dataset="${2:-}"; output="${3:-$ROOT_DIR/data/smart-router/replay-decisions.jsonl}"
    [[ -f "$dataset" ]] || { echo "Request JSONL file required" >&2; exit 2; }
    dataset="$(cd "$(dirname "$dataset")" && pwd)/$(basename "$dataset")"; mkdir -p "$(dirname "$output")"; touch "$output"; output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
    compose run --rm --no-deps -v "$dataset:/work/input.jsonl:ro" -v "$output:/work/output.jsonl" smart-router python -m smart_router.eval.replay /work/input.jsonl -o /work/output.jsonl ;;
  execution-status)
    echo "features=$(env_value EXECUTION_FEATURES)"; echo "profiles=$(env_value COMPOSE_PROFILES)"; compose ps execution-docker-broker execution-ssh-broker execution-approver 2>/dev/null || true ;;
  set-execution-approval-bot-token)
    ensure_execution_secrets
    read -rsp 'Dedicated execution approval Telegram bot token: ' token; echo
    [[ "$token" == *:* && ${#token} -ge 20 ]] || { echo "Token format is invalid." >&2; exit 2; }
    secure_write "$(execution_secret_root)/approval-bot-token" "$token"; ensure_execution_secrets; echo "Approval bot token stored in a mode-0600 secret file." ;;
  set-execution-users)
    shift; (($# > 0)) || { echo "At least one numeric Telegram user ID is required." >&2; exit 2; }
    users=""; for id in "$@"; do [[ "$id" =~ ^[0-9]+$ ]] || { echo "Invalid numeric user ID: $id" >&2; exit 2; }; users="${users:+$users,}$id"; done
    ensure_execution_secrets; secure_write "$(execution_secret_root)/users" "$users"; ensure_execution_secrets; echo "Execution approval users updated." ;;
  enable-execution)
    feature="${2:-}"; [[ "$feature" == sandbox || "$feature" == ssh || "$feature" == docker ]] || { echo "sandbox|ssh|docker required" >&2; exit 2; }
    ensure_execution_secrets; execution_validate_ready "$feature"
    internal="$(execution_feature_name "$feature")"; profile="$(execution_profile_name "$feature")"
    set_csv_item EXECUTION_FEATURES "$internal" 1; set_csv_item COMPOSE_PROFILES "$profile" 1; set_csv_item COMPOSE_PROFILES execution-approval 1
    compose up -d --no-deps "$profile" execution-approver hermes
    echo "$feature execution enabled; every privileged action still requires the independent approval broker." ;;
  disable-execution)
    feature="${2:-}"; [[ "$feature" == sandbox || "$feature" == ssh || "$feature" == docker ]] || { echo "sandbox|ssh|docker required" >&2; exit 2; }
    internal="$(execution_feature_name "$feature")"; set_csv_item EXECUTION_FEATURES "$internal" 0
    # Keep broker profiles if another feature still needs them; otherwise remove the relevant one.
    remaining="$(env_value EXECUTION_FEATURES)"
    if [[ "$feature" == ssh && "$remaining" != *ssh* ]]; then set_csv_item COMPOSE_PROFILES execution-ssh 0; compose stop execution-ssh-broker 2>/dev/null || true; fi
    if [[ "$feature" != ssh && "$remaining" != *local* && "$remaining" != *docker* ]]; then set_csv_item COMPOSE_PROFILES execution-docker 0; compose stop execution-docker-broker 2>/dev/null || true; fi
    if [[ -z "$remaining" ]]; then set_csv_item COMPOSE_PROFILES execution-approval 0; compose stop execution-approver 2>/dev/null || true; fi
    compose up -d --no-deps --force-recreate hermes; echo "$feature execution disabled." ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
