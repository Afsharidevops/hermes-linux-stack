# Hermes Operations Center User Guide — v0.5.6

Open `/control/` on your Smart Router address. Use the top-bar theme control to switch light/dark mode.

## Resource lifecycle

For Agents, Teams, Groups, Plugins, Skills, and Routes, **Enable/Disable** changes operational state and is reversible. **Delete/Permanent Delete/Uninstall** removes the record. Group permanent deletion is refused while ACL rules reference the Group unless an administrator explicitly chooses cascade deletion.

## Traces

**Observe → Traces** shows per-request stages. Trace records are intentionally structured and redact prompt/auth-like fields instead of storing raw secrets. Flight Deck also shows recent request trace groups.

## Knowledge and vector RAG

**Intelligence → Knowledge** reports the retrieval mode, embedding provider, dimensions and pgvector status. `hybrid` retrieval combines lexical and vector candidates and reranks the merged set. PostgreSQL + pgvector is recommended for production; SQLite remains supported using the portable vector path.

## Routing pipelines

**Routing → Router Pipelines** stores ordered pipeline definitions. Supported stage concepts are condition, route, load balance, retry and fallback. Keep a deterministic default route available so malformed/overly selective conditions cannot strand traffic.

## Guardrails

**Routing → Guardrails** displays the active mode and custom rules. `audit` records findings without blocking; `enforce` can reject configured high-risk findings. Treat PII detection as an indicator requiring policy review, not as perfect classification.

## Workflows and prompts

**Intelligence → Workflows** provides a graph registry/visual preview for Agent and Team flows. **Prompts** keeps version history and lets an operator activate an earlier version as rollback.

## Evaluations

**Intelligence → Evaluations** stores datasets, expected outputs and A/B evaluation run definitions. v0.5.6 provides the data/control-plane foundation; connect your benchmark executor/judge policy to populate quality metrics for production comparisons.

## Model Catalog

**Routing → Model Catalog** synchronizes the upstream model list and records capability/context/pricing/health metadata when the upstream exposes it. Validate provider pricing rather than assuming catalog defaults.

## Onboarding and identity

**System → Onboarding** tracks upstream, authentication, model discovery, routes, pricing, administrator, Knowledge, first Agent and test-request steps. **Access → Identity** shows OIDC plus LDAP/SAML/SCIM readiness. OIDC is the completed interactive login path in v0.5.6; LDAP/SAML/SCIM require deployment-specific connectors and integration tests.

## HA

Use `smart-router/compose-ha-v0.5.6.example.yml` as a reference for PostgreSQL/pgvector + Redis + two Smart Router replicas behind a load balancer, then run `scripts/ha-smoke-v0.5.6.sh` and the load test before production rollout.
