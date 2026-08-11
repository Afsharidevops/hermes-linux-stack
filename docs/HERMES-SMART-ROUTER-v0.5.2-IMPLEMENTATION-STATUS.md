# Hermes Smart Router v0.5.2 — Implementation Status

This package implements the **v0.5.2 reliability/security foundation** while preserving the v0.5.1 OpenAI-compatible data-plane behavior. It does not claim that every long-range item in `plan5.2.md` is production-complete.

## Implemented in this package

- Shared Smart Router v0.5.2 source on both gateway branches.
- Fixed `./manage.sh router-info`; `/router/info` is the canonical endpoint and `/router/policy` remains as a compatibility alias.
- Installer rotates empty and `CHANGE_ME*` bootstrap/admin/database/client secrets instead of accepting predictable placeholders.
- Docker execution GID is detected from `/var/run/docker.sock` when available; Docker execution enablement checks the host GID rather than assuming `999`.
- Smart Router client authentication is enabled by default; the installer synchronizes the generated client key to Hermes and Open WebUI.
- Control-plane authentication is enabled by default and Open WebUI signup is disabled by default.
- Mutable application image tags remain the operator default (`latest`, and `main` for Open WebUI), but every application image repository/tag is overrideable from `.env` without editing Compose.
- Provider/model health tracking, health scoring, circuit states, fallback accounting, and Prometheus metrics.
- PostgreSQL-backed control-plane state and Redis-backed shared quota/rate state.
- Redis-backed sticky-session routing in HA mode (`SMART_ROUTER_STICKY_BACKEND=auto|redis|sqlite`), with SQLite preserved for simple single-node deployments.
- OIDC login foundation with discovery, authorization-code exchange, external subject mapping, group-to-role mapping, optional automatic provisioning, session revocation checks, and optional local-login disable.
- Fine-grained ACL foundation with deny-wins rules and knowledge-resource authorization hooks.
- `*_FILE` secret loading for supported Smart Router credentials and redacted control-plane status output.
- Knowledge-source hash/deduplication, replace/update semantics, source deletion cleanup, and metadata foundations.
- Outcome capture and provider-quality registry foundations for later offline/adaptive routing work.
- `doctor`, backup/restore, update/rollback, image lock/verify, and execution-approval token management through `manage.sh`/stack operations.
- Restored the approval-gated execution and exact-version package-policy plugin implementations that were placeholders in the uploaded package; operations fail closed outside the interactive/manual-approval context.
- HA Compose reference for PostgreSQL + Redis + multi-replica Smart Router.
- Kubernetes/Helm **foundation** for the HA Smart Router control/data layer, including Services, stateful dependencies, PDB, NetworkPolicy, security contexts, and optional HPA.
- CI parity gate for the shared Smart Router image and v0.5.2 security scanning workflow.

## Intentionally still open / not claimed complete

The following plan items require substantial integration, external infrastructure, or measured evidence and are **not** represented as complete here:

- LDAP and SAML 2.0 production integrations.
- HashiCorp Vault and cloud secret-manager backends beyond file/Docker/Kubernetes secret patterns.
- Full production RAG connectors plus pgvector/Qdrant ingestion/retrieval pipeline.
- Full-stack Helm coverage for Hermes, gateway, Open WebUI, n8n, execution broker, Ingress/TLS, and all persistence modes.
- Full Control Plane UI v2 UX across every resource class.
- Formal Alembic migration history/rollback chain for every schema transition.
- Complete Grafana dashboard package.
- Destructive multi-node failover certification on a real cluster.
- 10k–25k representative held-out benchmark and any resulting routing quality/cost claims.
- Automatic production enforcement of learned routing. Adaptive/outcome data is a foundation only; heuristic/capability safety remains authoritative.

## Release truthfulness

The target scores and benchmark numbers in `plan5.2.md` remain **engineering targets, not release claims**. Production-ready status should only be applied after the external HA, security, upgrade, Kubernetes, and real benchmark gates in the plan are actually executed and published.
