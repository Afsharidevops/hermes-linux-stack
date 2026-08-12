# Hermes Smart Router 0.5.8

Hermes Smart Router is the routing, governance, Operations Center, and observability layer for Hermes Linux Stack. This `9router` package routes OpenAI-compatible traffic through the configured upstream gateway while adding automatic model selection, access controls, budgets, guardrails, Knowledge/RAG, agents, teams, workflow registries, visual studios, and measured Flight Deck telemetry.

## Image

```text
afsharidevops/hermes-smart-router:0.5.8
```

Recommended platforms after publication: `linux/amd64`, `linux/arm64`.

## v0.5.8 highlights

- Visual Workflow Studio.
- Visual Agent Studio.
- Visual Router Pipeline Studio.
- Visual Knowledge Pipeline Studio.
- Reorganized Operations Center navigation.
- Improved light/dark theme behavior.
- Better Execution & Approvals browser diagnostics while preserving the separate Execution Admin boundary.
- Hybrid lexical/vector RAG and PostgreSQL/pgvector foundations retained.
- Existing ACL, budgets, guardrails, traces, model catalog, prompts, evaluations, Skills, Plugins, and Marketplace foundations retained.

## Ports / URLs

With host port `8787` mapped to container `8080`:

- OpenAI-compatible API: `/v1`
- Health: `/health`
- Readiness: `/ready`
- Router info: `/router/info`
- Metrics: `/metrics`
- Flight Deck: `/dashboard`
- Operations Center: `/control/`

## Persistence

Persist `/data`. The compatibility Operations Center SQLite filename may remain `control-v0.5.2.sqlite3`; v0.5.8 upgrades the schema marker in place. Do not delete the persistent data directory during a normal upgrade.

## Authentication

Production deployments should use `SMART_ROUTER_REQUIRE_AUTH=true`, strong client/admin credentials, TLS at the ingress/reverse proxy, private administration access, and least-privilege ACLs.

## Execution security

Execution Admin is a separate service and credential boundary. Smart Router must not receive the Execution Admin key, dedicated execution approval-bot token, approval private signing key, Docker socket, or SSH private credentials. Browser convenience in v0.5.8 does not change that design.

## Production guidance

Pin the release tag or immutable digest, back up state before upgrades, verify provider connectivity and request traces, use real embedding infrastructure plus PostgreSQL/pgvector for production semantic RAG, and validate HA/failover in your own environment before making HA claims.
