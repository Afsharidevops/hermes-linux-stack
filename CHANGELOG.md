# Changelog

## v2.0.0-omniroute — 2026-08-08

### Breaking

- Replaced the 9router service and all runtime `NINEROUTER_*` configuration with OmniRoute.
- Router persistence moved to `data/omniroute`; legacy router data is not reused.
- Internal OpenAI-compatible upstream moved to `http://omniroute:20129/v1`.
- Removed legacy router-specific automatic key/combo bootstrap. OmniRoute provider/endpoint configuration is performed in OmniRoute itself.

### Added

- Split OmniRoute dashboard/API ports (`20128`/`20129`) with loopback host bindings by default.
- OmniRoute storage encryption, JWT, API-key secret, initial-password, deployment-specific machine salt, WebSocket bridge secret, API-auth, and public-base-url configuration.
- Installer support for Hermes/Open WebUI/Smart Router using OmniRoute.
- `manage.sh enable-omniroute-api-auth` and `disable-omniroute-api-auth`.
- `manage.sh set-model`, `migration-status`, `doctor`, and stack backup commands.
- Migration and release notes.

### Changed

- Smart Router upstream now targets OmniRoute and defaults to the `auto` route instead of legacy combo names.
- Hermes provider is named `OmniRoute` and reads `OMNIROUTE_API_KEY`.
- Open WebUI points at OmniRoute (or Smart Router when selected).
- Compose project/network names now use `hermes-omniroute-*`.
