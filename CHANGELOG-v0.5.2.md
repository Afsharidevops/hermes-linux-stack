# v0.5.2 change summary — hermes-omniroute-linux-stack

- fixed router-info endpoint and retained compatibility alias
- hardened installer secret rotation and Smart Router client-key synchronization
- removed fixed Docker GID assumption
- enabled control/client auth by default and disabled Open WebUI signup by default
- made application image tags `.env`-overrideable while retaining `latest`/`main` defaults
- added provider health/circuit breakers, shared Redis state/stickiness, OIDC/ACL/secrets foundations, outcome capture and provider quality metadata
- added doctor/backup/restore/rollback/image-lock operations
- added HA Compose and Helm foundations plus security CI
- reconciled package version/documentation to Smart Router v0.5.2

See `docs/HERMES-SMART-ROUTER-v0.5.2-IMPLEMENTATION-STATUS.md` for items still open and not claimed complete.

## Post-review cleanup

- Replaced the Docker execution GID 0 fallback with fail-closed sentinel GID 65534; `install.sh` still detects the actual Docker socket GID when available.
- Removed a dead duplicate `/router/info` handler definition.
- Deduplicated Redis/Authlib dependency constraints to their prior effective versions.
- Removed the duplicate root `plan5.2.md`; the canonical roadmap is `docs/HERMES-SMART-ROUTER-v0.5.2-PLAN.md`.
- Updated smoke validation for configurable Smart Router image tags (`latest` by default, pinnable via `.env`).
