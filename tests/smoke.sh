#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Keep LAN-address suggestions deterministic regardless of the test host.
export HERMES_STACK_LAN_IP=192.168.85.244

cp -a "$ROOT_DIR/." "$TEST_DIR/stack"
rm -f "$TEST_DIR/stack/.env"
rm -f "$TEST_DIR/stack/data/hermes/.env"
rm -f "$TEST_DIR/stack/data/hermes/config.yaml"
rm -f "$TEST_DIR/stack/data/caddy/Caddyfile"

test_token='123456:'
test_token+='abcdefghijklmnopqrstuvwxyzABCDE'

printf '\ny\n\n\ntest-password\n\nn\n\n\n\n\ny\n%s\n946652372,7264771088\n\nn\nn\n\n\n\ny\ny\n\nadmin@example.com\ny\nrouter.example.com\ny\nchat.example.com\n' "$test_token" \
  | "$TEST_DIR/stack/install.sh" --dry-run >/dev/null

grep -q '^COMPOSE_PROFILES=9router,hermes,open-webui,caddy$' "$TEST_DIR/stack/.env"
grep -q '^NINEROUTER_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^HERMES_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^NINEROUTER_AUTH_COOKIE_SECURE=true$' "$TEST_DIR/stack/.env"
grep -q '^NINEROUTER_PUBLIC_BASE_URL="https://router.example.com"$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_URL="https://chat.example.com"$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_OPENAI_API_KEY="auto-generated-after-9router-starts"$' "$TEST_DIR/stack/.env"
grep -q '^router.example.com {$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^[[:space:]]*reverse_proxy nine-router:20128$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^chat.example.com {$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^[[:space:]]*reverse_proxy open-webui:8080$' "$TEST_DIR/stack/data/caddy/Caddyfile"
docker compose -f "$TEST_DIR/stack/docker-compose.yml" --env-file "$TEST_DIR/stack/.env" config --quiet

if [[ "${CADDY_VALIDATE_WITH_DOCKER:-false}" == true ]]; then
  docker run --rm \
    -v "$TEST_DIR/stack/data/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
    caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile
fi

cp -a "$ROOT_DIR/." "$TEST_DIR/no-caddy"
rm -f "$TEST_DIR/no-caddy/.env"
rm -f "$TEST_DIR/no-caddy/data/caddy/Caddyfile"
printf '2\nn\n\n\nsecond-password\n\nn\nn\n' \
  | "$TEST_DIR/no-caddy/install.sh" --dry-run >/dev/null
grep -q '^COMPOSE_PROFILES=9router$' "$TEST_DIR/no-caddy/.env"
grep -q '^NINEROUTER_BIND_IP=192.168.85.244$' "$TEST_DIR/no-caddy/.env"
grep -q '^NINEROUTER_PUBLIC_BASE_URL="http://192.168.85.244:20128"$' "$TEST_DIR/no-caddy/.env"
test ! -f "$TEST_DIR/no-caddy/data/caddy/Caddyfile"
docker compose -f "$TEST_DIR/no-caddy/docker-compose.yml" --env-file "$TEST_DIR/no-caddy/.env" config --quiet

# A second wizard run must preserve 9router while adding Hermes and Caddy.
printf 'n\ny\nn\nn\n\n\n\n\nn\nn\nn\ny\n\n\ny\nrouter-added.example.com\n' \
  | "$TEST_DIR/no-caddy/install.sh" --dry-run >/dev/null
grep -q '^COMPOSE_PROFILES=9router,hermes,caddy$' "$TEST_DIR/no-caddy/.env"
grep -q '^NINEROUTER_INITIAL_PASSWORD="second-password"$' "$TEST_DIR/no-caddy/.env"
grep -q '^router-added.example.com {$' "$TEST_DIR/no-caddy/data/caddy/Caddyfile"
test -f "$TEST_DIR/no-caddy/data/hermes/config.yaml"
docker compose -f "$TEST_DIR/no-caddy/docker-compose.yml" --env-file "$TEST_DIR/no-caddy/.env" config --quiet

# Bind addresses can be changed later without reconfiguring service secrets.
hermes_env_checksum="$(sha256sum "$TEST_DIR/no-caddy/data/hermes/.env")"
printf 'n\nn\nn\ny\n0.0.0.0\n192.168.10.20\n192.168.10.21\nn\n' \
  | "$TEST_DIR/no-caddy/install.sh" --dry-run >/dev/null
grep -q '^NINEROUTER_BIND_IP=0.0.0.0$' "$TEST_DIR/no-caddy/.env"
grep -q '^HERMES_BIND_IP=192.168.10.20$' "$TEST_DIR/no-caddy/.env"
grep -q '^CADDY_BIND_IP=192.168.10.21$' "$TEST_DIR/no-caddy/.env"
test "$hermes_env_checksum" = "$(sha256sum "$TEST_DIR/no-caddy/data/hermes/.env")"
docker compose -f "$TEST_DIR/no-caddy/docker-compose.yml" --env-file "$TEST_DIR/no-caddy/.env" config --quiet

printf 'Installer smoke test passed.\n'
