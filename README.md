# Hermes Linux Stack — OmniRoute + Smart Router v0.5.9

> **v0.5.9 UX release:** this package includes the interactive v0.1-style install/management flow while keeping the v0.5.9 Smart Router and OmniRoute architecture. Run `./install.sh`, use `./install.sh --dry-run` to preview, `./install.sh --no-start` to configure without starting containers, and `./manage.sh menu` for interactive management. n8n MCP provisioning/verification and token-management commands are available through `./manage.sh help`.

A self-hosted Linux stack for running **Hermes Agent**, its **Telegram bot/agent**, **Open WebUI**, optional **n8n**, and supporting services behind **Hermes Smart Router v0.5.9** and **OmniRoute**.

> This branch is intentionally **OmniRoute-only**.
>
> Do not add 9router to this stack.

## Project documentation

- [Canonical changelog](CHANGELOG.md)
- [Operations Center user guide](docs/HERMES-OPERATIONS-CENTER-USER-GUIDE-v0.5.9.md)
- [Release process](docs/RELEASE-PROCESS.md)
- [Smart Router client API](docs/SMART-ROUTER-CLIENT-API.md)
- [Smart Router Docker Hub notes](docs/publishing/SMART-ROUTER-DOCKERHUB.md)
- [Execution Broker Docker Hub notes](docs/publishing/EXECUTION-BROKER-DOCKERHUB.md)

## Architecture

```text
Telegram API
     ↑
     │ outbound polling
     │
Hermes Telegram Agent
     │
     ▼
Hermes Agent ───────────────┐
                            │
Open WebUI ─────────────────┼──► Hermes Smart Router v0.5.9
                            │              │
n8n / other clients ────────┘              │
                                           ▼
                                        OmniRoute
                                           │
                                           ▼
                                  Providers / Models
```

Telegram is provided through the Hermes gateway rather than through a separate Telegram Docker container.

Hermes polls the Telegram Bot API and serves authorized Telegram users through the same Smart Router → OmniRoute path used by other automatic-model clients.

---

# Branch Policy

The two router backends in this repository are intentionally isolated.

## `main`

```text
Hermes / Telegram / Open WebUI / n8n
                  │
                  ▼
          Smart Router v0.5.9
                  │
                  ▼
               9router
                  │
                  ▼
              Providers
```

## `hermes-omniroute-linux-stack`

```text
Hermes / Telegram / Open WebUI / n8n
                  │
                  ▼
          Smart Router v0.5.9
                  │
                  ▼
              OmniRoute
                  │
                  ▼
              Providers
```

Do not combine 9router and OmniRoute in one Compose stack.

---

# Features

- Hermes Agent
- Telegram bot/agent through Hermes
- Numeric Telegram allowlist
- Hermes Smart Router v0.5.9
- OmniRoute dashboard and OpenAI-compatible API
- Open WebUI
- Optional n8n
- Optional Caddy
- Optional secure execution infrastructure
- Smart Router heuristic and calibrated policy support
- Offline Smart Router calibration/report/replay tools
- Sticky sessions
- Capability gates
- Per-tier output budgets
- Privacy-safe routing observations
- Published multi-architecture Smart Router image
- Persistent runtime state under `data/`

---

# Requirements

- Linux
- Bash
- Docker Engine
- Docker Compose plugin
- Git
- Telegram BotFather token if Telegram is enabled
- At least one provider configured in OmniRoute

Verify Docker:

```bash
docker version
docker compose version
```

---

# Installation

Clone the repository:

```bash
git clone https://github.com/Afsharidevops/hermes-linux-stack.git
cd hermes-linux-stack
git switch hermes-omniroute-linux-stack
```

Make scripts executable:

```bash
chmod +x install.sh manage.sh
```

Run:

```bash
./install.sh
```

To prepare configuration without starting containers:

```bash
./install.sh --no-start
```

The installer:

- copies `.env.example` to `.env` if necessary
- generates replacement values for secret placeholders
- creates runtime directories
- prepares Hermes configuration
- creates `data/hermes/.env`
- prepares Smart Router data
- prepares Caddy configuration
- validates Compose
- starts the selected Compose profiles unless `--no-start` is used

Default profiles include:

```text
omniroute
smart-router
hermes
open-webui
```

---

# Telegram Agent

Telegram is supported through Hermes.

The request path is:

```text
Telegram user
     │
     ▼
Telegram Bot API
     │
     ▼
Hermes Agent
     │
     ▼
Smart Router v0.5.9
     │
     ▼
OmniRoute
     │
     ▼
Provider / Model
```

## Configure Telegram

The OmniRoute branch installer creates:

```text
data/hermes/.env
```

with Telegram fields ready for configuration.

Edit it:

```bash
nano data/hermes/.env
```

Configure:

```env
TELEGRAM_BOT_TOKEN=YOUR_BOTFATHER_TOKEN
TELEGRAM_ALLOWED_USERS=123456789
```

For multiple users:

```env
TELEGRAM_ALLOWED_USERS=123456789,987654321
```

Use numeric Telegram user IDs, not usernames.

Do not commit this file.

Set restrictive permissions if needed:

```bash
chmod 600 data/hermes/.env
```

Restart Hermes/the stack after changing Telegram configuration:

```bash
./manage.sh restart
```

or:

```bash
docker compose --env-file .env restart hermes
```

## Test Telegram

Open your BotFather-created bot and send:

```text
/start
```

Check Hermes logs if necessary:

```bash
./manage.sh logs hermes
```

## Telegram security

Only IDs listed in:

```env
TELEGRAM_ALLOWED_USERS=
```

should be treated as authorized Telegram users.

Keep this allowlist narrow.

Unlike the larger management script on `main`, this branch's current `manage.sh` does not provide `add-telegram-user`, `set-telegram-users`, or `show-telegram-users` commands.

Edit `data/hermes/.env` directly when changing Telegram access, then restart Hermes.

---

# OmniRoute

OmniRoute is the provider/model delivery layer for this branch.

## Default ports

Dashboard:

```text
http://127.0.0.1:20128
```

OpenAI-compatible API:

```text
http://127.0.0.1:20129/v1
```

Internal Docker URL:

```text
http://omniroute:20129/v1
```

Smart Router must use:

```env
SMART_ROUTER_UPSTREAM_BASE_URL=http://omniroute:20129/v1
```

The dashboard and API ports are intentionally separate.

---

# First OmniRoute Setup

After starting the stack:

1. open:

```text
http://127.0.0.1:20128
```

2. sign in using the initial password generated/stored for the deployment
3. change the administrator password if appropriate
4. add at least one provider
5. verify OmniRoute exposes working models/routes
6. test `/v1/models`
7. verify Smart Router connectivity

Test the API:

```bash
curl -s http://127.0.0.1:20129/v1/models
```

---

# Smart Router v0.5.9

Published image:

```text
afsharidevops/hermes-smart-router:latest
```

Smart Router answers:

> What capability tier does this request need?

OmniRoute answers:

> Which provider/model should actually serve the selected target?

There is no additional LLM call in the routing decision path.

## OpenAI-compatible aliases

Smart Router exposes:

```text
auto
auto-fast
auto-standard
auto-strong
```

These are visible through:

```text
GET /v1/models
```

## Default OmniRoute targets

Current defaults:

```env
SMART_ROUTER_OBSERVE_MODEL=auto

SMART_ROUTER_FAST_MODEL=auto
SMART_ROUTER_STANDARD_MODEL=auto
SMART_ROUTER_STRONG_MODEL=auto
```

This is a safe initial configuration.

Smart Router still evaluates capability tier, sticky-session state, and budgets, while OmniRoute resolves the final automatic route.

If you later want distinct OmniRoute behavior for each tier, replace the three target variables with route/model IDs that actually exist in your OmniRoute instance.

For example, your installation may expose routes such as:

```text
auto/best-fast
auto/best-chat
auto/best-reasoning
auto/best-coding
auto/best-vision
```

Do not assume route names: inspect your own `/v1/models` response first.

---

# Routing Modes

## Observe

```env
SMART_ROUTER_MODE=observe
```

Recommended starting state.

Switch with:

```bash
./manage.sh router-mode observe
```

## Route

```env
SMART_ROUTER_MODE=route
```

Enable active tier rewriting with:

```bash
./manage.sh router-mode route
```

---

# Routing Policies

## Heuristic

Default:

```env
SMART_ROUTER_POLICY=heuristic
```

Set with:

```bash
./manage.sh router-policy heuristic
```

## Calibrated

```env
SMART_ROUTER_POLICY=calibrated
```

Set with:

```bash
./manage.sh router-policy calibrated
```

A calibrated policy file must exist before enabling the calibrated policy.

The bundled calibration file should be treated as a bootstrap/example policy, not as proof that it has been trained for your workload.

---

# Capability Gates

Default capabilities:

| Tier | Tools | Vision | Context |
|---|---:|---:|---:|
| Fast | No | No | 32k |
| Standard | Yes | No | 128k |
| Strong | Yes | Yes | 200k |

Capability requirements override normal routing preference.

For example, a vision request cannot use a tier configured without vision support.

---

# Sticky Sessions

Defaults:

```env
SMART_ROUTER_SESSION_TTL_SECONDS=2700
SMART_ROUTER_MAX_SESSION_AGE_SECONDS=43200
SMART_ROUTER_DEMOTION_TURNS=5
```

These settings reduce unnecessary tier changes across a multi-turn conversation.

---

# Output Budgets

```env
SMART_ROUTER_FAST_MAX_TOKENS=1024
SMART_ROUTER_STANDARD_MAX_TOKENS=4096
SMART_ROUTER_STRONG_MAX_TOKENS=6144
```

Automatic requests can be clamped to the selected tier's budget when active routing is enabled.

---

# Offline Calibration and Evaluation

Smart Router v0.5.0 includes offline tools.

## Calibrate

```bash
./manage.sh router-calibrate LABELED.jsonl
```

## Report

```bash
./manage.sh router-report LABELED.jsonl
```

## Replay

```bash
./manage.sh router-replay REQUESTS.jsonl
```

Optional output path:

```bash
./manage.sh router-replay REQUESTS.jsonl OUTPUT.jsonl
```

These tools let you evaluate routing without adding another model request to production traffic.

---

# Smart Router Information

Inspect current router policy/state:

```bash
./manage.sh router-info
```

Health:

```bash
docker exec hermes-smart-router \
  python -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8080/health").read().decode())'
```

Expected version:

```json
{
  "status": "ok",
  "version": "0.5.9"
}
```

---

# Verify Smart Router → OmniRoute

Run:

```bash
docker exec hermes-smart-router \
  python -c 'import urllib.request; r=urllib.request.urlopen("http://omniroute:20129/v1/models", timeout=10); print("HTTP:", r.status); print(r.read(3000).decode())'
```

Expected:

```text
HTTP: 200
```

Then inspect Smart Router's own models endpoint:

```bash
docker exec hermes-smart-router \
  python -c 'import urllib.request; r=urllib.request.urlopen("http://127.0.0.1:8080/v1/models", timeout=10); print(r.read(3000).decode())'
```

It should include:

```text
auto
auto-fast
auto-standard
auto-strong
```

plus upstream OmniRoute models/routes.

---

# Open WebUI

Default host URL:

```text
http://127.0.0.1:3000
```

Open WebUI should connect internally to Smart Router:

```env
OPENWEBUI_OPENAI_BASE_URL=http://smart-router:8080/v1
```

This allows Open WebUI users to select:

```text
auto
auto-fast
auto-standard
auto-strong
```

alongside upstream models exposed by OmniRoute.

---

# n8n

n8n is optional.

Default:

```text
http://127.0.0.1:5678
```

Its runtime state is stored under:

```text
data/n8n/
```

The OmniRoute branch's lightweight management script does not expose the larger n8n management command set available on `main`.

Configure additional n8n integration deliberately rather than assuming `main` management commands are present here.

---

# Management

The current OmniRoute branch supports these `manage.sh` commands.

Interactive menu:

```bash
./manage.sh menu
```

## Stack lifecycle

```bash
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh status
./manage.sh update
```

Safe uninstall (keeps local configuration/data):

```bash
./manage.sh uninstall
```

Destructive local-data purge (keeps source files and external backups):

```bash
./manage.sh uninstall --purge
```

## Logs

All services:

```bash
./manage.sh logs
```

Specific services:

```bash
./manage.sh logs omniroute
./manage.sh logs smart-router
./manage.sh logs hermes
./manage.sh logs webui
./manage.sh logs n8n
./manage.sh logs caddy
```

`gateway` is accepted as an OmniRoute log alias.

## Diagnostics

```bash
./manage.sh doctor
```

## Smart Router

```bash
./manage.sh set-router-mode observe
./manage.sh set-router-mode route

./manage.sh router-policy heuristic
./manage.sh router-policy calibrated

./manage.sh router-info
./manage.sh router-calibrate LABELED.jsonl
./manage.sh router-report LABELED.jsonl
./manage.sh router-replay REQUESTS.jsonl
```

Do not document or rely on management commands that are not implemented in this branch.

In particular, the current script does not provide:

```text
backup
migration-status
set-model
enable-omniroute-api-auth
add-telegram-user
set-telegram-users
show-telegram-users
```

Configure those concerns through the appropriate `.env`, runtime file, dashboard, or explicit Docker Compose operations until dedicated management commands are implemented.

---

# Changing Smart Router Tier Targets

Edit `.env`:

```env
SMART_ROUTER_FAST_MODEL=auto
SMART_ROUTER_STANDARD_MODEL=auto
SMART_ROUTER_STRONG_MODEL=auto
```

Replace values only with valid OmniRoute model/route IDs.

Then recreate Smart Router:

```bash
docker compose \
  --env-file .env \
  up -d --no-deps --force-recreate smart-router
```

Verify afterward:

```bash
./manage.sh router-info
```

---

# OmniRoute API Authentication

Fresh configuration defaults to:

```env
OMNIROUTE_REQUIRE_API_KEY=false
```

The API binds to localhost by default.

Do not expose an unauthenticated OmniRoute API to an untrusted network.

If API-key enforcement is enabled, ensure every client path is configured consistently, including Smart Router → OmniRoute.

The current `manage.sh` does not provide an `enable-omniroute-api-auth` helper, so authentication changes should be treated as an explicit configuration operation and tested before public exposure.

---


## v0.5.9 Execution & Approvals UI

Hermes Operations Center now includes **System → Execution & Approvals**. It connects directly from the operator browser to the optional `execution-admin` service with a separate admin key. The Smart Router backend does not receive that key or the dedicated Telegram approval bot token.

Bootstrap the separate admin boundary:

```bash
./manage.sh enable-execution-admin
./manage.sh execution-admin-status
./manage.sh show-execution-admin-key
```

The UI can then manage:

- live Sandbox/Docker/SSH feature policy for already-deployed brokers;
- numeric Telegram execution approvers, restricted to `TELEGRAM_ALLOWED_USERS`;
- write-only replacement of the dedicated approval-bot token;
- broker control-secret rotation;
- broker/approver health and execution-admin audit events;
- redacted SSH profile metadata.

The `execution-admin` service does **not** mount the Ed25519 approval signing key, Docker socket, or SSH private credentials. First-time Docker/SSH broker deployment and SSH credential creation/removal remain host `manage.sh` operations. Port `8752` binds to loopback by default. For remote administration, use a trusted private bind address, TLS/reverse proxy where appropriate, and exact `EXECUTION_ADMIN_ALLOWED_ORIGINS`; never use wildcard CORS or expose the admin port publicly.


# Service Ports

Typical defaults:

| Service | Address |
|---|---|
| OmniRoute dashboard | `127.0.0.1:20128` |
| OmniRoute API | `127.0.0.1:20129` |
| Open WebUI | `127.0.0.1:3000` |
| Hermes API | `127.0.0.1:8642` |
| Hermes dashboard | `127.0.0.1:9119` |
| n8n | `127.0.0.1:5678` |
| Smart Router | Docker network + loopback host binding by default |

Telegram uses outbound polling and does not need an inbound Telegram port.

---

# Data and Secrets

Important runtime locations:

```text
.env
data/omniroute/
data/hermes/
data/hermes/.env
data/open-webui/
data/n8n/
data/smart-router/
data/stack-secrets/
```

Never commit:

```text
.env
data/hermes/.env
data/omniroute/
data/smart-router/
data/stack-secrets/
```

Treat all generated databases and credentials as private runtime data.

---

# Smart Router Runtime Security

The Smart Router image runs as a non-root user.

The stack uses:

- UID `10001`
- read-only container filesystem
- dropped capabilities
- `no-new-privileges`
- writable `/data`
- read-only `/policy`
- temporary `/tmp`

`smart-router-init` prepares the bind-mounted runtime directory before Smart Router starts.

This init step remains useful even though the Docker image contains `/data`, because a host bind mount replaces the image directory at runtime.

---

# Development and Tests

Install Smart Router development dependencies:

```bash
python -m pip install -e "./smart-router[dev]"
```

Run:

```bash
pytest -q smart-router/tests
```

The v0.4.0 suite covers:

- explicit request passthrough
- automatic routing
- budget clamping
- model aliases
- SSE byte preservation
- policy behavior

---

# Validation

Validate Compose:

```bash
docker compose \
  --env-file .env \
  config
```

Check images:

```bash
docker compose \
  --env-file .env \
  config --images
```

Smart Router should resolve to:

```text
afsharidevops/hermes-smart-router:latest
```

Check services:

```bash
./manage.sh status
```

Run diagnostics:

```bash
./manage.sh doctor
```

---

# Troubleshooting

## Telegram bot does not respond

Check:

```bash
./manage.sh logs hermes
```

Then verify `data/hermes/.env` contains:

```env
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=...
```

Check outbound DNS and HTTPS access to Telegram.

Do not run two Hermes gateways with the same bot token.

## Smart Router cannot reach OmniRoute

The internal URL must be:

```text
http://omniroute:20129/v1
```

Do not use `localhost:20129` from inside Smart Router.

## Smart Router is unhealthy

```bash
docker logs --tail=200 hermes-smart-router
```

## OmniRoute is unhealthy

```bash
./manage.sh logs omniroute
```

Check the dashboard:

```bash
curl -fsS http://127.0.0.1:20128 >/dev/null \
  && echo "OmniRoute dashboard OK"
```

## Open WebUI has no models

Verify:

1. OmniRoute is healthy.
2. Smart Router is healthy.
3. Smart Router can read OmniRoute `/v1/models`.
4. Open WebUI uses `http://smart-router:8080/v1`.

## Smart Router data permission errors

Inspect:

```bash
ls -ld data/smart-router
```

The runtime directory is intentionally owned/prepared for Smart Router UID `10001`.

---

# Published Smart Router Image

```text
afsharidevops/hermes-smart-router:latest
```

Platforms:

```text
linux/amd64
linux/arm64
```

OCI index digest:

```text
```

---

# Repository Layout

```text
.
├── .env.example
├── docker-compose.yml
├── install.sh
├── manage.sh
├── README.md
├── SECURITY.md
├── smart-router/
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── README.md
│   ├── policy/
│   ├── src/
│   └── tests/
└── data/
    ├── omniroute/
    ├── hermes/
    ├── open-webui/
    ├── n8n/
    └── smart-router/
```

Runtime data under `data/` should not be committed unless a specific placeholder/template is intentionally tracked.

---

# Recommended Initial State

Start conservatively with:

```env
SMART_ROUTER_MODE=observe
SMART_ROUTER_POLICY=heuristic

SMART_ROUTER_FAST_MODEL=auto
SMART_ROUTER_STANDARD_MODEL=auto
SMART_ROUTER_STRONG_MODEL=auto
```

Recommended rollout:

1. configure OmniRoute providers
2. configure Telegram if used
3. verify Hermes → Smart Router
4. verify Smart Router → OmniRoute
5. verify Open WebUI
6. collect representative routing observations
7. evaluate the heuristic policy
8. optionally build/test a calibrated policy
9. move to `route` mode
10. optionally assign distinct OmniRoute routes to each tier

---

# Design Principles

1. Telegram is a first-class Hermes interface.
2. Smart Router decides capability tier.
3. OmniRoute handles provider/model delivery.
4. No additional routing-model request is required.
5. Capability gates remain authoritative.
6. Explicit models remain explicit.
7. Calibration happens offline.
8. Runtime observations avoid raw prompt logging.
9. Secrets and state remain outside Git.
10. OmniRoute and 9router stay in separate branches.
11. Documentation must only advertise commands actually implemented by the branch.

---

# Current Branch State

```text
Branch: hermes-omniroute-linux-stack
    Smart Router: v0.5.1
Backend: OmniRoute
Smart Router upstream: http://omniroute:20129/v1

Fast:     auto
Standard: auto
Strong:   auto

Recommended initial router mode: observe
Recommended initial policy: heuristic
```



## Smart Router v0.5.0 release hardening

The v0.5.0 release keeps the learned classifier as a proposal layer and preserves deterministic capability, sticky-session, budget, explicit-model, streaming, privacy, and fail-open rules. The safe default remains `SMART_ROUTER_MODE=observe` with `SMART_ROUTER_POLICY=heuristic`.

Branch backend: **OmniRoute**

```env
SMART_ROUTER_UPSTREAM_BASE_URL=http://omniroute:20129/v1
SMART_ROUTER_UPSTREAM_HEALTH_URL=http://omniroute:20128/api/monitoring/health
SMART_ROUTER_FAST_MODEL=auto
SMART_ROUTER_STANDARD_MODEL=auto
SMART_ROUTER_STRONG_MODEL=auto
```

The shared v0.5.0 image is `afsharidevops/hermes-smart-router:0.5.0`. `SMART_ROUTER_HMAC_SECRET` is mandatory; generate a persistent secret with `openssl rand -hex 32` and keep the real value outside Git. Use `SMART_ROUTER_*_MAX_CONTEXT` for context limits.

For external OpenAI-compatible applications, see `docs/SMART-ROUTER-CLIENT-API.md`. For standalone TLS or an external Caddy/Nginx/Traefik/other reverse proxy, see `docs/SMART-ROUTER-PUBLIC-INGRESS.md`.

Learned rollout remains: heuristic+observe → collect safe features → train/evaluate → learned+observe → validate → learned+route. Do not publish cost/quality claims until measured on a representative workload.

## License

See `LICENSE`.

Third-party images and upstream projects retain their respective licenses.


## Smart Router v0.5.9 Flight Deck and Operations Center

Smart Router v0.5.9 keeps the built-in measured telemetry dashboard at `/dashboard` and the authenticated Operations Center at `/control/`, while preserving OmniRoute as this branch's upstream gateway. The Operations Center covers RBAC/users, virtual API keys and quotas, route profiles (fast/standard/strong/coding/vision), provider discovery and provider-health/circuit state, budgets, policies, knowledge/memory, agents/teams, plugins, ACLs, audit events, outcomes, and system state. OIDC and Redis-backed HA are optional advanced settings.

The easy installer now configures the v0.5.9 core switches instead of silently relying on Compose defaults, and `./manage.sh menu` exposes a Smart Router submenu. Useful commands include `router-status`, `router-access`, `router-summary`, `router-routes`, `router-provider-health`, `router-system`, `router-info`, `router-policy`, `router-calibrate`, `router-report`, and `router-replay`.

Routing semantics are important: Smart Router policy applies to `model=auto`; `auto-fast`/`auto-standard`/`auto-strong` are available only when tier overrides are enabled. Explicit upstream model names pass through without automatic tier selection. `observe` evaluates/logs automatic requests but dispatches them through `SMART_ROUTER_OBSERVE_MODEL`; `route` applies the selected route profile.

Default local URLs are `http://127.0.0.1:8787/v1`, `http://127.0.0.1:8787/dashboard`, and `http://127.0.0.1:8787/control/`. See `docs/HERMES-OPERATIONS-CENTER-USER-GUIDE-v0.5.9.md`, `docs/RELEASE-PROCESS.md`, and `smart-router/V0.5.9-RELEASE-NOTES.md` for current authentication, OIDC, HA, and release guidance.

Default Smart Router image: `afsharidevops/hermes-smart-router:latest`; pin `SMART_ROUTER_IMAGE_TAG` in `.env` when you want a stable release.


## Image tag policy (v0.5.9)

Application images intentionally default to mutable tags so normal `docker compose pull` tracks upstream releases. You can pin any service later by changing only `.env`; Compose does not need to be edited.

```env
OMNIROUTE_IMAGE_TAG=latest
HERMES_IMAGE_TAG=latest
SMART_ROUTER_IMAGE_TAG=latest
OPENWEBUI_IMAGE_TAG=main
N8N_IMAGE_TAG=latest
```

For example, replace one or more tag values with a version you have tested, then run:

```bash
docker compose --env-file .env pull
docker compose --env-file .env up -d
./manage.sh doctor
```

For a reproducible snapshot of currently resolved image digests, use `./manage.sh lock-images` and `./manage.sh verify-images`.


### n8n guided provisioning

For n8n + Hermes MCP installations, `./install.sh` starts n8n first and then offers to finish owner/API/MCP provisioning in the same wizard session. The owner API key and Instance MCP access token remain user-created n8n credentials; the installer validates and stores them through hidden prompts after owner setup. Use `./manage.sh n8n-menu` later to inspect status, replace credentials, change MCP mode, reconcile, verify, or rotate the Trigger token. Instance MCP validation follows the stable core tool surface instead of requiring every newer version-gated n8n MCP tool.

Instance-level MCP capabilities are n8n-version-dependent; the stack validates the stable workflow core and does not require newer optional tools such as `search_executions` just to accept a valid access token.

## RAG database storage (v0.5.9)

The visible admin UI is **Hermes Operations Center** at `/control/` (the URL and `SMART_ROUTER_CONTROL_*` names stay compatible). Knowledge storage is configured server-side so database passwords are not saved in browser state.

Use the same Operations database for RAG knowledge tables:

```env
SMART_ROUTER_CONTROL_DATABASE_URL=postgresql+psycopg://hermes_router:SECRET@postgres:5432/hermes_router
SMART_ROUTER_KNOWLEDGE_DATABASE_URL=
```

Or put knowledge bases/chunks in a separate PostgreSQL database:

```env
SMART_ROUTER_KNOWLEDGE_DATABASE_URL=postgresql+psycopg://hermes_rag:SECRET@rag-postgres:5432/hermes_knowledge
```

After changing the DSN, recreate only Smart Router and inspect **Operations Center → Knowledge** or `./manage.sh router-system`. The UI reports storage mode, connectivity and a redacted DSN. v0.5.9 retains hybrid lexical/vector retrieval, reranking, and PostgreSQL pgvector support from v0.5.6. Configure a real embeddings endpoint for production semantic retrieval.
