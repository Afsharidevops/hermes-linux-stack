# Hermes Linux Stack — OmniRoute Edition

Release: `v2.0.0-omniroute`
Date: 2026-08-08

This is the router-migration release: the stack now uses OmniRoute instead of 9router.

The important operational difference is that OmniRoute owns its own provider/endpoint configuration. The previous router-specific bootstrap routine that created API keys and combo names has intentionally been removed rather than translated against undocumented internals. A fresh deployment starts with OmniRoute's `auto` route, and operators add provider credentials in the OmniRoute dashboard.

Default exposure remains conservative: dashboard and API bind to loopback. The stack separates dashboard port `20128` and API port `20129`, allowing internal clients to use the OpenAI-compatible API without making it publicly reachable. Endpoint API-key enforcement can be enabled after an endpoint key exists. Fresh installs also generate a unique machine-ID salt and the production WebSocket bridge secret expected by current OmniRoute security guidance.

See `MIGRATION.md` before upgrading an existing installation.
