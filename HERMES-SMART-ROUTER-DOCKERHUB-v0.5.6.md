# Hermes Smart Router v0.5.6

Intelligent self-hosted OpenAI-compatible routing with hybrid/vector RAG, full request traces, guardrail foundations, advanced routing pipelines, operational lifecycle controls, prompt/workflow/evaluation registries, and HA examples.

```bash
docker pull afsharidevops/hermes-smart-router:0.5.6
```

Production deployments should pin `0.5.6` (or an image digest) rather than relying on `latest`.

v0.5.6 keeps `model=auto` for automatic Smart Router selection and preserves explicit upstream model pass-through. Its Operations schema upgrades in place while retaining the default compatibility filename `control-v0.5.2.sqlite3`.

For production vector RAG use PostgreSQL/pgvector plus a real embeddings endpoint. OIDC is the completed interactive enterprise login path; LDAP/SAML/SCIM are readiness/connector foundations in this release rather than claimed production-complete integrations.
