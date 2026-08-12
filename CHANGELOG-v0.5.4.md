# v0.5.4 change summary — OmniRoute

- Fixed the hidden 200,000 TPM ceiling on `SMART_ROUTER_CLIENT_API_KEY`; trusted stack-client RPM/TPM/daily limits are explicit (2,000,000 TPM default).
- Local quota 429 responses now identify Smart Router as the source, include current/limit/estimated values, and return `Retry-After`.
- Redis/HA quota checks are atomic: denied requests no longer consume additional quota.
- Virtual API-key RPM/TPM/daily limits can be edited in-place in `/control/` without rotating the key.
- Visible **Control Plane** naming is replaced by **Hermes Operations Center**; `/control/` and legacy `SMART_ROUTER_CONTROL_*` variables stay compatible.
- RAG knowledge tables can share the Operations DB or use a separate SQLite/PostgreSQL database through `SMART_ROUTER_KNOWLEDGE_DATABASE_URL`.
- The Operations Center shows RAG storage health/backend and labels the built-in retriever accurately as lexical.
- The persistent default filename remains `control-v0.5.2.sqlite3` so upgrades preserve state.
- Runtime/package/image/chart defaults are `0.5.4`.
