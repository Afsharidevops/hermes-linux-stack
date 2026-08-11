# Smart Router v0.5.2 install/manage synchronization audit

Branch: `hermes-omniroute-linux-stack`  
Upstream gateway: `OmniRoute`

## Core v0.5.2 features exposed by `install.sh`

- Smart Router image repository/tag (`SMART_ROUTER_IMAGE_REPOSITORY`, `SMART_ROUTER_IMAGE_TAG`)
- Safe bind address and HTTP port (`SMART_ROUTER_BIND_IP`, `SMART_ROUTER_PORT`)
- `observe` / `route` semantics matching the actual `model=auto` path
- `heuristic`, `calibrated`, and `learned` policies with artifact checks
- optional `auto-fast`, `auto-standard`, `auto-strong` tier overrides
- measured telemetry dashboard (`/dashboard`)
- v0.5.2 Control Plane (`/control/`) and authentication requirement
- provider/model health registry and circuit-breaker fallback
- fast/standard/strong/coding/vision route-profile defaults
- generated HMAC, client, admin API, and bootstrap-admin secrets without rotating existing values

## v0.5.2 features surfaced by `manage.sh`

- router runtime/status and `/router/info`
- dashboard/control/API URLs and deliberate secret reveal
- authenticated dashboard telemetry summary
- dynamic Control Plane route profiles
- provider/model health and circuit state
- Control Plane system state
- router mode and policy changes
- calibration, report, and replay tools
- existing health, version, backup/restore, rollback, and image-lock operations

## Features intentionally managed primarily in the Control Plane UI/API

Users/RBAC, virtual API keys, budgets, policies, knowledge, memory, agents, teams, plugins, ACLs, audit events, outcomes, and provider discovery are first-class Control Plane resources. The shell manager provides access/status helpers rather than duplicating every CRUD operation.

## Advanced settings preserved rather than forced by the easy installer

OIDC/SSO and Redis-backed HA require external infrastructure. Their v0.5.2 environment settings are preserved across reconfiguration and remain available in `.env`/Compose. PostgreSQL/Redis secrets and file-secret (`*_FILE`) options are also retained.

## Routing semantics

Smart Router automatic policy applies to `model=auto`. Tier aliases are optional overrides. Explicit upstream model names pass through without automatic tier selection. `observe` records/evaluates the automatic decision but uses the observe model; `route` applies the selected route profile. The route-profile names fast/standard/strong/coding/vision are Smart Router control-plane concepts, not Docker image versions.
