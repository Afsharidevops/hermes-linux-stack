# Hermes Operations Center User Guide — v0.5.7

Hermes Linux Stack v0.5.7 extends the v0.5.6 platform UI with a security-separated **Execution & Approvals** workspace. Existing Routing, Access, Knowledge, Memory, Agents, Teams, Skills, Plugins, workflows, prompts, evaluations, model catalog, traces, guardrails, onboarding, and light/dark theme behavior remain available.

## Execution & Approvals

Open Hermes Operations Center at `/control/` and choose **System → Execution & Approvals**.

The page connects from the operator browser directly to the optional `execution-admin` service. The Smart Router backend does not receive the Execution Admin credential, Telegram approval-bot token, approval private signing key, Docker socket, or SSH private credentials.

### First-time host setup

```bash
./manage.sh enable-execution-admin
./manage.sh execution-admin-status
./manage.sh show-execution-admin-key
```

`show-execution-admin-key` is intentionally restricted to an interactive trusted terminal. Paste the key into the Operations Center connection field only for the current browser session; the UI does not persist it in local storage.

The admin endpoint binds to `127.0.0.1:8752` by default. For a remote Operations Center, bind only to a trusted private address and configure exact `EXECUTION_ADMIN_ALLOWED_ORIGINS` values.

### What the UI can manage

- live Sandbox/local, Docker, and SSH feature policy for already-deployed brokers;
- numeric Telegram execution approver IDs;
- write-only replacement of the dedicated execution approval-bot token;
- broker control-secret rotation;
- broker/approver health status;
- SSH profile names and authentication type (metadata only);
- execution-admin audit history.

Each configuration mutation increments the execution policy generation. Pending capabilities/approvals from an older generation therefore fail closed.

### What remains host-only

For security, first-time deployment/removal of the Docker and SSH broker containers, SSH credential creation/removal, private approval signing-key management, and destructive execution purge operations stay behind `manage.sh` on the host.

Useful commands:

```bash
./manage.sh execution
./manage.sh execution-status
./manage.sh enable-execution-admin
./manage.sh execution-admin-status
./manage.sh rotate-execution-admin-key
./manage.sh disable-execution-admin
./manage.sh set-execution-approval-bot-token
./manage.sh set-execution-users 123456789,987654321
./manage.sh enable-execution sandbox
./manage.sh enable-execution docker
./manage.sh enable-execution ssh
```

## Telegram approval safety

The execution approval bot must remain dedicated to execution approval. The admin service receives only the token file needed for write-only replacement; it never receives the Ed25519 private decision-signing key. A hash marker of the Hermes Telegram bot token is used to reject accidental reuse of the same token without exposing that Hermes token to the admin service.

Approver IDs must be numeric and must already belong to the Hermes `TELEGRAM_ALLOWED_USERS` policy. This prevents the UI from silently expanding the Telegram trust boundary beyond the host-approved Hermes user set.

## Light and dark mode

Operations Center and Flight Deck retain the v0.5.6 theme control. Theme preference is browser-side UI state and does not change routing or execution policy.

## Lifecycle controls

v0.5.7 retains the normalized lifecycle behavior introduced in v0.5.6: **Enable/Disable changes active state; Permanent Delete is a separate destructive action** for supported resources. Groups referenced by ACLs cannot be purged accidentally without an explicit cascade path.

## Upgrade compatibility

The Smart Router runtime/control schema advances in place to `0.5.7`. The compatibility database filename remains `control-v0.5.2.sqlite3`; do not delete the persistent Operations Center data directory during upgrade.
