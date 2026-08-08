# Hermes + OmniRoute + Open WebUI Linux Stack

Hermes Linux Stack powered by [OmniRoute](https://github.com/diegosouzapw/OmniRoute) as the OpenAI-compatible model routing gateway.

## Architecture

```text
Telegram API
    ↑ outbound polling
    │
Hermes Agent ───┐
       │        ├──→ optional Hermes Smart Router ──→ OmniRoute ──→ AI providers
       │        │
       │        └──→ optional n8n
Open WebUI ─────┘

Host defaults:
  OmniRoute dashboard  127.0.0.1:20128
  OmniRoute /v1 API    127.0.0.1:20129
  Open WebUI           127.0.0.1:3000
  Hermes API           127.0.0.1:8642
  Hermes dashboard     127.0.0.1:9119
  n8n                   127.0.0.1:5678
```

Containers use `http://omniroute:20129/v1`. Splitting the dashboard and API ports lets the stack keep the API private by default while still supporting an HTTPS dashboard/reverse proxy.

## Major migration changes

- Compose service: `omniroute`
- Image: `diegosouzapw/omniroute:latest`
- Persistence: `data/omniroute:/app/data`
- OmniRoute dashboard: `20128`
- OpenAI-compatible API: `20129`
- Hermes provider environment: `OMNIROUTE_API_KEY`
- Smart Router upstream: `http://omniroute:20129/v1`
- Fresh route/model default: `auto`
- All stack router secrets/settings use `OMNIROUTE_*`


## Install

Requirements: Linux, Bash 4+, Docker Engine, and the Docker Compose plugin.

```bash
chmod +x install.sh manage.sh
./install.sh
```

To generate configuration without starting containers:

```bash
./install.sh --no-start
```

The installer generates OmniRoute secrets (including a deployment-specific machine salt and WebSocket bridge secret), Hermes/Open WebUI routing configuration, safe loopback bindings, optional Smart Router/n8n/Caddy profiles, and required mount sources.

## First OmniRoute setup

1. Start the stack and open `http://localhost:20128` (or your configured domain).
2. Sign in with the initial password selected in the installer.
3. Add at least one provider in OmniRoute.
4. Verify the `auto` route or create the endpoint/combo/model names you want.
5. Test Hermes/Open WebUI.
6. Optionally create an OmniRoute endpoint API key and run:

```bash
./manage.sh enable-omniroute-api-auth
```

Fresh installs have `OMNIROUTE_REQUIRE_API_KEY=false` so first-boot configuration is possible. The API host binding is `127.0.0.1` by default. Enable endpoint-key enforcement before publishing the API beyond a protected host/network.

## Smart Router

The existing Hermes Smart Router remains optional. It speaks OpenAI-compatible HTTP, so the integration change is its upstream and defaults rather than a protocol rewrite.

```bash
SMART_ROUTER_UPSTREAM_BASE_URL=http://omniroute:20129/v1
SMART_ROUTER_OBSERVE_MODEL=auto
SMART_ROUTER_FAIL_OPEN_MODEL=auto
SMART_ROUTER_FAST_MODEL=auto
SMART_ROUTER_STANDARD_MODEL=auto
SMART_ROUTER_STRONG_MODEL=auto
```

After configuring concrete OmniRoute model/combo names, edit `.env` or use:

```bash
./manage.sh set-model <name>
```

## Management

```bash
./manage.sh status
./manage.sh logs omniroute
./manage.sh doctor
./manage.sh update
./manage.sh migration-status
./manage.sh backup
./manage.sh set-model auto
./manage.sh enable-omniroute-api-auth
```

Run `./manage.sh help` for all commands.

## Upgrading an existing repository checkout

This archive also includes a non-destructive overlay helper. If you have a complete upstream checkout and want to preserve all unchanged development/source files:

```bash
```


## Validation

```bash
./tests/smoke.sh
```

The smoke test checks shell syntax, migration invariants, required OmniRoute wiring, and (when Docker is available) `docker compose config`.

## Security

Read `SECURITY.md`. In particular, keep `.env`, `data/hermes/.env`, `data/omniroute`, n8n state, and execution secrets out of version control. Existing execution profiles remain disabled by default.

## License

MIT for this repository. Third-party images/components retain their own licenses.
