# Hermes Linux Stack — v0.5.7 Changelog

## Focus

v0.5.7 integrates secure execution administration with the v0.5.6 Operations Center without collapsing the execution-broker trust boundaries.

## Execution & Approvals

- Added **System → Execution & Approvals** to Hermes Operations Center.
- Added `execution-admin` mode to Hermes Execution Broker `0.1.2`.
- Operations Center talks directly from the operator browser to the separate Execution Admin endpoint with a separate admin key.
- Smart Router backend does not receive the Execution Admin key or dedicated Telegram approval-bot token.
- Execution Admin does not mount the Ed25519 approval signing key, Docker socket, or SSH private credentials.
- Added live redacted health for approver, Docker broker and SSH broker.
- Added live enable/disable policy for already-deployed `local`, `docker`, and `ssh` execution capabilities.
- Added Telegram execution approver management, constrained to IDs already present in `TELEGRAM_ALLOWED_USERS`.
- Added write-only dedicated approval-bot token replacement. The token is never returned by the API.
- Added protection preventing the execution approval bot from reusing the Hermes Telegram bot token when the Hermes token hash is synchronized.
- Added broker control-secret rotation from the separate admin boundary.
- Added redacted SSH profile listing without exposing private keys/passwords.
- Added execution-admin audit events.
- Every execution policy/admin mutation increments the policy generation, invalidating older pending capabilities/approvals.

## Dynamic execution policy

- Added `EXECUTION_FEATURES_FILE` support to the Hermes execution policy plugin and execution brokers.
- Added `EXECUTION_POLICY_GENERATION_FILE` support to Docker, SSH and approver modes.
- Policy files are bind-mounted and rewritten in place to preserve host ownership and permissions.
- Existing environment variables remain compatibility fallbacks.
- First-time broker deployment remains a host `manage.sh` operation; the UI does not need Docker-socket authority.

## Management commands

Added:

```text
./manage.sh enable-execution-admin
./manage.sh disable-execution-admin
./manage.sh execution-admin-status
./manage.sh show-execution-admin-key
./manage.sh rotate-execution-admin-key
```

The existing execution commands remain supported.

## Security defaults

- Execution Admin binds to `127.0.0.1:8752` by default.
- Browser CORS uses an exact allowlist (`EXECUTION_ADMIN_ALLOWED_ORIGINS`); wildcard origins are not used.
- The admin credential is separate from Smart Router authentication.
- Operations Center keeps the Execution Admin key only in page memory; it is not written to localStorage.
- Bot token readback is not implemented.
- Signing-key rotation and SSH credential creation/removal remain local operator/CLI operations.

## v0.5.6 platform foundations retained

v0.5.7 retains the v0.5.6 light/dark UI, lifecycle fixes, hybrid vector RAG/pgvector support, Flight Deck traces, guardrails, router pipelines, workflows, prompt versioning, datasets/evaluations, model catalog, marketplace/onboarding and HA foundations.

## Compatibility

- Smart Router runtime/schema marker: `0.5.7`.
- Existing `control-v0.5.2.sqlite3` compatibility filename is preserved and upgraded in place.
- Smart Router image target: `afsharidevops/hermes-smart-router:0.5.7`.
- Execution Broker image target: `afsharidevops/hermes-execution-broker:0.1.2`.
- Branches: `main` (9router) and `hermes-omniroute-linux-stack` (OmniRoute).
