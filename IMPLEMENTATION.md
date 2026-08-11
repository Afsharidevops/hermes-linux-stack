# Smart Router v0.5.2 implementation notes

This branch uses the shared Smart Router v0.5.2 implementation in front of **9router**.

## Data plane

`Hermes / Open WebUI / n8n -> Smart Router v0.5.2 -> 9router -> provider/model`

Smart Router owns deterministic capability floors, tier/profile selection, authentication/authorization, shared routing state, provider-health/circuit logic, budgets, outcome metadata, and control-plane policy. **9router** remains the delivery gateway and performs its provider/model delivery behavior.

## v0.5.2 rollout

1. Run `./install.sh --no-start` and review `.env`.
2. Keep `SMART_ROUTER_MODE=observe` while validating your gateway/model mappings.
3. Run `./manage.sh doctor`.
4. Start with `docker compose --env-file .env up -d` (or your normal profiles).
5. Validate `/health`, `/ready`, `/router/info`, Open WebUI/Hermes access, and provider health.
6. For HA, configure PostgreSQL + Redis and use the v0.5.2 HA reference Compose file; Redis sticky state is selected automatically when configured.
7. Move to route/enforcement modes only after your own smoke, security, and benchmark gates pass.

Capability gates remain authoritative regardless of calibrated or learned scores. See `docs/HERMES-SMART-ROUTER-v0.5.2-IMPLEMENTATION-STATUS.md` for the exact implemented/open boundary.
