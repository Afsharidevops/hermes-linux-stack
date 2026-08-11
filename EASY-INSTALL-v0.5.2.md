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

## Manager uninstall and clearer router choices

The Smart Router setup now displays both valid modes before asking: `observe` (analyze/log decisions without actively switching tiers) and `route` (actively route automatic requests).

`./manage.sh menu` now includes **Uninstall stack**. The default uninstall removes containers/network while preserving local configuration and data. `./manage.sh uninstall --purge` additionally deletes local stack configuration, runtime data, and secrets after requiring the exact confirmation word `PURGE`; source files and external backups are preserved.
