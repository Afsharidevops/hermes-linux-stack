# Hermes Linux Stack v0.5.8 — Execution Admin Private-Ingress Hotfix

This hotfix records the server-validated fix for remote Operations Center → Execution & Approvals access.

## Fix

`execution-admin` joins both:

- `execution-control-net` — internal control plane; remains `internal: true`.
- `execution-admin-ingress-net` — dedicated normal bridge used only for the explicitly bound private host port.

Do not attach Smart Router, approver, Docker broker, or SSH broker to the ingress network.

## Verified target behavior

```text
Execution Admin image: afsharidevops/hermes-execution-broker:0.1.3
Private publication:    PRIVATE_IP:8752->8752/tcp
GET /health:            200
OPTIONS preflight:      204
Exact CORS origin:      required
Private Network Access: allowed only for an allowed origin
```

## Images

No image rebuild is required for this hotfix because the runtime image code is unchanged. Continue using:

```text
afsharidevops/hermes-smart-router:0.5.8
afsharidevops/hermes-smart-router:latest
afsharidevops/hermes-execution-broker:0.1.3
```

Do not publish `:v0.5.8` or `:v0.1.3` aliases.

`MANIFEST.sha256` in this hotfix is generated from repository-tracked release files so it verifies correctly from a clean Git clone and does not depend on ignored pytest/cache artifacts.
