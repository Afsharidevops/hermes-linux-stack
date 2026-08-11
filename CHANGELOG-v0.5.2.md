# v0.5.2 change summary — main

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
