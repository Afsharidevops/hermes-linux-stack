# Easy installer compatibility layer for v0.5.2

This package restores the interactive v0.1-style installer and management flow while keeping the v0.5.2 Compose, Smart Router, execution-broker, and policy files.

Branch target: `main`
Backend: 9router

## Install

```bash
chmod +x install.sh manage.sh scripts/*.sh 2>/dev/null || true
./install.sh
```

The wizard can select/reconfigure Hermes, Smart Router, Open WebUI, n8n, n8n MCP (Instance or Trigger), Caddy, Telegram, API/dashboard bindings, and preserves v0.5.2-only `.env` settings.

Use `./manage.sh help` for n8n provisioning, MCP token rotation, Telegram, execution, Smart Router policy/evaluation, backup/update, and diagnostics commands.

## Smart Router v0.5.2 installer/manager integration

The easy installer is synchronized with the Smart Router v0.5.2 runtime surface. It configures the router bind/port, `observe` or `route` mode, `heuristic`/`calibrated`/`learned` policy, optional tier-override aliases, built-in telemetry dashboard, Control Plane authentication, provider-health/circuit-breaker support, and fast/standard/strong/coding/vision route-profile defaults.

Smart routing is applied to `model=auto`. The aliases `auto-fast`, `auto-standard`, and `auto-strong` are advertised only when `SMART_ROUTER_ALLOW_TIER_OVERRIDES=true`. Explicit upstream model names pass through without automatic tier selection. In `observe` mode, automatic requests are evaluated/logged but dispatched through `SMART_ROUTER_OBSERVE_MODEL`; in `route` mode the selected route profile is applied.

The built-in Smart Router surfaces share one listener (default `127.0.0.1:8787`): `/v1` for the OpenAI-compatible API, `/dashboard` for measured routing/cost telemetry, and `/control/` for the v0.5.2 Control Plane. `./manage.sh menu` has a dedicated **Smart Router v0.5.2 management** submenu for status, access information, telemetry summary, route profiles, provider health, system state, mode, and policy. Run `./manage.sh router-access --show-secrets` only when you intentionally need to reveal local dashboard/control credentials.

HA/Redis and OIDC remain advanced infrastructure settings in `.env`; the installer preserves them instead of resetting them. The Control Plane itself manages users/API keys, budgets, policies, knowledge/memory, agents/teams, plugins, ACLs, audit events, outcomes, and dynamic route profiles.

## Uninstall

`./manage.sh menu` includes **Uninstall stack**. The default uninstall removes containers/network while preserving local configuration and data. `./manage.sh uninstall --purge` additionally deletes local stack configuration, runtime data, and secrets after requiring the exact confirmation word `PURGE`; source files and external backups are preserved.
