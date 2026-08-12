# Hermes Smart Router v0.5.7

v0.5.7 extends the v0.5.6 AI infrastructure platform with **Execution & Approvals** administration while retaining the existing routing/RAG/observability/workflow foundations.

## Image

```bash
docker pull afsharidevops/hermes-smart-router:0.5.7
```

Production deployments should pin `0.5.7` (or an immutable digest) rather than relying on `latest`.

## v0.5.7 highlights

- Light/dark Operations Center UI retained.
- Correct reversible Enable/Disable and explicit permanent Delete behavior retained for Agents/Teams/Groups/Skills/Plugins.
- Hybrid lexical/vector RAG + pgvector/reranking retained.
- Full request trace foundations, guardrails, advanced router pipelines, workflows, prompt versions, datasets/evaluations and model catalog retained.
- New **System → Execution & Approvals** UI.
- Separate Execution Admin credential and direct browser connection; Smart Router backend does not store the execution-admin credential.
- Telegram approver users can be managed subject to `TELEGRAM_ALLOWED_USERS`.
- Dedicated execution Telegram bot token can be replaced through a write-only API on the separate admin service.
- Broker/approver health, policy generation, redacted SSH profiles and execution-admin audit are visible.
- Execution broker image target is `afsharidevops/hermes-execution-broker:0.1.2`.

The independent Telegram approver remains the decision-signing boundary. Smart Router does not receive the Ed25519 private signing key, Docker socket, or SSH credentials.
