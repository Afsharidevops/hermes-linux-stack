#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
NO_START=false
case "${1:-}" in
  --no-start) NO_START=true ;;
  --help|-h) echo "Usage: ./install.sh [--no-start]"; exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }
if ! $NO_START; then
  command -v docker >/dev/null || { echo "Docker is required (or use --no-start to generate configuration only)." >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "Docker Compose plugin is required." >&2; exit 1; }
fi
[[ -f .env ]] || cp .env.example .env
chmod 600 .env
mkdir -p data/omniroute data/hermes data/open-webui data/caddy data/smart-router data/n8n data/stack-secrets data/stack-state
chmod 700 data/smart-router data/stack-secrets data/stack-state 2>/dev/null || true

python3 - "$ROOT_DIR/.env" <<'PYENV'
import secrets, sys
p=sys.argv[1]
lines=open(p,encoding='utf-8').read().splitlines()
force_generate={
  'SMART_ROUTER_HMAC_SECRET','SMART_ROUTER_ADMIN_API_KEY',
  'SMART_ROUTER_BOOTSTRAP_ADMIN_PASSWORD','SMART_ROUTER_PG_PASSWORD',
  'SMART_ROUTER_CLIENT_API_KEY','OPENWEBUI_SECRET_KEY','N8N_ENCRYPTION_KEY'
}
out=[]; values={}
for line in lines:
    if '=' not in line or line.lstrip().startswith('#'):
        out.append(line); continue
    k,v=line.split('=',1)
    if k.endswith('_FILE'):
        out.append(line); values[k]=v; continue
    if v.startswith('CHANGE_ME') or (k in force_generate and not v.strip()):
        n=24 if k.endswith('INITIAL_PASSWORD') or k.endswith('ADMIN_PASSWORD') else 48
        v=secrets.token_urlsafe(n)
    values[k]=v
    out.append(f"{k}={v}")
client=values.get('SMART_ROUTER_CLIENT_API_KEY','').strip()
if not client:
    client=secrets.token_urlsafe(48)
# Synchronize trusted local clients with the router's generated client key.
result=[]; seen=set()
for line in out:
    if '=' in line and not line.lstrip().startswith('#'):
        k=line.split('=',1)[0]
        if k=='SMART_ROUTER_CLIENT_API_KEY': line=f'SMART_ROUTER_CLIENT_API_KEY={client}'
        elif k=='OPENWEBUI_OPENAI_API_KEY': line=f'OPENWEBUI_OPENAI_API_KEY={client}'
        seen.add(k)
    result.append(line)
for k,v in [('SMART_ROUTER_CLIENT_API_KEY',client),('OPENWEBUI_OPENAI_API_KEY',client)]:
    if k not in seen: result.append(f'{k}={v}')
open(p,'w',encoding='utf-8').write('\n'.join(result)+'\n')
PYENV
chmod 600 .env

# Detect the host Docker socket group for the isolated execution broker.
if [[ -S /var/run/docker.sock ]]; then
  docker_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || stat -f '%g' /var/run/docker.sock)"
  python3 - "$ROOT_DIR/.env" "$docker_gid" <<'PYGID'
import sys
p,gid=sys.argv[1:]
lines=open(p,encoding='utf-8').read().splitlines(); out=[]; found=False
for line in lines:
    if line.startswith('EXECUTION_DOCKER_GID='):
        line='EXECUTION_DOCKER_GID='+gid; found=True
    out.append(line)
if not found: out.append('EXECUTION_DOCKER_GID='+gid)
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PYGID
else
  echo "NOTICE: /var/run/docker.sock is absent. Docker execution remains disabled; EXECUTION_DOCKER_GID stays 0." >&2
fi

[[ -f data/hermes/config.yaml ]] || cp templates/hermes-config.yaml.template data/hermes/config.yaml
# Hermes talks to Smart Router, so its historical gateway-named key must match the router client key.
client_key="$(sed -n 's/^SMART_ROUTER_CLIENT_API_KEY=//p' .env | tail -1)"
python3 - "$ROOT_DIR/data/hermes/.env" 'OMNIROUTE_API_KEY' "$client_key" <<'PYHERMES'
import os, sys
p,k,v=sys.argv[1:]
lines=[]
if os.path.exists(p): lines=open(p,encoding='utf-8').read().splitlines()
out=[]; found=False
for line in lines:
    if line.startswith(k+'='): line=k+'='+v; found=True
    out.append(line)
if not found: out.insert(0,k+'='+v)
if not any(x.startswith('TELEGRAM_BOT_TOKEN=') for x in out): out += ['# Configure Telegram only if you use it.','TELEGRAM_BOT_TOKEN=','TELEGRAM_ALLOWED_USERS=']
os.makedirs(os.path.dirname(p),exist_ok=True)
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
os.chmod(p,0o600)
PYHERMES
[[ -f data/caddy/Caddyfile ]] || cp examples/caddy/Caddyfile data/caddy/Caddyfile

printf '
Configured OmniRoute + Smart Router v0.5.2.
'
printf 'Router auth: enabled. Open WebUI signup: disabled. Mode: observe + heuristic.
'
printf 'Image tags default to latest/main and can be pinned later in .env.
'
if $NO_START; then
  echo "Configuration created; containers were not started."
else
  docker compose --env-file .env config --quiet
  docker compose --env-file .env up -d --build
  echo "Stack started. Run ./manage.sh doctor and ./manage.sh router-info."
fi
