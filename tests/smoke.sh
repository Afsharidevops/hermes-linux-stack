#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/install.sh"
bash -n "$ROOT/manage.sh"
python3 -m py_compile "$ROOT/smart-router/src/smart_router/config.py"

grep -q '^name: hermes-omniroute-stack$' "$ROOT/docker-compose.yml"
grep -q '^  omniroute:$' "$ROOT/docker-compose.yml"
grep -q 'http://omniroute:20129/v1' "$ROOT/docker-compose.yml"
grep -q 'DATA_DIR: /app/data' "$ROOT/docker-compose.yml"
grep -q 'API_PORT: "20129"' "$ROOT/docker-compose.yml"
grep -q 'STORAGE_ENCRYPTION_KEY:' "$ROOT/docker-compose.yml"
grep -q 'MACHINE_ID_SALT:' "$ROOT/docker-compose.yml"
grep -q 'OMNIROUTE_WS_BRIDGE_SECRET:' "$ROOT/docker-compose.yml"
grep -q 'key_env: OMNIROUTE_API_KEY' "$ROOT/templates/hermes-config.yaml.template"
grep -q 'OPENWEBUI_OPENAI_BASE_URL=http://omniroute:20129/v1' "$ROOT/.env.example"

if grep -RInE '(nine-router|NINEROUTER_|decolua/9router)' \
    "$ROOT/docker-compose.yml" "$ROOT/templates" "$ROOT/.env.example" "$ROOT/smart-router/src"; then
  echo 'legacy router identifier found in runtime/config source' >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  tmpenv="$(mktemp)"
  cp "$ROOT/.env.example" "$tmpenv"
  sed -i \
    -e 's/OMNIROUTE_INITIAL_PASSWORD=CHANGE_ME/OMNIROUTE_INITIAL_PASSWORD=test-password/' \
    -e 's/OMNIROUTE_JWT_SECRET=CHANGE_ME/OMNIROUTE_JWT_SECRET=0123456789abcdef0123456789abcdef/' \
    -e 's/OMNIROUTE_API_KEY_SECRET=CHANGE_ME/OMNIROUTE_API_KEY_SECRET=abcdef0123456789abcdef0123456789/' \
    -e 's/OMNIROUTE_STORAGE_ENCRYPTION_KEY=CHANGE_ME/OMNIROUTE_STORAGE_ENCRYPTION_KEY=00112233445566778899aabbccddeeff/' \
    -e 's/OMNIROUTE_MACHINE_ID_SALT=CHANGE_ME/OMNIROUTE_MACHINE_ID_SALT=44556677889900112233aabbccddeeff/' \
    -e 's/OMNIROUTE_WS_BRIDGE_SECRET=CHANGE_ME/OMNIROUTE_WS_BRIDGE_SECRET=55667788990011223344aabbccddeeff/' \
    -e 's/SMART_ROUTER_HMAC_SECRET=CHANGE_ME/SMART_ROUTER_HMAC_SECRET=11223344556677889900aabbccddeeff/' \
    -e 's/OPENWEBUI_SECRET_KEY=CHANGE_ME/OPENWEBUI_SECRET_KEY=22334455667788990011aabbccddeeff/' \
    -e 's/N8N_ENCRYPTION_KEY=CHANGE_ME/N8N_ENCRYPTION_KEY=33445566778899001122aabbccddeeff/' "$tmpenv"
  docker compose -f "$ROOT/docker-compose.yml" --env-file "$tmpenv" config >/dev/null
  rm -f "$tmpenv"
fi

echo 'smoke: PASS'
