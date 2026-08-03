# Hermes + 9router + Open WebUI Linux Stack

Interactive, public-safe Docker deployment for:

- [9router](https://github.com/decolua/9router) — OpenAI-compatible provider router
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — persistent AI agent with Telegram
- [Open WebUI](https://github.com/open-webui/open-webui) — optional browser chat interface

The installer asks what to install and collects all required settings. You can
install both 9router and Hermes, either service alone, add Open WebUI to any
selection, or install Open WebUI by itself.

## Features

- Interactive setup with hidden secret prompts
- Official multi-architecture container images
- Works on common AMD64 and ARM64 Linux servers
- Persistent data stored under `data/`
- Telegram polling: no domain, inbound port, or SSL required
- Numeric Telegram user allowlist
- Private Docker network between services
- Localhost-only published ports by default
- Optional Hermes dashboard and API
- Optional Open WebUI connected to 9router or another OpenAI-compatible API
- Secure generated JWT, signing, machine-ID, WebUI, and API secrets
- Reconfiguration backups
- Simple update, logs, status, and user-management commands
- GitHub Actions validation for shell and Compose files

## Architecture

```text
Telegram API
    ↑ outbound polling
    │
Hermes Agent ──────→ 9router ──────→ configured AI providers
    │                   ↑
    │                   │
    └──── shared Docker network ─── Open WebUI

Host defaults:
  9router:    127.0.0.1:20128
  Open WebUI: 127.0.0.1:3000
  Hermes API: 127.0.0.1:8642 (disabled unless selected)
  Hermes UI:  127.0.0.1:9119 (disabled unless selected)
```

## Requirements

- Linux server
- Bash 4 or newer
- Docker Engine with the `docker compose` plugin
- `curl` if you want the wizard to install Docker
- At least 2 GB RAM recommended for the full stack
- Sufficient disk for container images and persistent chats

If Docker is missing, the installer asks permission before downloading and
running Docker's official convenience installer.

## Quick start

One-command interactive installation:

```bash
curl -fsSL https://raw.githubusercontent.com/Afsharidevops/hermes-linux-stack/main/install.sh | bash
```

This clones or updates the full project at `$HOME/hermes-linux-stack`, then
opens the interactive wizard. Choose another location with:

```bash
curl -fsSL https://raw.githubusercontent.com/Afsharidevops/hermes-linux-stack/main/install.sh | HERMES_STACK_DIR=/opt/hermes-linux-stack bash
```

The target parent directory must be writable by the current user. The installer
uses `sudo` only when Docker administration requires it.

Alternatively, clone and run directly:

```bash
git clone https://github.com/Afsharidevops/hermes-linux-stack.git
cd hermes-linux-stack
chmod +x install.sh manage.sh
./install.sh
```

The installer asks:

1. Which services to install
2. Whether to add Open WebUI
3. Bind addresses and ports
4. 9router dashboard password and public URL
5. Whether `/v1` requires a Bearer key
6. 9router model/combo name used by Hermes
7. Telegram BotFather token and allowed numeric IDs
8. Optional Telegram home channel
9. Optional Hermes dashboard and API
10. Open WebUI endpoint, API key, URL, and signup policy

Secrets are written to ignored files with mode `0600`:

- `.env` — Compose and service secrets
- `data/hermes/.env` — Hermes/Telegram secrets

Never commit either file.

## First setup when installing all services

### 1. Open 9router

The default bind is localhost. From your workstation, create an SSH tunnel:

```bash
ssh -L 20128:127.0.0.1:20128 user@your-server
```

Then open <http://localhost:20128> and sign in with the initial password entered
during installation.

Configure provider accounts and create a combo/model such as `ai`. The combo
name must match the model name entered in the installer.

### 2. Configure endpoint authentication

For a fresh private installation, leaving `REQUIRE_API_KEY=false` allows Hermes
and Open WebUI to connect immediately over the private Docker network.

For stronger protection:

1. Generate an endpoint API key in the 9router dashboard.
2. Set `NINEROUTER_REQUIRE_API_KEY=true` in `.env`.
3. Give the key to Hermes:

```bash
./manage.sh set-backend-api-key YOUR_9ROUTER_API_KEY
./manage.sh restart
```

For Open WebUI, update the key in Admin Panel → Settings → Connections. Open
WebUI persists connection settings in its database after first launch, so a
later `.env` change does not override the saved UI setting.

Do not use provider master/management keys when a scoped endpoint key is
available.

### 3. Test Telegram

Open the bot created with BotFather and send:

```text
/start
```

Hermes accepts only IDs in `TELEGRAM_ALLOWED_USERS`. Telegram usernames are not
authorization IDs. You can obtain your numeric ID from `@userinfobot`.

If Hermes says no home channel is configured, send `/sethome` in the one chat
that should receive cron results and cross-platform notifications. Other
allowed users can still chat normally.

### 4. Create the first Open WebUI account

Tunnel the default Open WebUI port:

```bash
ssh -L 3000:127.0.0.1:3000 user@your-server
```

Open <http://localhost:3000>. The first registered account becomes the
administrator. After creating it, open Admin Panel → Settings → General and
turn off new-user signup.

Open WebUI persists some configuration in its own database after first start.
Later connection changes can also be made in its Admin Panel.

## Management commands

Open the lightweight terminal UI:

```bash
./manage.sh menu
```

It provides status, Telegram access management, restarts, updates, logs, and
reconfiguration without exposing another web administration service.

```bash
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh update
./manage.sh status
./manage.sh doctor
./manage.sh logs
./manage.sh logs hermes
./manage.sh logs 9router
./manage.sh logs webui
./manage.sh configure
```

### Telegram access

Show the current allowlist:

```bash
./manage.sh show-telegram-users
```

Add one user without removing existing users:

```bash
./manage.sh add-telegram-user 946652372
```

Replace the complete list:

```bash
./manage.sh set-telegram-users 946652372,7264771088,445110861
```

Hermes is recreated automatically after an allowlist change.

### Backend key

```bash
./manage.sh set-backend-api-key YOUR_KEY
```

Use Open WebUI's Admin Panel for post-install connection and signup changes,
because those settings become persistent database configuration after first
launch.

## Updating

Update all selected services to the current official image tags:

```bash
./manage.sh update
```

This performs `docker compose pull` and recreates containers without deleting
persistent data.

For reproducible production deployments, replace `latest`/`main` in `.env`
with tested version tags before publishing a release.

## Backups

Stop services for a consistent filesystem backup:

```bash
./manage.sh stop
tar --exclude='./.git' -czf ../hermes-stack-backup.tar.gz .env data
./manage.sh start
chmod 600 ../hermes-stack-backup.tar.gz
```

The archive contains secrets, provider data, Telegram sessions, chats, and
9router's SQLite database. Store it as sensitive material.

Restore by extracting `.env` and `data/` into a fresh clone, then run:

```bash
./manage.sh start
```

## Public access, domains, and Caddy

Telegram polling requires no public route. Keep ports bound to `127.0.0.1` and
use SSH tunnels unless public browser access is necessary.

An example is available at `examples/caddy/Caddyfile`:

```caddyfile
9router.example.com {
    reverse_proxy 127.0.0.1:20128
}

chat.example.com {
    reverse_proxy 127.0.0.1:3000
}
```

When using HTTPS for 9router, enter the HTTPS URL during setup so secure auth
cookies are enabled. Point DNS records to the Linux server and allow ports 80
and 443. Keep the application ports blocked from the public internet.

Before publishing Hermes's dashboard or API, review its authentication options
and keep `API_SERVER_KEY` enabled. Do not expose unauthenticated administration
interfaces.

## Install selections

The generated `COMPOSE_PROFILES` value controls active services:

```env
COMPOSE_PROFILES=9router,hermes,open-webui
```

Valid profile names are:

- `9router`
- `hermes`
- `open-webui`

Rerun `./install.sh` or `./manage.sh configure` to change the selection. Existing
configuration files receive timestamped backups before replacement.
Generated signing secrets are preserved during reconfiguration. The 9router
`INITIAL_PASSWORD` is used only when its database has no saved password, so
rerunning the installer does not reset an existing dashboard account password.

## Manual Compose operation

The management wrapper is optional. Standard commands work:

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f --tail=100
docker compose down
```

Do not use `docker compose down -v`; persistent data uses bind mounts, but this
habit can still be destructive in extended versions of the stack.

## Troubleshooting

Run diagnostics:

```bash
./manage.sh doctor
```

If Hermes cannot reach a bundled 9router, confirm its base URL is:

```text
http://nine-router:20128/v1
```

Inside containers, `localhost` means that container itself. For a service on
the Linux Docker host, use:

```text
http://host.docker.internal:PORT/v1
```

The Compose file adds the Linux `host-gateway` mapping automatically.

If Telegram does not connect:

```bash
./manage.sh logs hermes
```

Verify the BotFather token, numeric allowlist, outbound DNS, and HTTPS access to
Telegram. Do not run two Hermes gateways with the same bot token.

If Open WebUI does not show models, verify the 9router combo exists and confirm
the API URL and key in Open WebUI Admin Panel → Settings → Connections.

## Publishing to your public GitHub

Review the repository first:

```bash
git status --short
git check-ignore .env data/hermes/.env
```

Initialize and publish with GitHub CLI:

```bash
git init
git add .
git commit -m "Initial public release"
gh repo create hermes-linux-stack --public --source=. --remote=origin --push
```

Or create an empty public repository on GitHub, then:

```bash
git init
git add .
git commit -m "Initial public release"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/hermes-linux-stack.git
git push -u origin main
```

Never force-add ignored secret or data files.

## Upstream documentation

- [9router Docker deployment](https://github.com/decolua/9router/blob/master/DOCKER.md)
- [Hermes Agent Docker guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md)
- [Hermes Telegram guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/telegram.md)
- [Open WebUI quick start](https://docs.openwebui.com/getting-started/quick-start/)
- [Open WebUI environment reference](https://docs.openwebui.com/reference/env-configuration/)

## License

MIT — see `LICENSE`.
