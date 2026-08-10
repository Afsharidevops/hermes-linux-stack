# Hermes Linux Stack — OmniRoute + Smart Router v0.5.0

A self-hosted Linux stack for running **Hermes Agent**, its **Telegram bot/agent**, **Open WebUI**, optional **n8n**, and supporting services behind **Hermes Smart Router v0.5.0** and **OmniRoute**.

> This branch is intentionally **OmniRoute-only**.
>
> Do not add 9router to this stack.

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
Open WebUI ─────────────────┼──► Hermes Smart Router v0.5.0
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
          Smart Router v0.5.0
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
          Smart Router v0.5.0
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
- Hermes Smart Router v0.5.0
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
Smart Router v0.5.0
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

# Smart Router v0.5.0

Published image:

```text
afsharidevops/hermes-smart-router:0.5.0
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
  "version": "0.5.0"
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

## Stack lifecycle

```bash
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh status
./manage.sh update
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
./manage.sh router-mode observe
./manage.sh router-mode route

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
| Smart Router | Docker network only |

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
afsharidevops/hermes-smart-router:0.5.0
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
afsharidevops/hermes-smart-router:0.5.0
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
    Smart Router: v0.5.0
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


<!-- smart-router-v0.4.0-release -->
## Previous release: Smart Router v0.4.0 benchmarking

Smart Router v0.4.0 adds RouteLLM-style cost/quality benchmarking with Pareto plots, fixed baselines, tier distribution, confusion matrix, confidence-risk analysis, machine-readable summaries, and CI release gates. Synthetic example figures are explicitly watermarked and are not performance claims. See [`docs/SMART-ROUTER-v0.4.0-BENCHMARKING.md`](docs/SMART-ROUTER-v0.4.0-BENCHMARKING.md).

Client tier forcing is disabled by default, approximate context counts receive a configurable 15% safety margin, and the unused `SMART_ROUTER_FAIL_OPEN_MODEL` knob has been removed. The shared Docker image is released canonically from `main` only after `smart-router/` is identical on `main` and `hermes-omniroute-linux-stack`.

The v0.4.0 benchmark artifacts are retained as historical, reproducible validation evidence. They are synthetic results and are not production-cost claims.


<!-- smart-router-v0.5.0-release -->
## Smart Router v0.5.0 — measured cost, preferences, and a built-in dashboard

Smart Router v0.5.0 adds a lightweight dashboard directly to the router at **`/dashboard`**. It records measured upstream token usage to a local SQLite ledger and, when real tier prices are configured, shows measured USD cost, a same-token strong-only counterfactual, savings percentage, usage/pricing coverage, tier mix, and output-budget-cap reduction. Missing usage is never silently converted into fake savings.

Configure real prices by copying `smart-router/policy/pricing-v0.5.example.json` to `pricing-v0.5.json`. See [`docs/HERMES-SMART-ROUTER-v0.5.0-PLAN.md`](docs/HERMES-SMART-ROUTER-v0.5.0-PLAN.md) and [`docs/SMART-ROUTER-v0.5.0-DASHBOARD.md`](docs/SMART-ROUTER-v0.5.0-DASHBOARD.md).

### Evidence figures

The following v0.4 benchmark figures remain **synthetic examples, not production performance claims**:

![Synthetic quality vs cost](docs/smart-router-v0.4.0/synthetic-benchmark/quality_vs_cost.png)

![Synthetic tier distribution](docs/smart-router-v0.4.0/synthetic-benchmark/tier_distribution.png)

The v0.5 target scorecard is a roadmap figure, not measured performance:

![v0.5 improvement targets](docs/smart-router-v0.5.0/figures/v050-improvement-scorecard.png)

![v0.5 dashboard measurement funnel](docs/smart-router-v0.5.0/figures/v050-dashboard-measurement-funnel.png)
