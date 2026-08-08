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
- the Trigger and Instance-level Hermes-to-n8n MCP tokens in `data/hermes/.env`
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

Hermes uses one explicit n8n MCP mode over the private Docker network, never the
public host/LAN port:

- **Trigger** (`http://n8n:5678/mcp/hermes`) uses a stack-generated Bearer token
  and exposes only tools connected to the managed MCP Server Trigger workflow.
  The generated workflow contains only Calculator.
- **Instance** (`http://n8n:5678/mcp-server/http`) uses a personal token generated
  in n8n **Settings → Instance-level MCP → Connection details**. Its authority is
  bound to that n8n user and includes broad workflow, execution, credential-
  metadata, and data-table management. Workflow availability in Instance MCP and
  the user's project/workflow permissions still apply.
- **off** removes Hermes's managed connection. It does not disable Instance-level
  MCP globally because other clients may use it.

Never put either token in chat or argv. The stack never generates an Instance
token; `set-n8n-instance-mcp-token` reads it silently, first proves anonymous
rejection, then validates authenticated initialization and expected tools before
writing mode-`0600` `data/hermes/.env`. Regenerating the token in n8n immediately
revokes the previous token, so there is no server-side rollback to that revoked
value. Paste the replacement through the same command. Remove a stored token only
while Instance mode is inactive with `remove-n8n-instance-mcp-token`; this does
not disable Instance MCP in n8n.

Trigger-token rotation has a different lifecycle: `rotate-n8n-trigger-token`
(the `rotate-n8n-token` compatibility alias) transactionally updates n8n's
encrypted credential and Hermes, verifies it, and restores the prior Trigger
credential on failure. When switching to Instance or off mode, the managed Trigger
workflow is unpublished but its encrypted credential, IDs, fingerprint, and token
are retained for safe republishing. An unpublished Trigger endpoint is unavailable,
but retention is not a substitute for protecting its token.

The owner-created n8n API key used by `set-n8n-api-key` is a third, separate secret.
It is stored only in mode-`0600` `data/stack-secrets/n8n-bootstrap.env` and is used
by the public-API reconciler for hosted chat and Trigger publication changes; it is
not an MCP credential. Bootstrap passes secrets to restricted ephemeral containers
through temporary mode-`0600` env files, not command arguments. Remove the stored
owner key after bootstrap only if later reconciliation, publication changes, and
Trigger rotation are unnecessary:

```bash
./manage.sh remove-n8n-bootstrap-key
```

The non-secret state file retains managed IDs, fingerprints, and router metadata.
The reconciler updates only persisted IDs, fails closed on managed-name collisions
or manual drift, and never accesses n8n's SQLite database. Mode-specific
verification rechecks workflow definitions/publication and hosted-chat access.
Instance verification lists management tools but invokes only a bounded read-only
workflow search; Trigger verification invokes Calculator; established MCP sessions
are closed. Clone generated workflows before customizing them.

The generated hosted chat uses n8n user authentication. Operators must be signed
in to n8n to use it; do not weaken the Chat Trigger to anonymous access when the
editor is LAN- or Internet-reachable. Its model credential targets Smart Router
`auto` when installed or direct 9router model `ai` otherwise.

Publishing a Trigger workflow exposes every connected MCP tool to anyone holding
its token. Scope all n8n credentials and downstream accounts to the minimum
operations and data required, and review cloned workflows for prompt-derived
arguments before production use.

The n8n container is distributed under the n8n Sustainable Use License. Review
its terms before deployment or redistribution.

## Package and skill installation

The stack-managed `stack-package-policy` plugin must remain enabled and mounted
read-only. Package installation is limited to exact registry versions, persistent
unprivileged targets, interactive Telegram sessions, and one-time manual
approvals. npm lifecycle scripts are disabled and Python installation accepts
binary wheels only. Review the displayed source, package, exact version,
destination, and normalized command before approving.

By local operator decision, the managed Hermes config enables upstream
`terminal` and `code_execution`. They execute as the gateway uid and therefore
can read `/opt/data/.env`, including Telegram, backend, API-server, and n8n
credentials. Manual approval and upstream hardline patterns reduce accidental
execution but are not a filesystem sandbox and do not make a reusable approval
safe. Disable them with `./manage.sh set-upstream-terminal disabled` when that
risk is not acceptable. Plugin command-pattern checks are defense in depth only.

The separate stack execution tools are the isolation boundary for routine local,
SSH, and Docker work. Each capability is bound to one numeric Telegram execution
user, one interactive session, one feature, one canonical digest, one five-minute
nonce, and approval choice `once`. API, dashboard, MCP, cron/background, smart,
and bypass contexts fail closed. The Docker socket is mounted only into the
Docker broker; SSH keys only into the SSH broker; local sandboxes receive neither
and never join `agent-net`.

Execution also requires an independent decision from `execution-approver`. It
recomputes the exact digest and complete summary, sends them through a separately
configured Telegram bot to the matching authorized private numeric chat, and
accepts a one-time inline approval or denial. The approver alone holds that bot
token and an Ed25519 private signing key. Brokers hold only the public verification
key and persist the exact signed grant before atomic consumption. Hermes holds
neither key nor the approval bot token, so its broker control secret cannot approve
or execute by itself. A separate request-authentication secret permits sealed
broker-to-approver submissions but cannot forge decisions.

Execution is off until `./manage.sh set-execution-approval-bot-token` reads a token
silently, creates the approval keys, execution users are configured, and a feature
is explicitly enabled. Never pass that token in argv or reuse the main Hermes bot.
The approver has Telegram egress but no Docker socket or SSH profiles; brokers and
Hermes have no access to its token or private key. Keep all execution services
unpublished and preserve the internal execution-control network.

The broker denial floor rejects protected service names and resolved immutable IDs,
including inspect/log/remove operations; execution-control network names and IDs;
and host binds equal to, beneath, or ancestral to execution-authority paths. Docker
inspect output omits environment values, labels, and mounts. Local requests bind a
digest-pinned resolved image, workspace generation, and normalized `/workspace`
workdir. SSH requests bind host, port, user, authority, authentication type, and
known-host fingerprints and file digests, plus key fingerprints and file digests
for public-key profiles. Any change after approval fails closed.

An SSH profile may authenticate with a dedicated key or a locally configured
password. Password bytes stay inside the SSH broker's profile directory, which no
other service mounts, and are handed to OpenSSH only through an image-owned
askpass helper reading a mode-0600 file on the broker's private `tmpfs`. They are
never placed in argv, an environment value, a prompt, a Telegram message, a
broker request, an approval summary, a log, or an audit record, and `sshpass` is
not installed. What the sealed request binds instead is an HMAC-SHA256 tag over
the profile name, credential revision, and password, keyed by a secret mounted
only into the SSH broker. Neither Hermes nor the approver holds that key, so
neither can test password guesses offline, and a password, revision, or host-key
change between approval and execution fails closed. Password authentication
authorizes the SSH session only: keyboard-interactive and MFA are refused, only
one prompt is allowed, and `sudo-nopasswd` still means only `sudo -n`.

The Docker socket and approved privileged/host-mounted containers are
host-root-equivalent. Root and passwordless-sudo SSH profiles are
remote-root-equivalent. Approval authorizes an effect; it does not make it safe
or reversible. Disabling execution revokes pending operations but cannot undo
remote changes, revoke a remote public key, change a remote password, or clean up
already-created Docker objects. Skills must still use staged diff approval, and package approvals never
authorize later execution.

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
