# Easy installer compatibility layer for v0.5.2

This package restores the interactive v0.1-style installer and management flow while keeping the v0.5.2 Compose, Smart Router, execution-broker, and policy files.

Branch target: `hermes-omniroute-linux-stack`
Backend: OmniRoute

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


## n8n same-run provisioning

When n8n + Hermes MCP is selected, the normal installer now uses a two-phase flow. It starts n8n first because the owner account must exist before n8n can issue user-bound credentials. Once n8n is healthy, the same wizard offers to pause while you claim/confirm the owner account, then securely prompts for the owner API key. In Instance-level MCP mode it also guides you to **Settings -> Instance-level MCP -> Connection details -> Access Token**, validates the n8n-generated token, stores it without printing it, and reconciles/verifies the managed n8n integration. You can skip this phase and resume at any time with `./manage.sh n8n-menu`.

Instance MCP validation is capability-aware: it requires the stable workflow core (`search_workflows`, `get_workflow_details`, `execute_workflow`) but does not reject valid tokens merely because the installed n8n image lacks newer version-gated tools such as `search_executions` or `list_credentials`.

Current n8n releases add MCP tools incrementally (for example `search_executions` is version-gated), so the stack treats those extra tools as optional during token authentication and reports compatibility through verification instead of rejecting an otherwise valid token.
