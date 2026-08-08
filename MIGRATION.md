# Migration: 9router → OmniRoute

This release changes the router layer of Hermes Linux Stack to OmniRoute while keeping the existing Hermes Agent, optional Smart Router, Open WebUI, n8n, Caddy, and execution-isolation Compose services.

## What changed

| Old stack | OmniRoute release |
|---|---|
| `nine-router` service | `omniroute` service |
| `decolua/9router:latest` | `diegosouzapw/omniroute:latest` |
| `data/9router` | `data/omniroute` |
| internal API `http://nine-router:20128/v1` | `http://omniroute:20129/v1` |
| single dashboard/API port | dashboard `20128`, API `20129` |
| `NINEROUTER_*` stack settings | `OMNIROUTE_*` settings |
| Hermes `NINEROUTER_API_KEY` | Hermes `OMNIROUTE_API_KEY` |
| legacy `ai`/`combo-*` defaults | OmniRoute `auto` default |

## Important: router databases are not format-compatible

Do **not** mount the old `data/9router` directory into OmniRoute. This release deliberately uses a new `data/omniroute` directory. Keep the old directory as a backup until you have verified the new routing setup.

Provider credentials, endpoint definitions, combinations, usage state, and generated endpoint keys from the old router are not automatically imported. Configure providers/endpoints in the OmniRoute dashboard after first boot.

## Recommended upgrade procedure

1. Back up the old installation (`.env`, `data/9router`, `data/hermes`, Open WebUI/n8n data, and execution secrets).
2. Stop the old stack.
3. Extract this release into a new directory, or replace only tracked project files while preserving your `data/` backups.
4. Run `./install.sh --no-start` and answer the prompts.
5. Start OmniRoute first if you want to configure it before the rest:
   `COMPOSE_PROFILES=omniroute docker compose --env-file .env up -d omniroute`
6. Open the OmniRoute dashboard, add provider credentials, and verify the `auto` route or create your preferred models/combos/endpoints.
7. Run `./manage.sh start`.
8. Test Hermes and Open WebUI.
9. Create an OmniRoute endpoint API key, then run `./manage.sh enable-omniroute-api-auth` if you want API-key enforcement.
10. Keep `data/9router` until you are satisfied with the migration; the new Compose file never mounts it.

## Smart Router

The optional Hermes Smart Router still speaks OpenAI-compatible HTTP, so its code does not need a router-specific protocol rewrite. Its upstream is now OmniRoute `http://omniroute:20129/v1`.

Fresh defaults use `auto` for all Smart Router tiers. After you create explicit OmniRoute model/combo names, set them in `.env` or run `./manage.sh set-model <name>` for a common default.

## Authentication model

Fresh installs use `OMNIROUTE_REQUIRE_API_KEY=false` because a brand-new OmniRoute instance has no operator-created endpoint key yet. Both OmniRoute host ports bind to `127.0.0.1` by default, while stack clients communicate over Docker's private bridge network.

When you create an OmniRoute endpoint key, `./manage.sh enable-omniroute-api-auth` updates Hermes and Open WebUI with that key and turns enforcement on. Do this before exposing the API bind address beyond a trusted host/network.
