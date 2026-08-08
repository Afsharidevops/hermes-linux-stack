#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/install.sh" "$ROOT/manage.sh"
python3 -m compileall -q "$ROOT/smart-router/src" "$ROOT/smart-router/tests"
PYTHONPATH="$ROOT/smart-router/src" pytest -q "$ROOT/smart-router/tests"
python3 - "$ROOT/docker-compose.yml" <<'PY'
import sys, yaml
p=sys.argv[1]
x=yaml.safe_load(open(p,encoding='utf-8'))
s=x['services']['smart-router']
assert s.get('build',{}).get('context') == './smart-router'
assert './smart-router/policy:/policy:ro' in s['volumes']
assert 'SMART_ROUTER_POLICY' in s['environment']
assert 'SMART_ROUTER_OBSERVATION_ENABLED' in s['environment']
print('compose YAML/wiring: OK')
PY
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
PYTHONPATH="$ROOT/smart-router/src" python3 -m smart_router.eval.calibrate "$ROOT/smart-router/examples/labeled-workload.jsonl" -o "$tmp" --weight-passes 0 >/dev/null
PYTHONPATH="$ROOT/smart-router/src" python3 -m smart_router.eval.report "$ROOT/smart-router/examples/labeled-workload.jsonl" --policy "$tmp" >/dev/null
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f "$ROOT/docker-compose.yml" --env-file "$ROOT/.env.example" config --quiet
fi
echo "smoke: OK"
