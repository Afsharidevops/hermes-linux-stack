# Roadmap and design recommendations

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
