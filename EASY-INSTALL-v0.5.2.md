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
