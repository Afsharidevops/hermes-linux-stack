#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Keep LAN-address suggestions deterministic regardless of the test host.
export HERMES_STACK_LAN_IP=192.168.85.244

copy_fixture() {
  local destination="$1"
  mkdir -p "$destination"
  # A deployed stack may have large live databases under data/. Tests need only
  # the tracked sources and empty persistence directories, never runtime state.
  tar -C "$ROOT_DIR" --exclude=.git --exclude=.env --exclude='data/*/*' -cf - . \
    | tar -C "$destination" -xf -
}

copy_fixture "$TEST_DIR/stack"
rm -f "$TEST_DIR/stack/.env"
rm -f "$TEST_DIR/stack/data/hermes/.env"
rm -f "$TEST_DIR/stack/data/hermes/config.yaml"
rm -f "$TEST_DIR/stack/data/caddy/Caddyfile"

test_token='123456:'
test_token+='abcdefghijklmnopqrstuvwxyzABCDE'

printf '%s\n' \
  '' y y y \
  '' '' test-password '' n \
  '' '' '' '' \
  '' '' '' '' \
  y 2 \
  '' '' y "$test_token" 946652372,7264771088 '' n n \
  '' '' '' y \
  y '' admin@example.com y router.example.com y chat.example.com y n8n.example.com \
  | "$TEST_DIR/stack/install.sh" --dry-run >/dev/null

grep -q '^COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,n8n,caddy$' "$TEST_DIR/stack/.env"
grep -q '^SMART_ROUTER_MODE=observe$' "$TEST_DIR/stack/.env"
grep -q '^SMART_ROUTER_IMAGE=afsharidevops/hermes-smart-router:0.1.0@sha256:4290667e8c90940a5dd97bcd6fd1575c0f1b822db507f9cc5076abe126708bef$' "$TEST_DIR/stack/.env"
grep -q '^SMART_ROUTER_HMAC_SECRET=[0-9a-f]\{64\}$' "$TEST_DIR/stack/.env"
grep -q '^NINEROUTER_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^HERMES_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^NINEROUTER_AUTH_COOKIE_SECURE=true$' "$TEST_DIR/stack/.env"
grep -q '^NINEROUTER_PUBLIC_BASE_URL="https://router.example.com"$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_URL="https://chat.example.com"$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_OPENAI_BASE_URL="http://smart-router:8080/v1"$' "$TEST_DIR/stack/.env"
grep -q '^OPENWEBUI_OPENAI_API_KEY="auto-generated-after-9router-starts"$' "$TEST_DIR/stack/.env"
grep -q "^  provider: 'custom:9router'$" "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q "^  default: 'auto'$" "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q "^    base_url: 'http://smart-router:8080/v1'$" "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^NINEROUTER_API_KEY="auto-generated-after-9router-starts"$' "$TEST_DIR/stack/data/hermes/.env"
grep -q '^NINEROUTER_URL="http://nine-router:20128"$' "$TEST_DIR/stack/data/hermes/.env"
grep -q '^NINEROUTER_KEY="auto-generated-after-9router-starts"$' "$TEST_DIR/stack/data/hermes/.env"
grep -q '^approvals:$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  mode: manual$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  cron_mode: deny$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^skills:$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  write_approval: true$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^    - stack-package-policy$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^    - stack-execution-policy$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  disabled_toolsets: \[\]$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  backend: local$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  max_turns: 90$' "$TEST_DIR/stack/data/hermes/config.yaml"
test -d "$TEST_DIR/stack/data/hermes/lazy-packages"
test -d "$TEST_DIR/stack/data/hermes/npm-packages"
test "$(stat -c '%a' "$TEST_DIR/stack/data/stack-secrets")" = 700
# Capability-dropped bootstrap containers can only traverse mode 700 when the
# directory belongs to the operator uid/gid that manage.sh runs the container as.
test "$(stat -c '%u:%g' "$TEST_DIR/stack/data/stack-secrets")" = "$(id -u):$(id -g)"
test "$(stat -c '%a' "$TEST_DIR/stack/data/stack-secrets/execution/control-secret")" = 640
test "$(stat -c '%a' "$TEST_DIR/stack/data/stack-secrets/execution/users")" = 640
grep -q '^EXECUTION_FEATURES=$' "$TEST_DIR/stack/.env"
! grep -q 'execution-docker\|execution-ssh' < <(sed -n 's/^COMPOSE_PROFILES=//p' "$TEST_DIR/stack/.env")
grep -q './plugins/stack-package-policy:/opt/data/plugins/stack-package-policy:ro' "$TEST_DIR/stack/docker-compose.yml"
grep -q './plugins/stack-execution-policy:/opt/data/plugins/stack-execution-policy:ro' "$TEST_DIR/stack/docker-compose.yml"
grep -q '^[[:space:]]*WEBHOOK_URL: ${N8N_PUBLIC_URL:-http://localhost:5678}$' "$TEST_DIR/stack/docker-compose.yml"
! grep -q '^[[:space:]]*N8N_WEBHOOK_URL:' "$TEST_DIR/stack/docker-compose.yml"
! grep -q "custom:'9router'" "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^router.example.com {$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^[[:space:]]*reverse_proxy nine-router:20128$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^chat.example.com {$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^[[:space:]]*reverse_proxy open-webui:8080$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^N8N_BIND_IP=192.168.85.244$' "$TEST_DIR/stack/.env"
grep -q '^N8N_ENCRYPTION_KEY=[0-9a-f]\{64\}$' "$TEST_DIR/stack/.env"
grep -q '^N8N_PUBLIC_URL="https://n8n.example.com"$' "$TEST_DIR/stack/.env"
grep -q '^N8N_PROTOCOL=https$' "$TEST_DIR/stack/.env"
grep -q '^N8N_SECURE_COOKIE=true$' "$TEST_DIR/stack/.env"
grep -q '^n8n.example.com {$' "$TEST_DIR/stack/data/caddy/Caddyfile"
grep -q '^[[:space:]]*reverse_proxy n8n:5678$' "$TEST_DIR/stack/data/caddy/Caddyfile"
# Mode-specific MCP tokens belong in the mode-0600 Hermes env file, never in config.yaml.
grep -q '^N8N_MCP_MODE=trigger$' "$TEST_DIR/stack/.env"
grep -q '^N8N_TRIGGER_MCP_TOKEN=[0-9a-f]\{64\}$' "$TEST_DIR/stack/data/hermes/.env"
grep -q '^N8N_TRIGGER_MCP_URL="http://n8n:5678/mcp/hermes"$' "$TEST_DIR/stack/data/hermes/.env"
grep -q '^N8N_INSTANCE_MCP_URL="http://n8n:5678/mcp-server/http"$' "$TEST_DIR/stack/data/hermes/.env"
! grep -q '^N8N_MCP_\(TOKEN\|URL\|PATH\)=' "$TEST_DIR/stack/data/hermes/.env"
! grep -q '[0-9a-f]\{64\}' "$TEST_DIR/stack/data/hermes/config.yaml"
test "$(grep -c '^mcp_servers:$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1
grep -q 'Bearer \${N8N_TRIGGER_MCP_TOKEN}' "$TEST_DIR/stack/data/hermes/config.yaml"
test "$(stat -c '%a' "$TEST_DIR/stack/data/hermes/.env")" = 600
expected_hermes_uid="$(id -u)"; expected_hermes_gid="$(id -g)"
if [[ "$expected_hermes_uid" == 0 ]]; then
  expected_hermes_uid=10000; expected_hermes_gid=10000
fi
test "$(stat -c '%u:%g' "$TEST_DIR/stack/data/hermes/.env")" = "$expected_hermes_uid:$expected_hermes_gid"
test "$(stat -c '%a' "$TEST_DIR/stack/data/hermes/config.yaml")" = 640
test "$(stat -c '%u:%g' "$TEST_DIR/stack/data/hermes/config.yaml")" = "$expected_hermes_uid:$expected_hermes_gid"
grep -q "^HERMES_UID=$expected_hermes_uid$" "$TEST_DIR/stack/.env"
grep -q "^HERMES_GID=$expected_hermes_gid$" "$TEST_DIR/stack/.env"
docker compose -f "$TEST_DIR/stack/docker-compose.yml" --env-file "$TEST_DIR/stack/.env" config --quiet

if [[ "${CADDY_VALIDATE_WITH_DOCKER:-false}" == true ]]; then
  docker run --rm \
    -v "$TEST_DIR/stack/data/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
    caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile
fi

# Reconfiguring n8n must preserve the encryption key and Trigger token and must
# not duplicate the installer-owned config block.
n8n_key="$(sed -n 's/^N8N_ENCRYPTION_KEY=//p' "$TEST_DIR/stack/.env")"
n8n_token="$(sed -n 's/^N8N_TRIGGER_MCP_TOKEN=//p' "$TEST_DIR/stack/data/hermes/.env")"
printf '%s\n' \
  n n n y n y y n \
  '' '' '' '' y '' n \
  | "$TEST_DIR/stack/install.sh" --dry-run >/dev/null
test "$n8n_key" = "$(sed -n 's/^N8N_ENCRYPTION_KEY=//p' "$TEST_DIR/stack/.env")"
test "$n8n_token" = "$(sed -n 's/^N8N_TRIGGER_MCP_TOKEN=//p' "$TEST_DIR/stack/data/hermes/.env")"
test "$(grep -c '^mcp_servers:$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1

# Existing policy sections are reconciled field-by-field without removing
# unrelated user settings or duplicating managed keys.
python3 - "$TEST_DIR/stack/data/hermes/config.yaml" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = re.sub(
    r"approvals:\n(?:  .*\n)*",
    "approvals:\n  mode: off\n  timeout: 10\n  cron_mode: allow\n  user_option: keep\n",
    text,
    count=1,
)
text = re.sub(
    r"skills:\n(?:  .*\n)*",
    "skills:\n  write_approval: false\n  user_option: keep\n",
    text,
    count=1,
)
path.write_text(text)
PY
printf '%s\n' n n n y n y n n n \
  | "$TEST_DIR/stack/install.sh" --dry-run >/dev/null
test "$(grep -c '^  mode: manual$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1
test "$(grep -c '^  timeout: 300$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1
test "$(grep -c '^  cron_mode: deny$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1
test "$(grep -c '^  write_approval: true$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1
grep -q '^  user_option: keep$' "$TEST_DIR/stack/data/hermes/config.yaml"

# If a user already has other MCP servers, adding/removing the managed n8n
# entry must preserve the existing map instead of creating a duplicate key.
awk '
  { print }
  $0 == "mcp_servers:" {
    print "  existing:"
    print "    url: \"http://existing:1234/mcp\""
  }
' "$TEST_DIR/stack/data/hermes/config.yaml" > "$TEST_DIR/stack/data/hermes/config.yaml.with-existing"
mv "$TEST_DIR/stack/data/hermes/config.yaml.with-existing" "$TEST_DIR/stack/data/hermes/config.yaml"
printf '%s\n' n n n y n y y n '' '' '' '' y '' n \
  | "$TEST_DIR/stack/install.sh" --dry-run >/dev/null
test "$(grep -c '^mcp_servers:$' "$TEST_DIR/stack/data/hermes/config.yaml")" = 1
grep -q '^  existing:$' "$TEST_DIR/stack/data/hermes/config.yaml"
grep -q '^  n8n:$' "$TEST_DIR/stack/data/hermes/config.yaml"

# Disabling the profile removes Hermes MCP wiring while keeping n8n's data and
# encryption key available for a later re-enable.
cp -a "$TEST_DIR/stack" "$TEST_DIR/n8n-disabled"
printf '%s\n' n n n y n n n n \
  | "$TEST_DIR/n8n-disabled/install.sh" --dry-run >/dev/null
grep -q '^COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,caddy$' "$TEST_DIR/n8n-disabled/.env"
test "$n8n_key" = "$(sed -n 's/^N8N_ENCRYPTION_KEY=//p' "$TEST_DIR/n8n-disabled/.env")"
grep -q '^mcp_servers:$' "$TEST_DIR/n8n-disabled/data/hermes/config.yaml"
grep -q '^  existing:$' "$TEST_DIR/n8n-disabled/data/hermes/config.yaml"
! grep -q '^  n8n:$' "$TEST_DIR/n8n-disabled/data/hermes/config.yaml"
! grep -q '^N8N_\(MCP_\|TRIGGER_MCP_\|INSTANCE_MCP_\)' "$TEST_DIR/n8n-disabled/data/hermes/.env"
test -d "$TEST_DIR/n8n-disabled/data/n8n"

# Enabling only the MCP bridge on an otherwise unchanged installation must
# reconcile Hermes even when neither Hermes nor n8n itself is reconfigured.
cp -a "$TEST_DIR/n8n-disabled" "$TEST_DIR/mcp-transition"
sed -i 's/^COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,caddy$/COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,n8n,caddy/' \
  "$TEST_DIR/mcp-transition/.env"
printf '%s\n' n n n y n y n n y 2 n \
  | "$TEST_DIR/mcp-transition/install.sh" --dry-run \
    > "$TEST_DIR/mcp-transition.out"
grep -q '^N8N_MCP_MODE=trigger$' "$TEST_DIR/mcp-transition/.env"
grep -q '^N8N_TRIGGER_MCP_URL="http://n8n:5678/mcp/hermes"$' "$TEST_DIR/mcp-transition/data/hermes/.env"
grep -q '^N8N_INSTANCE_MCP_URL="http://n8n:5678/mcp-server/http"$' "$TEST_DIR/mcp-transition/data/hermes/.env"
test "$(grep -c '^N8N_TRIGGER_MCP_TOKEN=[0-9a-f]\{64\}$' "$TEST_DIR/mcp-transition/data/hermes/.env")" = 1
test "$(grep -c '^  n8n:$' "$TEST_DIR/mcp-transition/data/hermes/config.yaml")" = 1
test "$(grep -c '^  # >>> hermes-stack n8n mcp (managed) >>>$' "$TEST_DIR/mcp-transition/data/hermes/config.yaml")" = 1
transition_token="$(sed -n 's/^N8N_TRIGGER_MCP_TOKEN=//p' "$TEST_DIR/mcp-transition/data/hermes/.env")"
! grep -Fq "$transition_token" "$TEST_DIR/mcp-transition.out"

# Selecting Instance-level MCP without a UI-generated personal token records a
# pending mode but must not render an unusable Hermes MCP entry or invent a token.
cp -a "$TEST_DIR/n8n-disabled" "$TEST_DIR/instance-pending"
sed -i 's/^COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,caddy$/COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,n8n,caddy/' \
  "$TEST_DIR/instance-pending/.env"
printf '%s\n' n n n y n y n n y 1 n \
  | "$TEST_DIR/instance-pending/install.sh" --dry-run \
    > "$TEST_DIR/instance-pending.out"
grep -q '^N8N_MCP_MODE=instance$' "$TEST_DIR/instance-pending/.env"
grep -q '^N8N_INSTANCE_MCP_URL="http://n8n:5678/mcp-server/http"$' "$TEST_DIR/instance-pending/data/hermes/.env"
! grep -q '^N8N_INSTANCE_MCP_TOKEN=' "$TEST_DIR/instance-pending/data/hermes/.env"
! grep -q '^  n8n:$' "$TEST_DIR/instance-pending/data/hermes/config.yaml"
grep -q 'Instance-level MCP is selected but pending' "$TEST_DIR/instance-pending.out"

copy_fixture "$TEST_DIR/no-caddy"
rm -f "$TEST_DIR/no-caddy/.env"
rm -f "$TEST_DIR/no-caddy/data/caddy/Caddyfile"
printf '2\nn\nn\n\n\nsecond-password\n\nn\nn\n' \
  | "$TEST_DIR/no-caddy/install.sh" --dry-run >/dev/null
grep -q '^COMPOSE_PROFILES=9router$' "$TEST_DIR/no-caddy/.env"
grep -q '^NINEROUTER_BIND_IP=192.168.85.244$' "$TEST_DIR/no-caddy/.env"
grep -q '^NINEROUTER_PUBLIC_BASE_URL="http://192.168.85.244:20128"$' "$TEST_DIR/no-caddy/.env"
test ! -f "$TEST_DIR/no-caddy/data/caddy/Caddyfile"
docker compose -f "$TEST_DIR/no-caddy/docker-compose.yml" --env-file "$TEST_DIR/no-caddy/.env" config --quiet

# A second wizard run must preserve 9router while adding Hermes and Caddy.
printf '%s\n' \
  n y n n n n \
  '' '' '' n n n \
  y '' '' y router-added.example.com \
  | "$TEST_DIR/no-caddy/install.sh" --dry-run >/dev/null
grep -q '^COMPOSE_PROFILES=9router,hermes,caddy$' "$TEST_DIR/no-caddy/.env"
grep -q '^NINEROUTER_INITIAL_PASSWORD="second-password"$' "$TEST_DIR/no-caddy/.env"
grep -q '^router-added.example.com {$' "$TEST_DIR/no-caddy/data/caddy/Caddyfile"
test -f "$TEST_DIR/no-caddy/data/hermes/config.yaml"
docker compose -f "$TEST_DIR/no-caddy/docker-compose.yml" --env-file "$TEST_DIR/no-caddy/.env" config --quiet

# Bind addresses can be changed later without reconfiguring service secrets.
hermes_env_checksum="$(sha256sum "$TEST_DIR/no-caddy/data/hermes/.env")"
printf 'n\nn\nn\nn\nn\ny\n0.0.0.0\n192.168.10.20\n192.168.10.21\nn\n' \
  | "$TEST_DIR/no-caddy/install.sh" --dry-run >/dev/null
grep -q '^NINEROUTER_BIND_IP=0.0.0.0$' "$TEST_DIR/no-caddy/.env"
grep -q '^HERMES_BIND_IP=192.168.10.20$' "$TEST_DIR/no-caddy/.env"
grep -q '^CADDY_BIND_IP=192.168.10.21$' "$TEST_DIR/no-caddy/.env"
test "$hermes_env_checksum" = "$(sha256sum "$TEST_DIR/no-caddy/data/hermes/.env")"
docker compose -f "$TEST_DIR/no-caddy/docker-compose.yml" --env-file "$TEST_DIR/no-caddy/.env" config --quiet

# Duplicate encryption-key entries are ambiguous because Compose uses the last
# value. Reconfiguration must fail before rewriting either entry.
cp -a "$TEST_DIR/stack" "$TEST_DIR/duplicate-env"
printf 'N8N_ENCRYPTION_KEY=%064d\n' 0 >> "$TEST_DIR/duplicate-env/.env"
duplicate_env_checksum="$(sha256sum "$TEST_DIR/duplicate-env/.env")"
if printf '%s\n' n n n n n n n \
  | "$TEST_DIR/duplicate-env/install.sh" --dry-run >"$TEST_DIR/duplicate-env.out" 2>&1; then
  printf 'Duplicate N8N_ENCRYPTION_KEY unexpectedly passed.\n' >&2
  exit 1
fi
grep -q 'Duplicate N8N_ENCRYPTION_KEY entries' "$TEST_DIR/duplicate-env.out"
test "$duplicate_env_checksum" = "$(sha256sum "$TEST_DIR/duplicate-env/.env")"

# Duplicate managed top-level sections must fail closed before policy rewrite.
for section in approvals plugins agent; do
  cp -a "$TEST_DIR/stack" "$TEST_DIR/duplicate-$section"
  printf '\n%s:\n  user_value: keep\n' "$section" \
    >> "$TEST_DIR/duplicate-$section/data/hermes/config.yaml"
  if printf '%s\n' n n n y n n y n n \
    | "$TEST_DIR/duplicate-$section/install.sh" --dry-run \
      >"$TEST_DIR/duplicate-$section.out" 2>&1; then
    printf 'Duplicate %s section unexpectedly passed.\n' "$section" >&2
    exit 1
  fi
  grep -q "Duplicate top-level $section" "$TEST_DIR/duplicate-$section.out"
done

# An unmatched installer marker must never cause the remainder of config.yaml
# to be truncated while n8n is reconfigured.
cp -a "$TEST_DIR/stack" "$TEST_DIR/unmatched-marker"
python3 - "$TEST_DIR/unmatched-marker/data/hermes/config.yaml" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "  # <<< hermes-stack n8n mcp (managed) <<<\n",
    "",
    1,
)
path.write_text(text)
PY
marker_checksum="$(sha256sum "$TEST_DIR/unmatched-marker/data/hermes/config.yaml")"
if printf '%s\n' n n n y n y y n '' '' '' '' y '' n \
  | "$TEST_DIR/unmatched-marker/install.sh" --dry-run \
    >"$TEST_DIR/unmatched-marker.out" 2>&1; then
  printf 'Unmatched n8n MCP marker unexpectedly passed.\n' >&2
  exit 1
fi
grep -q 'incomplete or duplicate managed n8n MCP markers' "$TEST_DIR/unmatched-marker.out"
test "$marker_checksum" = "$(sha256sum "$TEST_DIR/unmatched-marker/data/hermes/config.yaml")"

# Invalid numeric answers must retry in-place rather than aborting the wizard.
copy_fixture "$TEST_DIR/retry-inputs"
rm -f "$TEST_DIR/retry-inputs/.env"
rm -f "$TEST_DIR/retry-inputs/data/hermes/.env"
rm -f "$TEST_DIR/retry-inputs/data/hermes/config.yaml"
printf '%s\n' \
  invalid 1 n n n \
  '' not-a-port 20128 retry-password '' n \
  '' '' '' y \
  "$test_token" 111111111 invalid-home 111111111 n n \
  n \
  | "$TEST_DIR/retry-inputs/install.sh" --dry-run >/dev/null

grep -q '^NINEROUTER_PORT=20128$' "$TEST_DIR/retry-inputs/.env"
grep -q '^TELEGRAM_HOME_CHANNEL=111111111$' "$TEST_DIR/retry-inputs/data/hermes/.env"

printf 'Installer smoke test passed.\n'
