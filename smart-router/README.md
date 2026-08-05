# Hermes Smart Router

A privacy-conscious OpenAI-compatible routing sidecar for Hermes Agent, Open WebUI, and 9router.

```text
Hermes Agent ───┐
                ├──→ Hermes Smart Router ──→ 9router ──→ AI providers
Open WebUI ─────┘
```

The router provides deterministic fast/standard/strong model-tier selection, session stickiness, request-aware output budgets, transparent streaming, and Prometheus metrics. It keeps the official 9router image unchanged.

## Image

```text
afsharidevops/hermes-smart-router:0.1.0
```

Supported platforms:

- `linux/amd64`
- `linux/arm64`

Version `0.1.0` includes an SBOM and build-provenance attestations.

For reproducible deployment, pin the manifest digest:

```text
afsharidevops/hermes-smart-router:0.1.0@sha256:4290667e8c90940a5dd97bcd6fd1575c0f1b822db507f9cc5076abe126708bef
```

## Features

- OpenAI-compatible `POST /v1/chat/completions`
- OpenAI-compatible `GET /v1/models`
- Virtual models: `auto`, `auto-fast`, `auto-standard`, `auto-strong`
- `observe` and `route` modes in one image
- Transparent SSE streaming without event reconstruction
- Explicit non-auto model passthrough
- Capability gates for tools, vision, and context size
- Deterministic complexity scoring without another LLM call
- SQLite-backed sticky session tiers
- HMAC-pseudonymous session identifiers
- Request-aware output-token budgets in route mode
- Prometheus metrics with no prompt or credential labels
- Separate `/health` and `/ready` endpoints
- Non-root runtime
- No answer cache, semantic cache, message compression, tool filtering, or automatic replay

## Observe mode

Start with observation mode:

```env
SMART_ROUTER_MODE=observe
SMART_ROUTER_OBSERVE_MODEL=ai
```

For virtual `auto*` requests, observe mode:

- calculates a proposed tier and output budget;
- sends the known-working `ai` model to 9router;
- does **not** enforce or alter output-token limits;
- records proposed and effective values separately.

Explicit non-auto model requests are forwarded unchanged.

Observation metrics are estimates and do not represent realized savings.

## Route mode

After configuring meaningful model lists for `combo-fast`, `combo-standard`, and `combo-strong` in 9router:

```env
SMART_ROUTER_MODE=route
```

Route mode maps virtual models to configured tier combos and can clamp output limits, but never increases a limit supplied by the client.

Explicit non-auto models continue to pass through unchanged.

## Docker Compose example

```yaml
services:
  smart-router:
    image: afsharidevops/hermes-smart-router:0.1.0
    restart: unless-stopped
    environment:
      SMART_ROUTER_MODE: observe
      SMART_ROUTER_UPSTREAM_BASE_URL: http://nine-router:20128/v1
      SMART_ROUTER_DATABASE_PATH: /data/router.sqlite3
      SMART_ROUTER_HMAC_SECRET: ${SMART_ROUTER_HMAC_SECRET}
      SMART_ROUTER_POLICY_VERSION: "1"
      SMART_ROUTER_OBSERVE_MODEL: ai
      SMART_ROUTER_FAIL_OPEN_MODEL: ai
      SMART_ROUTER_FAST_MODEL: combo-fast
      SMART_ROUTER_STANDARD_MODEL: combo-standard
      SMART_ROUTER_STRONG_MODEL: combo-strong
    volumes:
      - ./data/smart-router:/data
    read_only: true
    tmpfs:
      - /tmp:size=64m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

Generate the HMAC secret securely:

```bash
openssl rand -hex 32
```

Do not publish port `8080` on an untrusted network. Keep the router on the same private Docker network as its clients and 9router.

## Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /health` | Process liveness; does not depend on 9router |
| `GET /ready` | SQLite and upstream readiness |
| `GET /metrics` | Prometheus-format operational metrics |
| `GET /v1/models` | Upstream model list plus virtual auto aliases |
| `POST /v1/chat/completions` | OpenAI-compatible JSON and SSE proxy |

## Main configuration

| Variable | Default | Description |
|---|---|---|
| `SMART_ROUTER_MODE` | `observe` | `observe` or `route` |
| `SMART_ROUTER_UPSTREAM_BASE_URL` | `http://nine-router:20128/v1` | 9router OpenAI-compatible URL |
| `SMART_ROUTER_DATABASE_PATH` | `/data/router.sqlite3` | Sticky-route SQLite database |
| `SMART_ROUTER_HMAC_SECRET` | required | At least 32 characters; protects session identifiers |
| `SMART_ROUTER_POLICY_VERSION` | `1` | Changing it invalidates old sticky decisions |
| `SMART_ROUTER_OBSERVE_MODEL` | `ai` | Effective model in observe mode |
| `SMART_ROUTER_FAIL_OPEN_MODEL` | `ai` | Fallback when an auto routing decision fails |
| `SMART_ROUTER_FAST_MODEL` | `combo-fast` | Fast-tier 9router combo |
| `SMART_ROUTER_STANDARD_MODEL` | `combo-standard` | Standard-tier 9router combo |
| `SMART_ROUTER_STRONG_MODEL` | `combo-strong` | Strong-tier 9router combo |
| `SMART_ROUTER_SESSION_TTL_SECONDS` | `2700` | Sliding inactivity TTL |
| `SMART_ROUTER_MAX_SESSION_AGE_SECONDS` | `43200` | Hard session age limit |
| `SMART_ROUTER_DEMOTION_TURNS` | `5` | Consecutive simpler turns before demotion |
| `SMART_ROUTER_FAST_MAX_TOKENS` | `1024` | Fast-tier output ceiling in route mode |
| `SMART_ROUTER_STANDARD_MAX_TOKENS` | `4096` | Standard-tier output ceiling in route mode |
| `SMART_ROUTER_STRONG_MAX_TOKENS` | `6144` | Strong-tier output ceiling in route mode |
| `SMART_ROUTER_MAX_REQUEST_BYTES` | `10485760` | Maximum request-body size |
| `SMART_ROUTER_CONNECT_TIMEOUT_SECONDS` | `10` | Upstream connection timeout |
| `SMART_ROUTER_READ_TIMEOUT_SECONDS` | `600` | Upstream response/read timeout |

## Request behavior

### Explicit models

Any model other than an `auto*` alias is passed through without model routing or tier budgets. This includes 9router combos and explicit provider/model identifiers.

### Auto aliases

- `auto`: deterministic selection with sticky session behavior
- `auto-fast`: request fast tier, capability-upgraded when required
- `auto-standard`: request standard tier, capability-upgraded when required
- `auto-strong`: request strong tier

Optional control headers:

```text
X-Router-Session: stable-pseudonymous-session-value
X-Router-Tier: fast|standard|strong
X-Router-Reset: true
```

Do not put secrets or raw personal identifiers in session headers.

## Metrics and measurement

The router reports facts it directly knows:

- proposed tiers and proposed output budgets;
- effective output limits;
- budget-enforcement counts;
- actual upstream input, cached-input, and output tokens when reported;
- missing upstream usage counts;
- request status and latency;
- sticky-route outcomes;
- upstream errors and readiness.

The router does not claim tokens avoided, realized savings, retry causality, or cost-per-task conclusions. Compare baseline, observation, and routing periods externally using workload-normalized metrics.

## Privacy and security

The router does not intentionally store or log:

- prompts or responses;
- raw API keys;
- raw Telegram/user/session identifiers;
- tool arguments;
- SSE event content.

SQLite stores only HMAC-pseudonymous sticky-route metadata. Rotating `SMART_ROUTER_HMAC_SECRET` invalidates previous sticky identities.

Authentication is forwarded unchanged to 9router. The router does not maintain a second API-key database.

The router sends each request upstream once. It does not automatically replay failed agent requests. 9router may independently apply its configured provider/combo fallback behavior.

## Source and license

Source, installer integration, tests, and deployment documentation:

https://github.com/Afsharidevops/hermes-linux-stack/tree/main/smart-router

License: MIT, as distributed with the parent repository.
