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
- n8n's `N8N_ENCRYPTION_KEY`, persisted `data/n8n/` state, and workflow credentials
- the Hermes-to-n8n MCP Bearer token in `data/hermes/.env`
- Smart Router HMAC secrets and SQLite state

The repository `.gitignore` excludes runtime secrets and persistent data. Check
with `git status --ignored` before every public release.

## Network defaults

All Compose host ports bind to `127.0.0.1` by default. The installer may suggest
the detected private LAN IP for selected editors and dashboards, including n8n;
accept it only for an intentionally trusted LAN. Prefer SSH port forwarding. If a
service must be public, place it behind HTTPS and appropriate authentication;
do not simply change every bind address to `0.0.0.0`.

Telegram polling uses outbound connections and needs no inbound firewall rule.

When the optional Caddy profile is enabled, expose only TCP 80/443 and UDP 443.
Keep 9router, Open WebUI, n8n, and Hermes host ports bound to `127.0.0.1`. DNS
names must point to the server before Caddy can obtain public certificates. The
generated n8n `/mcp*` route disables compression and uses immediate flushing;
preserve that no-buffering behavior so MCP SSE/streaming responses are not
truncated or delayed.

## n8n and MCP

A fresh n8n instance is unclaimed: the first visitor can create its owner account.
Keep it on localhost or a protected trusted LAN and claim it immediately before
publishing it through Caddy. Restrict the editor with firewall rules and HTTPS;
do not treat an obscure URL as authentication.

`N8N_ENCRYPTION_KEY` encrypts credentials stored under `data/n8n/`. Back up and
restore the key and directory together. Rotating or losing the key makes existing
stored credentials undecryptable; neither item is a useful complete recovery on
its own.

Hermes reaches the fixed managed MCP URL (`http://n8n:5678/mcp/hermes`)
over the private Docker network, not through n8n's public host/LAN port. The MCP
Server Trigger uses Bearer authentication. The token is never printed by a
management command: `./manage.sh rotate-n8n-token` updates n8n's encrypted
credential, updates Hermes, recreates it, verifies the new token, and restores the
prior credential on failure.

The owner-created n8n API key used by `set-n8n-api-key` is stored only in
mode-`0600` `data/stack-secrets/n8n-bootstrap.env`. Bootstrap passes all secrets
to its restricted ephemeral container through a temporary mode-`0600` env file,
not command arguments. Remove the stored owner key after successful bootstrap if
ongoing reconciliation is unnecessary:

```bash
./manage.sh remove-n8n-bootstrap-key
```

The non-secret state file retains managed IDs and fingerprints. Re-enter a valid
owner API key before later reconciliation or rotation. The reconciler updates
only persisted IDs, fails closed on managed-name collisions or manual drift, and
never accesses n8n's SQLite database. The verifier rechecks workflow definitions
and publication, requires anonymous hosted-chat requests to be rejected, invokes
Calculator through authenticated MCP, and closes established MCP sessions. Clone
generated workflows before customizing them.

The generated hosted chat uses n8n user authentication. Operators must be signed
in to n8n to use it; do not weaken the Chat Trigger to anonymous access when the
editor is LAN- or Internet-reachable.

Publishing a workflow exposes every connected MCP tool to anyone holding that
token. The generated workflow intentionally contains only Calculator. Scope n8n
credentials and downstream accounts to the minimum operations and data required,
and review cloned workflows for prompt-derived arguments before production use.
An unpublished MCP Server Trigger is unavailable rather than a security control.

The n8n container is distributed under the n8n Sustainable Use License. Review
its terms before deployment or redistribution.

## Package and skill installation

The stack-managed `stack-package-policy` plugin must remain enabled and mounted
read-only. Package installation is limited to exact registry versions, persistent
unprivileged targets, interactive Telegram sessions, and one-time manual
approvals. npm lifecycle scripts are disabled and Python installation accepts
binary wheels only. Review the displayed source, package, exact version,
destination, and normalized command before approving.

The managed Hermes config disables `terminal` and `code_execution`; this is the
primary boundary that prevents shell or dynamic-code indirection from bypassing
the broker. Keep both toolsets disabled. Plugin command-pattern checks are only
defense in depth and are not a complete sandbox for arbitrary execution.

Do not bypass this boundary with raw `pip`, `uv`, `npm`, `yarn`, `pnpm`, OS
package managers, shell indirection, or direct writes to the managed package
targets. Hermes remains unprivileged without a Docker socket, host root mount,
`sudo`, or OS package installation. Package preparation and execution require
manual approval mode; smart/model-mediated, YOLO, cron, and background contexts
fail closed. Skills must use Hermes's staged diff approval; a package approval
does not authorize a skill write or any later installation.

9router URL/key aliases do not grant web-search capability by themselves. Configure
a supported search provider separately, and install search skills only through
staged review. Keep provider credentials out of skill files and prompts.

## Smart Router

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
