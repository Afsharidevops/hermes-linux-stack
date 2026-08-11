# Package scope — v0.5.2

This ZIP is a self-contained enhanced deployment package for the `hermes-omniroute-linux-stack` branch and its Hermes -> Smart Router -> **OmniRoute** path. The Smart Router source is intended to remain identical to the other supported gateway branch; gateway-specific behavior should be configuration rather than a second router implementation.

The default application image policy intentionally remains mutable (`latest`, and `main` for Open WebUI) at operator request. Repository/tag pairs are exposed in `.env.example`, so a stable version can later be pinned without editing `docker-compose.yml`.

The package includes the v0.5.2 reliability/security foundation, operational scripts, HA Compose reference, and a Helm foundation. It does **not** claim completion of the entire long-range `docs/HERMES-SMART-ROUTER-v0.5.2-PLAN.md`; the precise implemented/open list is in `docs/HERMES-SMART-ROUTER-v0.5.2-IMPLEMENTATION-STATUS.md`.
