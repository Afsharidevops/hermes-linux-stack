# Hermes Linux Stack v0.5.6 — Platform Foundations

v0.5.6 advances Hermes from an operator-focused Smart Router into a broader self-hosted AI infrastructure platform while preserving the existing `control-v0.5.2.sqlite3` compatibility filename and explicit-model pass-through behavior.

## Major additions

- Light/dark themes in Hermes Operations Center and Flight Deck, persisted in the browser.
- Consistent lifecycle UX: Agents, Teams, and Groups use reversible Enable/Disable controls; permanent deletion is a separate destructive action. Group purge protects ACL references unless explicit cascade deletion is requested. Plugins and Skills have explicit enable/disable and permanent removal controls.
- Hybrid Knowledge/RAG with lexical + vector retrieval, embedding indexing, score fusion/reranking, PostgreSQL `pgvector` acceleration where available, and a deterministic portable vector fallback for offline/development use.
- Full request trace records for request/auth/authorization/guardrails/RAG/classification/routing/retry/fallback/result stages, visible in Flight Deck and Operations Center.
- Guardrail engine foundations for prompt-injection indicators, PII indicators, content deny rules, tool allow-lists, and high-risk tool confirmation policy. Modes: `off`, `audit`, `enforce`.
- Advanced router pipeline definitions with conditions, route stages, load balancing, retries, and fallback model chains.
- Workflow graph registry and visual workflow preview for Agent/Team orchestration.
- Prompt registry with immutable versions, activation/rollback, notes, and history.
- Evaluation datasets, dataset items, and A/B evaluation-run definitions.
- Model catalog synchronized from the upstream `/models` endpoint with capability/context/pricing/health/latency metadata where available.
- Plugin/Skill marketplace view built on the safe catalog/registry model.
- First-run Operations Center onboarding flow.
- PostgreSQL + pgvector + Redis + two-router HA Compose example and smoke/load-test tooling.
- Enterprise identity readiness page. OIDC remains the completed interactive login path; LDAP/SAML/SCIM are connector/provisioning foundations and require deployment-specific integration before production use.
- Static public-docs starter with release screenshots and demo deployment example.

## Compatibility and non-regression rules

- `model=auto` enters Smart Router automatic selection.
- Explicit upstream model IDs pass through unchanged.
- Existing SQLite data is upgraded in place; the compatibility DB filename is not renamed simply because the software version changes.
- Catalog plugin installation does not download/execute arbitrary untrusted code. Lifecycle state, permissions metadata, endpoint configuration, and safe registration remain controlled by the operator.

## Production notes

For real semantic vector RAG, configure an embeddings endpoint and use PostgreSQL with the `vector` extension. The built-in deterministic embedding fallback is useful for tests/offline operation but is not a substitute for a production embedding model. Run the HA smoke and load-test scripts against your own infrastructure before calling a deployment production-HA certified.
