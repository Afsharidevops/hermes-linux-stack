# Roadmap and design recommendations

## Implemented optional integrations

- The opt-in `n8n` Compose profile runs `n8nio/n8n:latest`, persists state in
  `data/n8n/`, and supports localhost, trusted-LAN, or Caddy HTTPS editor access.
- Hermes-to-n8n MCP has explicit `instance`, `trigger`, and `off` modes. Trigger
  mode publishes a narrow Calculator workflow; Instance mode uses an n8n-generated
  user-bound personal token for broad management tools; switching away unpublishes
  but retains the managed Trigger workflow and credential.
- After owner setup, the operator can store a separate n8n API key silently and use
  the public API reconciler to provision n8n-user-authenticated hosted chat through
  Smart Router model `auto` or direct 9router model `ai` when Smart Router is absent.
- Reconciliation persists managed IDs/fingerprints, is idempotent, fails closed on
  name collisions or manual drift, and supports transactional Trigger-token
  rotation. Mode-specific verification checks fingerprints, publication/access
  policy, a bounded read-only Instance search or Trigger Calculator output, and MCP
  session closure.
- Hermes can install reviewed skills and exact-version unprivileged Python/npm
  packages through staged or one-time manual Telegram approvals. Stack execution
  brokers add exact one-time-approved sandbox, pinned-profile SSH, and structured
  host Docker operations while keeping the Docker socket and SSH keys out of
  Hermes. Execution is locally opt-in with an operator allowlist and persistent
  anti-replay nonces. Upstream terminal/code-execution are also enabled by explicit
  operator choice, with the documented consequence that they can read Hermes
  credentials after manual approval.
- Disabling n8n stops and removes its containers while preserving workflow data.
  Backups must keep `N8N_ENCRYPTION_KEY` coupled with `data/n8n/` and should retain
  `data/stack-secrets/n8n-bootstrap-state.json` for managed-object ownership.

## Recommended next release

1. Add tested backup and restore commands with retention settings.
2. Support an optional S3-compatible backup/artifact endpoint.
3. Add non-interactive installer flags for automation and cloud-init.
4. Pin images in tagged releases and automate update pull requests.
5. Add HTTP readiness checks for every enabled service.
6. Measure Smart Router observation data before enabling route mode by default.
7. Add safe workload-normalized cost reporting outside the request path.

## RustFS recommendation

RustFS should be optional, not a required fourth core service. Telegram sends
Hermes files directly from persistent local storage, so object storage is not
needed for basic chat operation.

Object storage becomes useful for:

- off-server backups;
- generated-image and document archives;
- multiple Hermes servers sharing artifacts;
- retention and lifecycle policies.

The best public design is a generic S3-compatible integration that accepts an
endpoint, bucket, region, access key, and secret key. Users can then select an
existing RustFS, MinIO, AWS S3, or compatible provider. A bundled RustFS profile
can be added later for users who explicitly want local self-hosted storage.

## Management UI recommendation

The included `./manage.sh menu` is the recommended first management interface:
it is lightweight, works over SSH, and does not create a new network attack
surface.

A browser management panel could later manage Telegram IDs, service selection,
logs, backups, ports, and health. It should not mount the Docker socket directly
or display raw secret files. A safe design needs:

- localhost-only binding by default;
- strong login and CSRF protection;
- narrowly scoped server-side actions;
- encrypted or redacted secrets;
- an audit log;
- authenticated HTTPS before public exposure.

## Other useful additions

- `backup`, `restore`, and scheduled backup commands;
- optional Telegram notifications when containers become unhealthy;
- configuration export with secrets redacted;
- UFW/firewalld guidance and automated checks;
- optional authentication middleware in front of sensitive dashboards;
- optional Prometheus metrics and a small health dashboard;
- release checksums and signed GitHub releases;
- documented migration between servers;
- Renovate or Dependabot for pinned image updates;
- an uninstall command that preserves data unless deletion is explicitly chosen.
