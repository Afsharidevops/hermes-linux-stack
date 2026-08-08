#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
NO_START=false
[[ "${1:-}" == "--no-start" ]] && NO_START=true
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { echo "Usage: ./install.sh [--no-start]"; exit 0; }
command -v docker >/dev/null || { echo "Docker is required." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose plugin is required." >&2; exit 1; }
[[ -f .env ]] || cp .env.example .env
chmod 600 .env
mkdir -p data/9router data/hermes data/open-webui data/caddy data/smart-router data/n8n data/stack-secrets
chmod 700 data/smart-router data/stack-secrets || true
python3 - "$ROOT_DIR/.env" <<'PYENV'
import secrets, sys
p=sys.argv[1]
lines=open(p,encoding='utf-8').read().splitlines()
secret_keys={
    'NINEROUTER_INITIAL_PASSWORD','NINEROUTER_JWT_SECRET','NINEROUTER_API_KEY_SECRET',
    'NINEROUTER_MACHINE_ID_SALT','SMART_ROUTER_HMAC_SECRET','OPENWEBUI_SECRET_KEY','N8N_ENCRYPTION_KEY'
}

out=[]
for line in lines:
    if '=' not in line or line.lstrip().startswith('#'):
        out.append(line); continue
    k,v=line.split('=',1)
    if v=='CHANGE_ME' and k in secret_keys:
        n=24 if k.endswith('INITIAL_PASSWORD') else 48
        v=secrets.token_urlsafe(n)
    elif v=='CHANGE_ME':
        v=secrets.token_urlsafe(32)
    out.append(f"{k}={v}")
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PYENV
if [[ ! -f data/hermes/config.yaml ]]; then
  cp templates/hermes-config.yaml.template data/hermes/config.yaml
fi
if [[ ! -f data/hermes/.env ]]; then
  umask 077
  cat > data/hermes/.env <<'EOFH'
NINEROUTER_API_KEY=local-internal
# Configure Telegram only if you use it.
TELEGRAM_BOT_TOKEN=
TELEGRAM_ALLOWED_USERS=
EOFH
fi
if [[ ! -f data/caddy/Caddyfile ]]; then cp examples/caddy/Caddyfile data/caddy/Caddyfile; fi
printf '
Configured %s + Smart Router v0.2.
' '9router'
printf 'Default router state: observe + heuristic.
'
if $NO_START; then
  echo "Configuration created; containers were not started."
else
  docker compose --env-file .env config --quiet
  docker compose --env-file .env up -d --build
  echo "Stack started. Use ./manage.sh status and ./manage.sh router-info."
fi
