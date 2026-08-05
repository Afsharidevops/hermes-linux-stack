# Security policy

## Secrets

Never commit or publish:

- `.env`
- `data/hermes/.env`
- any file under `data/`
- backups containing those files
- Telegram bot tokens
- 9router endpoint or provider keys
- Open WebUI signing secrets
- Smart Router HMAC secrets and SQLite state

The repository `.gitignore` excludes runtime secrets and persistent data. Check
with `git status --ignored` before every public release.

## Network defaults

All host ports bind to `127.0.0.1` by default. Prefer SSH port forwarding. If a
service must be public, place it behind HTTPS and appropriate authentication;
do not simply change every bind address to `0.0.0.0`.

Telegram polling uses outbound connections and needs no inbound firewall rule.

When the optional Caddy profile is enabled, expose only TCP 80/443 and UDP 443.
Keep 9router, Open WebUI, and Hermes host ports bound to `127.0.0.1`. DNS names
must point to the server before Caddy can obtain public certificates.

The Smart Router has no published host port and must remain on the private Docker
network. It forwards endpoint authentication to 9router unchanged and never logs
or stores prompts, responses, raw credentials, or raw session identifiers. Rotating
`SMART_ROUTER_HMAC_SECRET` intentionally invalidates existing sticky routes.

Publish Smart Router images with a versioned tag or manifest digest. Docker Hub
credentials belong only in a local credential helper or protected GitHub Actions
secrets; never add them to this repository, `.env`, Docker build arguments, or logs.

## Reporting vulnerabilities

Do not open a public issue containing secrets or exploit details. Use the
private security-reporting feature of the GitHub repository when enabled.
