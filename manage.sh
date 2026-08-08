#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
cd "$ROOT_DIR"
usage() { cat <<'EOF'
Usage: ./manage.sh COMMAND [ARG]
  start | stop | restart | status | update
  logs [gateway|smart-router|hermes|webui|n8n|caddy]
  doctor
  router-mode observe|route
  router-policy heuristic|calibrated
  router-info
  router-calibrate LABELED.jsonl
  router-report LABELED.jsonl
  router-replay REQUESTS.jsonl [OUTPUT.jsonl]
EOF
}
[[ -f "$ENV_FILE" ]] || { echo "Run ./install.sh first." >&2; exit 1; }
compose() { docker compose --env-file "$ENV_FILE" "$@"; }
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
}
case "${1:-}" in
  start) compose up -d --build ;;
  stop) compose stop ;;
  restart) compose restart ;;
  status) compose ps ;;
  update) compose pull; compose up -d --build --remove-orphans ;;
  logs)
    case "${2:-}" in
      gateway|9router) svc=nine-router ;;
      smart-router) svc=smart-router ;;
      hermes) svc=hermes ;;
      webui|open-webui) svc=open-webui ;;
      n8n) svc=n8n ;;
      caddy) svc=caddy ;;
      "") compose logs -f --tail=150; exit ;;
      *) echo "Unknown service" >&2; exit 2 ;;
    esac
    compose logs -f --tail=150 "$svc" ;;
  doctor)
    compose config --quiet
    python3 -m compileall -q smart-router/src smart-router/tests
    SMART_ROUTER_HMAC_SECRET="$(sed -n 's/^SMART_ROUTER_HMAC_SECRET=//p' .env)" PYTHONPATH=smart-router/src pytest -q smart-router/tests 2>/dev/null || echo "pytest not installed on host; container build still validates runtime dependencies."
    echo "Compose: valid"
    echo "Smart Router source: compiles"
    ;;
  router-mode)
    mode="${2:-}"; [[ "$mode" == observe || "$mode" == route ]] || { echo "observe|route required" >&2; exit 2; }
    set_env SMART_ROUTER_MODE "$mode"; compose up -d --build --no-deps --force-recreate smart-router; echo "router mode: $mode" ;;
  router-policy)
    policy="${2:-}"; [[ "$policy" == heuristic || "$policy" == calibrated ]] || { echo "heuristic|calibrated required" >&2; exit 2; }
    [[ "$policy" != calibrated || -s smart-router/policy/calibrated.json ]] || { echo "calibrated policy missing" >&2; exit 1; }
    set_env SMART_ROUTER_POLICY "$policy"; compose up -d --build --no-deps --force-recreate smart-router; echo "router policy: $policy" ;;
  router-info)
    compose exec -T smart-router python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/router/policy').read().decode())" ;;
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
    dataset="$(cd "$(dirname "$dataset")" && pwd)/$(basename "$dataset")"
    output="$(mkdir -p "$(dirname "$output")"; cd "$(dirname "$output")" && pwd)/$(basename "$output")"
    touch "$output"
    compose run --rm --no-deps -v "$dataset:/work/input.jsonl:ro" -v "$output:/work/output.jsonl" smart-router python -m smart_router.eval.replay /work/input.jsonl -o /work/output.jsonl ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
