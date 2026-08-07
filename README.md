# Hermes + 9router + Open WebUI Linux Stack

Interactive, public-safe Docker deployment for:

- [9router](https://github.com/decolua/9router) — OpenAI-compatible provider router
- Hermes Smart Router — optional sticky complexity routing and output budgeting
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — persistent AI agent with Telegram
- [Open WebUI](https://github.com/open-webui/open-webui) — optional browser chat interface
- [n8n](https://n8n.io/) — optional workflow automation and Hermes MCP tools
- [Caddy](https://caddyserver.com/) — optional domain routing and automatic HTTPS

The installer asks what to install and collects all required settings. You can
install both 9router and Hermes, either service alone, add Open WebUI or n8n to
any selection, or install Open WebUI by itself. n8n is opt-in and is not started
unless its Compose profile is selected; on an existing installation it can remain
the only selected profile after the other services are disabled.

## Features

- Interactive setup with hidden secret prompts
- Official multi-architecture container images
- Works on common AMD64 and ARM64 Linux servers
- Persistent data stored under `data/`
- Telegram polling: no domain, inbound port, or SSL required
- Numeric Telegram user allowlist
- Private Docker network between services
- Automatic private LAN IPv4 detection with LAN-accessible service defaults
- Optional Hermes dashboard and API
- Optional Open WebUI connected to 9router or another OpenAI-compatible API
- Dedicated auto-generated 9router keys for Hermes and Open WebUI
- Installer-managed `OpenCode-Free` and `ai` combos with current free fallbacks
- Optional Smart Router with observe/route modes, sticky tiers, transparent SSE,
  request-aware output budgets, privacy-safe metrics, and no answer cache
- Optional n8n Compose profile with persistent workflows and a Hermes MCP
  client bridge
- Optional Caddy profile with wizard-generated domains, automatic HTTPS, and
  unbuffered n8n MCP streaming
- Secure generated JWT, signing, machine-ID, WebUI, n8n, and API secrets
- Reconfiguration backups
- Simple update, logs, status, and user-management commands
- GitHub Actions validation for shell and Compose files

## Architecture

```text
Telegram API
    ↑ outbound polling
    │
Hermes Agent ───┐
       │        ├──→ optional Smart Router ──→ 9router ──→ AI providers
       │        │
       │        └──→ n8n MCP Server Trigger (private Docker network)
       │
Open WebUI ─────┘
                                ↑
Internet ── HTTPS ── optional Caddy reverse proxy

Host defaults (using the detected private LAN IP):
  9router:    LAN_IP:20128
  Open WebUI: LAN_IP:3000
  n8n editor: LAN_IP:5678 (only when selected)
  Hermes API: LAN_IP:8642 (disabled unless selected)
  Hermes UI:  LAN_IP:9119 (disabled unless selected)
```

## Requirements

- Linux server
- Bash 4 or newer
- Docker Engine with the `docker compose` plugin
- `curl` if you want the wizard to install Docker
- At least 2 GB RAM recommended for the full stack
- Sufficient disk for container images and persistent chats
- Public DNS records and inbound ports 80/443 only when Caddy is selected

If Docker is missing, the installer asks permission before downloading and
running Docker's official convenience installer.

## Quick start

One-command interactive installation:

```bash
curl -fsSL https://raw.githubusercontent.com/Afsharidevops/hermes-linux-stack/main/install.sh | bash
```

This clones or updates the full project at `$HOME/hermes-linux-stack`, then
opens the interactive wizard. Choose another location with:

```bash
curl -fsSL https://raw.githubusercontent.com/Afsharidevops/hermes-linux-stack/main/install.sh | HERMES_STACK_DIR=/opt/hermes-linux-stack bash
```

The target parent directory must be writable by the current user. The installer
uses `sudo` only when Docker administration requires it.

Alternatively, clone and run directly:

```bash
git clone https://github.com/Afsharidevops/hermes-linux-stack.git
cd hermes-linux-stack
chmod +x install.sh manage.sh
./install.sh
```

The installer asks:

1. Which services to install
2. Whether to add Open WebUI
3. Bind addresses and ports
4. 9router dashboard password and public URL
5. Whether `/v1` requires a Bearer key
6. 9router model/combo name used by Hermes
7. Telegram BotFather token and allowed numeric IDs
8. Optional Telegram home channel
9. Optional Hermes dashboard and API
10. Optional Smart Router for both Hermes and Open WebUI, initially in observe mode
11. Open WebUI endpoint (or automatic routed 9router connection), URL, and signup policy
12. Optional n8n workflow automation, editor bind/URL, timezone, and Hermes MCP bridge
13. Caddy bind address and optional HTTPS domains for each installed web service

The installer detects the server's primary private LAN IPv4 address and suggests
it as the default bind for 9router, Hermes, Open WebUI, and the optional n8n editor.
The Compose/.env default remains `127.0.0.1`; accept the LAN suggestion only when
trusted LAN access is intentional. Choose the bind mode
that matches how you want to access the services:

| Bind value | Who can connect | How to open a service |
|---|---|---|
| Detected `LAN_IP` | Trusted devices on the same LAN | `http://LAN_IP:PORT` |
| `127.0.0.1` | Only the Linux server itself | Use an SSH tunnel, then open `http://localhost:PORT` |
| `0.0.0.0` | Devices reaching any server interface | Use only with a firewall and appropriate authentication |

Press Enter at a bind prompt to accept the suggested `LAN_IP`. This is convenient
for a trusted home, office, or lab network. Restrict each application port to your
trusted LAN subnet with the host or network firewall. LAN binding uses plain HTTP
unless you add a reverse proxy with HTTPS.

Enter `127.0.0.1` when you want the service hidden from the LAN. A remote device
must then create an SSH tunnel to the server. A specific `LAN_IP` is preferable to
`0.0.0.0` because it avoids publishing the service on unrelated interfaces.

On a later wizard run, choose **Change published container bind IPs only** to
update these addresses without re-entering service or Telegram secrets. Caddy
defaults to `0.0.0.0` because public certificate validation must reach ports 80
and 443.

Secrets are written to ignored files with mode `0600`:

- `.env` — Compose, service, Smart Router HMAC, and n8n encryption secrets
- `data/hermes/.env` — Hermes/Telegram secrets and the n8n MCP bearer token
- `data/smart-router/router.sqlite3` — pseudonymous sticky-route state
- `data/n8n/` — n8n workflows, settings, and encrypted credentials

Never commit these secret files or runtime data.

## Optional Hermes Smart Router

The installer can place an internal OpenAI-compatible Smart Router between Hermes,
Open WebUI, and 9router. Both clients retain separate 9router endpoint keys, so
sticky sessions and metrics remain isolated by caller. The image source is
in `smart-router/`; the versioned public image is:

```text
afsharidevops/hermes-smart-router:0.1.0
```

The initial mode is `observe`. Requests using the virtual `auto` model are sent to
the existing `ai` combo while the router records a proposed fast, standard, or
strong tier and proposed output budget. **Observation mode does not enforce output
budgets**, so it can be compared fairly with direct Hermes → 9router behavior.
Explicit non-auto models always pass through unchanged.

In `route` mode, auto requests select `combo-fast`, `combo-standard`, or
`combo-strong` and may have output limits clamped but never increased. The
installer initially clones `ai` into all three combos. They are therefore identical
until you customize their ordered model lists in the 9router dashboard.

```bash
./manage.sh set-router-mode observe
./manage.sh set-router-mode route
./manage.sh logs smart-router
./manage.sh doctor
```

### Using models in route mode

Use the `auto` model for normal operation in route mode:

```text
auto → combo-fast, combo-standard, or combo-strong
```

| Selected model | Behavior |
|---|---|
| `auto` | Smart Router analyzes the request and selects a tier |
| `auto-fast` | Requests the fast tier; capability requirements may upgrade it |
| `auto-standard` | Requests the standard tier; capabilities may require strong |
| `auto-strong` | Requests the strong tier |
| `ai` | Bypasses automatic routing and sends the explicit `ai` combo unchanged |
| `OpenCode-Free` | Bypasses automatic routing and sends that explicit combo unchanged |

Therefore, the recommended normal selection is:

```text
Model: auto
```

#### Hermes and Telegram

The installer configures Hermes with `auto` when Smart Router is enabled. Verify
its active model and backend URL:

```bash
grep -E '^[[:space:]]*(default|base_url):' \
  /root/hermes-linux-stack/data/hermes/config.yaml
```

Expected output:

```yaml
default: 'auto'
base_url: 'http://smart-router:8080/v1'
```

Telegram `/model` should report:

```text
Current model: auto
Provider: custom:9router
```

Selecting `ai` manually bypasses automatic tier selection. Select `auto` again to
restore Smart Router routing.

#### Open WebUI

Select `auto` in the Open WebUI model selector for automatic routing. For manual
tier testing, select one of:

```text
auto-fast
auto-standard
auto-strong
```

Selecting `ai`, `OpenCode-Free`, or another explicit model bypasses automatic tier
selection and forwards that model unchanged.

#### Confirm automatic routing

Send a simple prompt while using `auto`:

```text
Reply briefly: hello
```

Then inspect the latest decision:

```bash
docker logs --since 2m hermes-smart-router 2>&1 | grep route_decision
```

A simple request should include:

```json
{
  "requested_model": "auto",
  "effective_model": "combo-fast",
  "mode": "route"
}
```

For a difficult request, such as:

```text
Perform a detailed security review and threat model for this architecture.
```

the decision should include:

```json
{
  "requested_model": "auto",
  "effective_model": "combo-strong",
  "mode": "route"
}
```

In short: use `auto` for normal operation in route mode.

The router stores only HMAC-pseudonymous sticky-route metadata in
`data/smart-router/router.sqlite3`. It does not cache answers, rewrite messages,
filter tools, classify with another LLM, or retry requests. 9router may still apply
its own provider/combo fallback behavior. Metrics at `/metrics` are available only
inside the private Docker network and separate proposed budgets from actual
upstream usage; they do not claim realized savings.

Smart routing primarily reduces strong-model use and cost. Actual token reduction
in v0.1.0 comes from enforced output limits in route mode, plus Hermes compression
and 9router RTK/optional Headroom outside this sidecar.

Rollback is available by rerunning `./install.sh` and disabling the Smart Router;
Hermes returns to `http://nine-router:20128/v1` with model `ai`, while router state
is preserved for inspection.

## Optional n8n and Hermes MCP tools

The opt-in `n8n` Compose profile runs the user-requested `n8nio/n8n:latest` image
and stores its state in `data/n8n/`. Select **Add optional n8n workflow
automation?** in the installer. The editor's Compose default is localhost; the
wizard suggests the detected private LAN address for convenient trusted-LAN
access and lets you keep `127.0.0.1` instead. Do not expose an unclaimed instance:
the first visitor to a fresh n8n installation can create its owner account.

The installer generates and preserves `N8N_ENCRYPTION_KEY` in `.env`. n8n uses
this key to encrypt stored credentials. Always back up `.env`—specifically this
key—together with `data/n8n/`; restoring the data without the matching key makes
those credentials unreadable. The bundled image is subject to the
[n8n Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md),
not this repository's MIT license. Review that license for your use case.

### Bootstrap the managed MCP and hosted-chat workflows

When Hermes, n8n, and 9router are selected, the installer can connect Hermes to
n8n in one of three explicit modes:

- **Instance-level MCP** uses `http://n8n:5678/mcp-server/http`. It carries the
  permissions of the n8n user who generated the personal token and exposes broad
  workflow, execution, credential-metadata, and data-table management tools.
- **MCP Server Trigger** uses `http://n8n:5678/mcp/hermes` and exposes only tools
  explicitly connected in the managed workflow (Calculator by default).
- **off** removes only the stack-managed Hermes MCP entry.

Both endpoints stay on the private Docker network; the public editor URL and
host/LAN port are not used by Hermes. Selecting Instance mode on a fresh install
is initially pending: the stack never generates this personal token. Claim the
owner account, then use **Settings → Instance-level MCP → Connection details** to
enable access and generate/copy its token. Paste it only into the silent prompt:

```bash
./manage.sh set-n8n-instance-mcp-token
```

Never paste an Instance token in chat or pass it as a command argument. Regenerating
it in n8n immediately revokes the previous token; after regeneration, run the same
command to validate, store, and activate the replacement.

Hosted-chat reconciliation and Trigger workflow publication use a separate n8n
owner API key. Create it after claiming the owner account, then capture it through
a silent prompt so it does not enter shell history or process arguments:

```bash
./manage.sh set-n8n-api-key
./manage.sh bootstrap-n8n
```

The public-API reconciler always creates or updates **Hermes Hosted Chat
(managed)**: an n8n-user-authenticated Chat Trigger → AI Agent → OpenAI Chat Model
using a dedicated n8n 9router key. With Smart Router installed it targets
`http://smart-router:8080/v1` and model `auto`; without Smart Router it targets
`http://nine-router:20128/v1` and model `ai`. Anonymous chat requests are rejected.

In Trigger mode the reconciler also creates/publishes **Hermes MCP Tools
(managed)** with an encrypted Bearer credential and Calculator. In Instance or off
mode, an existing managed Trigger workflow is unpublished but retained together
with its encrypted credential, stable IDs, fingerprint, and Trigger token. Switching
back to Trigger republishes the same objects rather than creating duplicates. The
stack does not globally disable Instance-level MCP when switching away because
other n8n clients may use it.

The command persists only non-secret managed IDs, fingerprints, and routing
metadata in `data/stack-secrets/n8n-bootstrap-state.json`, recreates Hermes, and
runs mode-specific verification. Instance verification lists expected management
tools but invokes only a bounded read-only workflow search. Trigger verification
invokes Calculator with `2+3`; off mode skips MCP protocol probing. All modes verify
hosted-chat authentication and managed publication state. Name collisions or
manual edits to stack-owned objects fail closed; clone a managed workflow before
customizing it.

Useful lifecycle commands are:

```bash
./manage.sh set-n8n-mcp-mode instance
./manage.sh set-n8n-mcp-mode trigger
./manage.sh set-n8n-mcp-mode off
./manage.sh set-n8n-instance-mcp-token
./manage.sh remove-n8n-instance-mcp-token
./manage.sh verify-n8n
./manage.sh reconcile-n8n
./manage.sh rotate-n8n-trigger-token
./manage.sh remove-n8n-bootstrap-key
```

The compatibility alias `./manage.sh rotate-n8n-token` rotates only the retained
Trigger credential. Removing the owner API key retains managed IDs/fingerprints,
but later reconciliation, publication changes, and Trigger rotation require a valid
key again. Both mode-specific MCP tokens are stored only in mode-`0600`
`data/hermes/.env`; `config.yaml` contains environment references. The owner API
key is stored separately in mode-`0600`
`data/stack-secrets/n8n-bootstrap.env`.

If Caddy publishes n8n, the generated `/mcp*` route disables compression and sets
`flush_interval -1` so MCP SSE/streaming responses are not buffered. Hermes still
uses the private Docker endpoint; Caddy is only for clients using the public n8n
domain.

Rerun `./manage.sh configure` and decline **Keep n8n workflow automation
enabled?** to disable the profile. The installer stops and removes the active
n8n containers but deliberately preserves `data/n8n/`, the encryption key, and
managed bootstrap state.

## First setup when installing all services

### 1. Open 9router

The installer suggests the detected private LAN IP as the bind address. From any
trusted device on the same LAN, open:

```text
http://LAN_IP:20128
```

For example:

```text
http://192.168.10.10:20128
```

Sign in with the initial password entered during installation. Ensure the server
firewall permits TCP port `20128` only from your trusted LAN subnet.

If you selected `127.0.0.1` instead of the LAN IP, create an SSH tunnel from your
workstation:

```bash
ssh -L 20128:127.0.0.1:20128 user@your-server
```

Then open <http://localhost:20128>.

Configure provider accounts and create a combo/model such as `ai`. The combo
name must match the model name entered in the installer.

### 2. Configure endpoint authentication

When 9router is selected with Hermes or Open WebUI, the installer automatically:

1. Generates or reuses separate endpoint keys named `Hermes Agent
   (hermes-linux-stack)` and `Open WebUI (hermes-linux-stack)`.
2. Fetches the current no-cost model list from OpenCode.
3. Creates or updates `ai` and `OpenCode-Free`; with Smart Router enabled it also
   clones `ai` into `combo-fast`, `combo-standard`, and `combo-strong`.
4. Stores keys without printing them, synchronizes an existing Open WebUI database
   to the selected direct/routed URL, and verifies authenticated model discovery.

The key is intentionally not printed. You can inspect, rotate, or revoke it in
the 9router dashboard. OpenCode's free catalog is dynamic, so rerunning the
installer refreshes the combo.

For a fresh private installation, leaving `REQUIRE_API_KEY=false` still allows
Hermes to use its configured local key behavior. Open WebUI always receives its
own generated key.

For stronger protection:

1. Generate an endpoint API key in the 9router dashboard.
2. Set `NINEROUTER_REQUIRE_API_KEY=true` in `.env`.
3. Give the key to Hermes:

```bash
./manage.sh set-backend-api-key YOUR_9ROUTER_API_KEY
./manage.sh restart
```

For an external OpenAI-compatible endpoint (when 9router is not selected), the
wizard asks for that endpoint's API key normally.

Do not use provider master/management keys when a scoped endpoint key is
available.

### 3. Test Telegram

Open the bot created with BotFather and send:

```text
/start
```

Hermes accepts only IDs in `TELEGRAM_ALLOWED_USERS`. Telegram usernames are not
authorization IDs. You can obtain your numeric ID from `@userinfobot`.

If Hermes says no home channel is configured, send `/sethome` in the one chat
that should receive cron results and cross-platform notifications. Other
allowed users can still chat normally.

### 4. Create the first Open WebUI account

From a trusted device on the same LAN, open:

```text
http://LAN_IP:3000
```

For example:

```text
http://192.168.10.10:3000
```

The first registered account becomes the administrator. After creating it, open
Admin Panel → Settings → General and turn off new-user signup. Restrict TCP port
`3000` to the trusted LAN; plain HTTP does not protect traffic on an untrusted
network.

If Open WebUI is bound to `127.0.0.1`, use an SSH tunnel instead:

```bash
ssh -L 3000:127.0.0.1:3000 user@your-server
```

Then open <http://localhost:3000>.

Open WebUI persists some configuration in its own database after first start.
Later connection changes can also be made in its Admin Panel.

## Management commands

Open the lightweight terminal UI:

```bash
./manage.sh menu
```

It provides status, Telegram access management, restarts, updates, logs, and
reconfiguration without exposing another web administration service.

```bash
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh update
./manage.sh status
./manage.sh doctor
./manage.sh logs
./manage.sh logs hermes
./manage.sh logs 9router
./manage.sh logs webui
./manage.sh logs n8n
./manage.sh logs caddy
./manage.sh restart-hermes
./manage.sh set-n8n-api-key
./manage.sh set-n8n-instance-mcp-token
./manage.sh remove-n8n-instance-mcp-token
./manage.sh set-n8n-mcp-mode instance|trigger|off
./manage.sh bootstrap-n8n
./manage.sh reconcile-n8n
./manage.sh verify-n8n
./manage.sh rotate-n8n-trigger-token
./manage.sh remove-n8n-bootstrap-key
./manage.sh configure
```

### Telegram access

Show the current allowlist:

```bash
./manage.sh show-telegram-users
```

Add one user without removing existing users:

```bash
./manage.sh add-telegram-user 946652372
```

Replace the complete list:

```bash
./manage.sh set-telegram-users 111111111,222222222,333333333
```

Hermes is recreated automatically after an allowlist change.

### Approval-gated skills and packages

Hermes skills continue through the native staged review flow: inspect changes
with `/skills diff`, then explicitly `/skills approve` or `/skills reject`.
Direct `hermes skills install` execution is blocked so it cannot bypass that
review.

The read-only `stack-package-policy` plugin provides persistent, unprivileged
Python and npm installation. Each operation is prepared as a sealed one-time
request and requires a fresh approval from an interactive Telegram session while
`approvals.mode` is `manual`. A session-wide, permanent, smart/model-mediated,
YOLO, cron, or background authorization cannot approve a package operation.

The managed Hermes config enables upstream `terminal` and `code_execution` by
explicit operator choice. They run as the Hermes gateway uid and can read
`/opt/data/.env`; manual approval remains mandatory. Use
`./manage.sh set-upstream-terminal disabled` to remove them. The isolated stack
execution tools below are preferred for routine work because they seal and
approve each exact operation once. The package plugin's raw-command checks are
defense in depth, not isolation from an approved local terminal command.

Supported package specifications are deliberately narrow:

- Python: exactly `package==version` from PyPI, binary wheels only.
- npm: exactly `package@version` from the npm registry, lifecycle scripts off.

URLs, Git refs, local paths, ranges, `latest`, alternate registries, arbitrary
flags, raw package-manager commands, OS package managers, and direct writes to
the managed targets are blocked. Before approving, verify the displayed source,
package, exact version, destination, and normalized command. Packages persist in
`data/hermes/lazy-packages/` and `data/hermes/npm-packages/`; they do not grant
root access, Docker access, or additional host mounts. Run `./manage.sh doctor`
to check that the policy plugin is enabled and mounted read-only.

### Approved terminal, SSH, and Docker execution

Execution brokers are off by default. Use a second BotFather bot dedicated only
to execution approval; do not reuse the Hermes bot. Configure its token through
silent input, select Telegram operators, then enable only the desired capabilities:

```bash
./manage.sh set-execution-approval-bot-token
./manage.sh set-execution-users 123456789
./manage.sh enable-execution sandbox
./manage.sh enable-execution ssh
./manage.sh enable-execution docker
./manage.sh execution-status
```

`set-execution-users` accepts only numeric IDs already present in
`TELEGRAM_ALLOWED_USERS`. Every sandbox, SSH, and Docker operation is prepared and
sealed to that user, Telegram session, policy generation, and canonical digest.
The independent `execution-approver` recomputes the complete summary and digest,
sends them to the matching private numeric chat through its dedicated bot, and
accepts one inline approval or denial. The broker persists and atomically consumes
that exact signed grant once. This independent signed decision is the broker's
trust root. Hermes's native approval prompt remains defense in depth and accepts
only `once`; it is not an independently enforced boundary against compromised
code already running inside Hermes.

Hermes cannot read the approval bot token or private signing key. Brokers hold only
the public verification key; the approver has no control secret, Docker socket, SSH
profiles, or capability database. All three services have no published ports. The
approval bot setup also creates a separate broker-to-approver request secret, which
cannot sign grants. Execution remains off until token, keys, users, and a feature
are explicitly configured.

- **Sandbox:** short-lived non-root container; only `data/execution-workspace`
  persists; network is off unless the exact operation requests egress; `NET_RAW`
  is separate.
- **SSH:** `./manage.sh add-ssh-profile NAME` creates one profile and requires an
  independently verified host fingerprint. Choose `publickey` (it creates or
  imports a dedicated key) or `password` (it reads the password twice silently
  from your terminal). Host, user, port, credential, and SSH flags are never
  model-controlled. Use `verify-ssh-profile` afterwards; for a key profile,
  install the displayed public key remotely first.
- **Docker:** only `hermes-execution-docker-broker` receives the host socket.
  Hermes, n8n, SSH broker, approver, and sandboxes never receive it. Images must
  be digest-pinned or immutable local IDs. Privileged mode, host namespaces,
  devices, capabilities, ports, and every bind mount appear in the approval.
  Protected stack containers cannot be inspected, logged, changed, or removed by
  name or resolved ID; authority-path binds and the execution-control network are
  denied. Inspect returns a redacted view without environment values, mounts, or
  labels.

SSH passwords are stored only inside the SSH broker's profile directory, which
no other service mounts. They never appear in prompts, Telegram messages, broker
requests, approval summaries, argv, environment values, logs, or audit records.
The approval shows only `authentication: password (broker-held)`. A password
profile authenticates the SSH session and nothing else: keyboard-interactive and
MFA are refused, and `sudo-nopasswd` still means only `sudo -n`. Rotate with
`./manage.sh set-ssh-profile-password NAME`, which also revokes pending
operations and rolls back if verification fails. Removing a password profile
deletes the local copy only — change or disable the remote account password
separately.

Docker socket authority is host-root-equivalent, and an SSH `root` or
`sudo-nopasswd` profile is remote-root-equivalent. Exact approval controls when
an action runs; it does not make an approved action harmless or reversible.
Disablement revokes pending capabilities but does not undo remote commands,
container effects, remove a public key from remote `authorized_keys`, or change
a remote password.

Other management commands:

```bash
./manage.sh add-execution-user ID
./manage.sh remove-execution-user ID
./manage.sh disable-execution all
./manage.sh rotate-execution-broker-secret
./manage.sh set-ssh-profile-password NAME
./manage.sh remove-ssh-profile NAME
./manage.sh purge-execution
./manage.sh set-agent-max-turns 90
```

When Telegram reports `Iteration budget exhausted`, the turn stopped safely.
Send another message to continue from its summary, or raise the bounded budget
with `set-agent-max-turns`; that increases tool/model cost but grants no extra
execution authority.

### 9router web search

The installer writes the aliases expected by compatible 9router search skills:
`NINEROUTER_URL=http://nine-router:20128` (without `/v1`) and a dedicated
`NINEROUTER_KEY`. These aliases provide authenticated access to 9router, but do
not create a search-provider account. Search remains unavailable until an
operator configures a supported provider such as Tavily, Exa, Brave, or Serper
in 9router. Install any web-search skill only through the staged skill review
flow above.

The generated n8n Trigger-mode MCP workflow intentionally exposes only
Calculator, and the hosted-chat workflow has no search tool. Instance-level MCP
is broader and exposes n8n management tools permitted to its token's n8n user.
Clone a managed workflow before adding custom Trigger tools; direct edits to a
stack-owned workflow are detected as drift.

### Backend key

```bash
./manage.sh set-backend-api-key YOUR_KEY
```

Use Open WebUI's Admin Panel for post-install connection and signup changes,
because those settings become persistent database configuration after first
launch.

## Updating

Update all selected services to the current official image tags:

```bash
./manage.sh update
```

This performs `docker compose pull` and recreates containers without deleting
persistent data.

For reproducible production deployments, replace `latest`/`main` in `.env`
with tested version tags before publishing a release.

## Backups

Stop services for a consistent filesystem backup:

```bash
./manage.sh stop
tar --exclude='./.git' -czf ../hermes-stack-backup.tar.gz .env data
./manage.sh start
chmod 600 ../hermes-stack-backup.tar.gz
```

The archive contains secrets, provider data, Telegram sessions, chats, 9router's
SQLite database, and n8n state when selected. Store it as sensitive material.
`N8N_ENCRYPTION_KEY` in `.env` and `data/n8n/` are a required pair: do not restore
or retain either one without the other if encrypted n8n credentials must remain
usable.

Restore by extracting `.env` and `data/` into a fresh clone, then run:

```bash
./manage.sh start
```

## Public access, domains, and Caddy

Telegram polling requires no public route. Keep ports bound to `127.0.0.1` and
use SSH tunnels unless public browser access is necessary.

The installer asks whether to configure Caddy. If selected, it asks separately
whether to publish:

- 9router
- Open WebUI
- n8n, when selected
- the Hermes dashboard, when enabled
- the Hermes API, when enabled

Each selected service receives its own validated domain. The installer writes
`data/caddy/Caddyfile`, adds the `caddy` Compose profile, validates the generated
configuration with Caddy, and changes the relevant public URL to HTTPS.

Example generated configuration:

```caddyfile
9router.example.com {
    encode zstd gzip
    reverse_proxy nine-router:20128
}

chat.example.com {
    encode zstd gzip
    reverse_proxy open-webui:8080
}
```

Before installation, create public DNS `A`/`AAAA` records pointing every domain
to the Linux server. Allow inbound TCP ports 80 and 443 plus UDP 443. Caddy uses
the domain names to obtain and renew certificates automatically. Keep the
application ports blocked from the public internet.

If ports 80 or 443 are already used by an existing reverse proxy, do not enable
the Compose Caddy service. Use `examples/caddy/Caddyfile` as a configuration
reference for the existing proxy instead.

Before publishing Hermes's dashboard or API, review its authentication options
and keep `API_SERVER_KEY` enabled. Do not expose unauthenticated administration
interfaces.

## Install selections

The generated `COMPOSE_PROFILES` value controls active services:

```env
COMPOSE_PROFILES=9router,smart-router,hermes,open-webui,n8n,caddy
```

Valid profile names are:

- `9router`
- `smart-router`
- `hermes`
- `open-webui`
- `n8n`
- `caddy`

Rerun the same curl command, `./install.sh`, or `./manage.sh configure` at any
time. When an installation already exists, the wizard shows its active
components and asks separately whether to reconfigure each installed component
or add each missing component. For example, you can install 9router first and
later add Hermes Agent, Open WebUI, n8n, or Caddy without reinstalling the stack.
It also offers a bind-IP-only path for changing published interfaces safely.
Disabling n8n removes its active containers but preserves `data/n8n/`.

Components you do not select for reconfiguration keep their settings, secrets,
data, and Compose profile. Configuration files receive timestamped backups
before replacement, and generated signing secrets are preserved. The 9router
`INITIAL_PASSWORD` is used only when its database has no saved password, so
rerunning the installer does not reset an existing dashboard account password.

## Manual Compose operation

The management wrapper is optional. Standard commands work:

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f --tail=100
docker compose down
```

Do not use `docker compose down -v`; persistent data uses bind mounts, but this
habit can still be destructive in extended versions of the stack.

## Troubleshooting

Run diagnostics:

```bash
./manage.sh doctor
```

If Hermes cannot reach a bundled 9router, confirm its base URL is:

```text
http://nine-router:20128/v1
```

Inside containers, `localhost` means that container itself. For a service on
the Linux Docker host, use:

```text
http://host.docker.internal:PORT/v1
```

The Compose file adds the Linux `host-gateway` mapping automatically.

If Telegram does not connect:

```bash
./manage.sh logs hermes
```

Verify the BotFather token, numeric allowlist, outbound DNS, and HTTPS access to
Telegram. Do not run two Hermes gateways with the same bot token.

If Open WebUI does not show models, verify the `OpenCode-Free` combo and the
`Open WebUI (hermes-linux-stack)` endpoint key exist in 9router. Then confirm
the API URL and key in Open WebUI Admin Panel → Settings → Connections.

## Upstream documentation

- [9router Docker deployment](https://github.com/decolua/9router/blob/master/DOCKER.md)
- [Hermes Agent Docker guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md)
- [Hermes Telegram guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/telegram.md)
- [Open WebUI quick start](https://docs.openwebui.com/getting-started/quick-start/)
- [Open WebUI environment reference](https://docs.openwebui.com/reference/env-configuration/)
- [n8n Docker installation](https://docs.n8n.io/hosting/installation/docker/)
- [n8n MCP Server Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.mcptrigger/)
- [n8n Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md)
- [Caddy automatic HTTPS](https://caddyserver.com/docs/quick-starts/https)
- [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)

## License

This stack's code is MIT — see `LICENSE`. The bundled n8n image remains subject
to the n8n Sustainable Use License described above.
