# Hermes Linux Stack / Smart Router v0.5.2 Plan

## Release goal

Hermes Smart Router v0.5.2 should move the project from a strong self-hosted AI/DevOps stack into a more production-ready, enterprise-capable agent infrastructure platform.

The main goal is **not** to add unrelated features. v0.5.2 should strengthen the capabilities already introduced in v0.5.1 and close the remaining gaps against platforms such as LibreChat + LiteLLM, Dify, and AnythingLLM.

Target outcome:

- `main` branch: Hermes + Smart Router + 9router
- `hermes-omniroute-linux-stack` branch: Hermes + Smart Router + OmniRoute
- Same Smart Router implementation on both branches
- Branch-specific gateway defaults only
- Production-quality authentication, HA, routing reliability, secrets handling, RAG, ACLs, deployment, and benchmarking
- Measurable routing quality/cost evidence

Target score after successful implementation:

```text
Hermes Linux Stack + 9router v0.5.2          9.5+/10
Hermes Linux Stack + OmniRoute v0.5.2        9.5+/10
```

---

# 1. SSO / Enterprise Authentication

## Goal

Add production-grade identity support beyond local users and API keys.

## Required providers

- OIDC
- OAuth2
- LDAP
- SAML 2.0

## Recommended first-class integrations

- Authentik
- Keycloak
- Microsoft Entra ID
- Google Workspace
- GitHub
- Generic OIDC provider

## Required capabilities

- login through external identity provider
- automatic user provisioning
- group/role mapping
- configurable default role
- account disable/revoke
- session expiration
- logout
- external subject/provider mapping
- audit login success/failure
- optional local-login disable
- multiple providers where practical

## Example configuration

```env
SMART_ROUTER_AUTH_MODE=local,oidc

SMART_ROUTER_OIDC_ENABLED=true
SMART_ROUTER_OIDC_ISSUER_URL=https://auth.example.com/application/o/hermes/
SMART_ROUTER_OIDC_CLIENT_ID=hermes-smart-router
SMART_ROUTER_OIDC_CLIENT_SECRET_FILE=/run/secrets/oidc_client_secret
SMART_ROUTER_OIDC_REDIRECT_URI=https://router.example.com/control/auth/callback
```

## Acceptance criteria

- local auth continues to work
- OIDC login works end-to-end
- external groups can map to Hermes roles
- failed logins are audited
- revoked/disabled identities can no longer authenticate
- no plaintext provider secret is required in source code

---

# 2. Production RAG / Knowledge Connectors

## Goal

Turn v0.5.1 knowledge support into a production-quality knowledge layer.

## Required source types

- local files
- Markdown
- text
- PDFs
- Git repositories
- websites
- REST/API documentation
- PostgreSQL
- generic HTTP source

## High-value DevOps connectors

Prioritize:

- GitHub repositories
- GitLab repositories
- Kubernetes manifests
- Helm charts
- Terraform
- Ansible
- Dockerfiles / Compose
- CI/CD files
- runbooks
- Markdown documentation

## Vector database support

Support at least:

- PostgreSQL + pgvector
- Qdrant

Optional later:

- Chroma
- Weaviate
- Milvus

## Required pipeline

```text
Source
  ↓
Loader
  ↓
Parser
  ↓
Chunker
  ↓
Embedding
  ↓
Vector Store
  ↓
Retriever
  ↓
Reranking / filtering
  ↓
Hermes request context
```

## Required features

- collection/knowledge-base management
- re-index
- incremental sync
- deduplication
- source metadata
- file/repository revision tracking
- namespace/project scoping
- ACL-aware retrieval
- configurable chunk size
- configurable embedding model
- retrieval limits
- citations/source references
- deletion cleanup
- ingestion status/error reporting

## Acceptance criteria

- repository knowledge can be added and queried
- ACLs are applied before retrieval
- re-indexing does not duplicate chunks
- deleted sources are removed from retrieval
- retrieval metrics are exposed
- production vector storage is persistent

---

# 3. Kubernetes / Helm Deployment

## Goal

Make Hermes Linux Stack deployable as a real Kubernetes workload, not only Docker Compose.

## Deliverables

```text
deploy/
├── helm/
│   └── hermes-linux-stack/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── templates/
│       └── README.md
└── kubernetes/
    └── examples/
```

## Helm components

Support:

- Smart Router
- Hermes
- 9router or OmniRoute
- Open WebUI
- n8n
- execution broker
- PostgreSQL reference configuration
- Redis reference configuration

## Kubernetes requirements

- Deployments / StatefulSets where appropriate
- Services
- Ingress
- TLS
- ConfigMaps
- Secrets
- PersistentVolumeClaims
- PodDisruptionBudgets
- readiness probes
- liveness probes
- resource requests/limits
- NetworkPolicies
- ServiceAccounts
- securityContext
- optional HorizontalPodAutoscaler
- topology spread / anti-affinity

## Installation target

```bash
helm install hermes ./deploy/helm/hermes-linux-stack \
  --namespace hermes \
  --create-namespace
```

## Acceptance criteria

- Helm template validation passes
- chart deploys on a clean Kubernetes cluster
- Smart Router health/readiness passes
- persistence survives pod restart
- multi-replica Smart Router can run with shared state
- no Docker socket is exposed to the Smart Router pod

---

# 4. Redis Shared State + Tested Multi-Node HA

## Goal

Move from "HA-ready" to tested multi-node operation.

## Redis use cases

- distributed sticky-session state
- rate-limit counters
- virtual-key quotas
- short-lived cache
- provider-health state
- circuit-breaker state
- distributed locks
- optional job/event coordination

## PostgreSQL use cases

Keep durable control-plane state in PostgreSQL:

- users
- roles
- ACLs
- policies
- providers
- routes
- agent profiles
- knowledge metadata
- audit logs
- budget state
- configuration

## Architecture

```text
                  Load Balancer
                  /           \
                 ▼             ▼
          Smart Router A   Smart Router B
                 \             /
                  \           /
                 PostgreSQL + Redis
                       │
                       ▼
                9router / OmniRoute
```

## Required HA tests

- two Smart Router replicas
- concurrent requests
- sticky-session consistency
- rate-limit consistency
- budget consistency
- route update propagation
- provider circuit state propagation
- one router replica killed during load
- Redis restart behavior
- PostgreSQL restart behavior
- gateway restart behavior

## Acceptance criteria

- no conflicting local sticky state
- no duplicate budget counters
- route/config updates become visible across nodes
- one router replica can fail without API outage
- documented recovery behavior exists

---

# 5. Provider Health Scores + Circuit Breakers

## Goal

Make provider reliability a first-class routing input.

## Health score inputs

Track:

- success rate
- error rate
- timeout rate
- average latency
- p95 latency
- p99 latency
- rate-limit responses
- authentication failures
- consecutive failures
- recent recovery success

## Provider state

```text
HEALTHY
DEGRADED
UNHEALTHY
CIRCUIT_OPEN
HALF_OPEN
```

## Circuit breaker example

```text
5 qualifying failures in 60 seconds
        ↓
OPEN circuit
        ↓
stop normal traffic
        ↓
cooldown
        ↓
HALF_OPEN
        ↓
probe traffic
        ↓
success → CLOSED
failure → OPEN
```

## Routing integration

Provider health must become part of route scoring.

Example:

```text
provider_score =
    capability_fit
  + quality_score
  + cost_score
  + latency_score
  + health_score
  + availability_score
```

## Required UI

Control Plane should show:

- provider
- route
- current health
- success rate
- latency
- active circuit
- last failure
- last recovery
- recent fallback count

## Acceptance criteria

- unhealthy providers are automatically avoided
- circuits recover safely
- state works across multiple Smart Router replicas
- health metrics are exposed through Prometheus
- provider failures are visible in audit/observability views

---

# 6. Automatic Quality / Cost Router Learning

## Goal

Evolve Smart Router from learned classification toward measurable outcome-driven routing.

## Training signals

Capture:

- request feature vector
- requested capabilities
- selected tier/profile
- selected provider/model
- latency
- token usage
- cost
- tool success
- execution success
- user feedback
- quality evaluation
- fallback outcome
- final task success

## Learning objective

Select the cheapest/fastest route that still meets:

- capability requirements
- required quality
- reliability floor
- latency target
- policy constraints
- budget constraints

## Conceptual score

```text
score =
    capability_fit * 0.30
  + quality        * 0.25
  + reliability    * 0.15
  + cost           * 0.12
  + latency        * 0.10
  + availability   * 0.08
```

The exact weights must be configurable and should eventually be learned/evaluated.

## Safety requirements

Automatic learning must never bypass:

- hard capability floors
- vision requirements
- tool requirements
- context limits
- policy denies
- ACLs
- execution approval
- administrator route restrictions

## Deployment modes

```text
observe
shadow
recommend
enforce
```

### Observe

Collect outcomes only.

### Shadow

Calculate adaptive route but do not use it.

### Recommend

Show recommended route in UI/API.

### Enforce

Use adaptive route after benchmark/approval thresholds are met.

## Acceptance criteria

- routing-learning data can be exported
- training is offline/reproducible
- learned route decisions are explainable
- rollback to heuristic/calibrated mode is instant
- model artifact integrity is validated
- no automatic production enablement occurs after training

---

# 7. Fine-Grained ACLs

## Goal

Move from role-based access toward resource-level authorization.

## Resource types

ACL support should cover:

- agents
- agent teams
- tools
- plugins
- MCP servers
- knowledge bases
- memories
- routing profiles
- providers
- budgets
- virtual keys
- execution targets
- environments
- audit views

## Permission examples

```text
agents.read
agents.use
agents.manage

knowledge.read
knowledge.write
knowledge.manage

tools.use
tools.manage

providers.read
providers.manage

routing.read
routing.manage

execution.sandbox
execution.docker
execution.ssh
execution.approve

audit.read

budgets.read
budgets.manage
```

## Subject types

- user
- role
- group
- team
- agent
- virtual API key

## Example

```text
Developer Group

Allow:
  agents.use: devops-agent
  knowledge.read: platform-docs
  tools.use: github-read
  execution.sandbox

Deny:
  providers.manage
  routing.manage
  execution.ssh: production
  execution.approve
```

## Acceptance criteria

- API and UI enforce the same permissions
- retrieval cannot access unauthorized knowledge
- denied tool access cannot be bypassed through agent configuration
- ACL changes are audited
- default-deny can be enabled for sensitive resource classes

---

# 8. Secrets Manager Integration

## Goal

Reduce dependency on plaintext `.env` secrets.

## Required secret backends

Implement at least:

- Docker Secrets
- file-based secrets (`*_FILE`)
- HashiCorp Vault

Recommended later:

- 1Password Connect
- AWS Secrets Manager
- Azure Key Vault
- Google Secret Manager
- Kubernetes Secrets / External Secrets

## Secret types

Move support toward external references for:

- OIDC client secrets
- provider API keys
- gateway credentials
- HMAC secrets
- admin bootstrap secrets
- database credentials
- Redis credentials
- SSH credentials
- webhook secrets

## Example

```env
SMART_ROUTER_HMAC_SECRET_FILE=/run/secrets/router_hmac
SMART_ROUTER_ADMIN_API_KEY_FILE=/run/secrets/router_admin
SMART_ROUTER_DATABASE_PASSWORD_FILE=/run/secrets/postgres_password
```

## Vault example

```env
SMART_ROUTER_SECRETS_BACKEND=vault
SMART_ROUTER_VAULT_ADDR=https://vault.example.com
SMART_ROUTER_VAULT_AUTH_METHOD=approle
```

## Acceptance criteria

- secret values are never returned through the control API
- UI masks secret values
- logs never print secrets
- rotation does not require source-code changes
- file/Docker secret loading works in Compose
- Kubernetes secret loading works in Helm deployment

---

# 9. Control Plane UI v2

## Goal

Turn the v0.5.1 panel into a polished operations console.

## Design principles

- fast
- low dependency
- mobile usable
- dark/light support
- clear system status
- minimum clicks for operational tasks
- no raw developer-only views as primary UX

## Main navigation

```text
Overview
Routing
Providers
Models
Agents
Teams
Knowledge
Memory
Tools / MCP
Policies
Users
Groups
ACLs
API Keys
Budgets
Approvals
Executions
Audit
Benchmarks
System
```

## Overview dashboard

Show:

```text
Requests today
Tier distribution
Profile distribution
Cost today
Cost saved
Latency p50/p95
Fallback rate
Provider health
Circuit breaker status
Active users
Active agents
Execution approvals
Knowledge retrieval count
Routing confidence
Capability violations
```

## Routing UI

Allow:

- edit FAST/STANDARD/STRONG/CODING/VISION mappings
- inspect live `/v1/models`
- show route health
- show selected provider/model
- test a route
- compare cost/latency/quality
- enable/disable profile
- rollback configuration

## Benchmark UI

Show:

- dataset
- run date
- router version
- routing accuracy
- false-fast rate
- capability violations
- cost
- savings
- latency
- tier/profile distribution
- per-category quality
- baseline comparison

## Acceptance criteria

- major admin operations can be completed without editing DB files
- dangerous actions require confirmation
- control API errors are clearly surfaced
- ACLs determine which UI sections/actions are visible
- health/fallback/circuit information is understandable without reading logs

---

# 10. Real-World Benchmark Program

## Goal

Make v0.5.2 evidence-driven.

This is the highest-priority proof milestone.

Do not publish fabricated or synthetic "production" claims.

## Dataset target

Target:

```text
25,000+ representative requests
```

Minimum public benchmark target:

```text
10,000 representative requests
```

Dataset categories should include:

- simple chat
- factual Q&A
- summarization
- coding
- debugging
- architecture
- DevOps
- Terraform
- Kubernetes
- Docker
- security analysis
- long-context
- tool requests
- vision requests
- multi-step reasoning
- RAG requests
- agent/tool workloads

## Data split

Use:

```text
train
validation
held-out test
```

The final public score must come from held-out data.

## Required baselines

Compare:

- fast-only
- standard-only
- strong-only
- random routing
- heuristic Smart Router
- calibrated Smart Router
- learned Smart Router
- adaptive/outcome Smart Router

## Required metrics

### Routing quality

- exact routing accuracy
- false-fast rate
- under-routing rate
- over-routing rate
- capability-violation rate
- route confusion matrix
- per-category accuracy

### Quality

- task success
- evaluator score
- human/user feedback where available
- quality retention vs strong-only

### Cost

- total cost
- cost/request
- token usage
- cached-token usage
- strong-only baseline cost
- measured savings
- pricing coverage

### Performance

- end-to-end latency
- TTFT
- p50
- p95
- p99
- timeout rate

### Reliability

- provider failure rate
- fallback count
- fallback success
- circuit-breaker activations
- recovery rate

## Target report format

```text
Hermes Smart Router v0.5.2 Benchmark
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Production-like requests        25,000

Routing accuracy                 >= 97%
False-fast rate                  <= 1%
Capability violations              0%

FAST                              ~55%
STANDARD                          ~29%
STRONG                            ~12%
CODING                             ~3%
VISION                             ~1%

Strong-only cost                 $XXX.XX
Hermes routed cost               $XXX.XX

Measured savings                 >= 35%

Average latency reduction        >= 20%
Provider fallback success        >= 99%
```

These are **release targets**, not claims. Actual published values must come from measured results.

## Public benchmark artifacts

```text
benchmark/
├── datasets/
├── configs/
├── results/
├── reports/
├── figures/
├── run.py
├── score.py
└── README.md
```

Generate:

- `summary.json`
- `report.md`
- `results.csv`
- confusion matrix
- tier distribution
- profile distribution
- cost comparison
- latency comparison
- quality vs cost plot
- provider reliability report
- environment/version manifest

## Reproducibility

Every published benchmark should record:

- Smart Router git commit
- Smart Router version
- gateway
- model/route mapping
- provider pricing snapshot
- test date
- dataset version
- benchmark configuration
- machine/environment details
- random seed where relevant

---

# 11. OmniRoute Tier Profiles

## Goal

Remove the remaining architectural weakness in the OmniRoute branch.

v0.5.1 safe defaults may still use:

```text
FAST      → auto
STANDARD  → auto
STRONG    → auto
CODING    → auto
VISION    → auto
```

v0.5.2 should support real configured route profiles.

Target:

```text
FAST
  ↓
OmniRoute low-latency / low-cost pool

STANDARD
  ↓
OmniRoute balanced pool

STRONG
  ↓
OmniRoute reasoning pool

CODING
  ↓
OmniRoute coding pool

VISION
  ↓
OmniRoute multimodal pool
```

## Important rule

Do not hard-code invented OmniRoute IDs.

Required workflow:

```text
Smart Router Control Plane
        ↓
Discover /v1/models
        ↓
Administrator chooses real route IDs
        ↓
Validate capability
        ↓
Save profile
        ↓
Benchmark
```

## Acceptance criteria

- all profiles can be mapped independently
- live model discovery works
- invalid route ID cannot silently become active
- route mapping can be tested before save
- route changes are audited
- profile mapping is shared across HA replicas

---

# 12. Provider Quality Registry

## Goal

Track provider/model outcomes over time.

## Store per model/route

- coding success
- reasoning quality
- RAG quality
- tool success
- vision success
- cost/request
- latency
- reliability
- failure rate
- user feedback
- benchmark score

Example:

```text
Model A
  Coding quality: 94%
  Avg cost:       $0.031
  p95 latency:     2.2s
  Reliability:     99.8%

Model B
  Coding quality: 90%
  Avg cost:       $0.012
  p95 latency:     1.1s
  Reliability:     99.4%
```

Use this registry as an input to adaptive routing.

---

# 13. Feedback / Outcome Capture

## Goal

Create the data needed for automatic router learning.

## Capture

- thumbs up/down
- explicit rating
- task completed/failed
- tool succeeded/failed
- execution succeeded/failed
- human correction
- fallback required
- user manually changed tier
- administrator routing override

## Privacy

Do not require storing raw prompts.

Prefer:

- derived features
- hashes/IDs
- task category
- route metadata
- outcome signals

Raw content storage must be opt-in.

---

# 14. Security Hardening

## Required v0.5.2 security review

Add tests for:

- RBAC bypass
- ACL bypass
- virtual-key privilege escalation
- route override bypass
- knowledge retrieval authorization
- secret leakage
- audit tampering
- SSO account mapping
- CSRF/session handling
- SSRF in RAG connectors
- malicious URLs
- unsafe plugin endpoints
- SQL injection
- shell injection
- path traversal
- malicious document ingestion

## CI security

Run:

- dependency scanning
- secret scanning
- container scanning
- static analysis

Recommended tools:

```text
Trivy
Gitleaks
Semgrep
Dependabot/Renovate
Grype (optional)
```

---

# 15. Observability Upgrade

## Goal

Make all v0.5.2 features measurable.

## Prometheus metrics

Add metrics for:

- SSO login success/failure
- auth latency
- ACL deny count
- RAG retrieval latency
- RAG hit count
- vector search latency
- provider health score
- circuit breaker state
- fallback attempts/success
- Redis availability
- PostgreSQL availability
- router replica ID
- adaptive router mode
- benchmark metrics
- execution approvals
- secret backend errors

## Optional Grafana package

Provide example dashboards:

```text
grafana/
├── smart-router-overview.json
├── provider-health.json
├── routing-quality.json
├── cost-dashboard.json
└── execution-security.json
```

---

# 16. Branch Strategy

Keep Smart Router source identical across both branches whenever possible.

## main

```text
Hermes
  ↓
Smart Router v0.5.2
  ↓
9router
  ↓
Providers
```

Default route concepts:

```text
FAST      → combo-fast
STANDARD  → combo-standard
STRONG    → combo-strong
CODING    → configured coding route
VISION    → configured vision route
```

## hermes-omniroute-linux-stack

```text
Hermes
  ↓
Smart Router v0.5.2
  ↓
OmniRoute
  ↓
Providers
```

Profiles should use discovered/configured real OmniRoute routes.

## Rule

Branch-specific code should be minimized.

Prefer:

```text
same code
+
different configuration
```

instead of maintaining two Smart Router implementations.

---

# 17. Backward Compatibility

v0.5.2 must not break existing v0.5.1 clients.

Required compatibility:

- OpenAI-compatible `/v1` behavior
- `FAST / STANDARD / STRONG`
- existing dashboard
- existing control panel data where possible
- existing SQLite single-node mode
- existing Docker Compose mode
- existing virtual keys
- existing local auth
- existing provider profiles

New enterprise features should remain optional.

A simple single-node install must not require:

- Kubernetes
- Redis
- PostgreSQL
- SSO
- external vector DB

unless that deployment mode explicitly enables them.

---

# 18. Database Migration

Add explicit schema migration support.

Recommended:

```text
Alembic
```

Required:

- v0.5.1 → v0.5.2 migration
- rollback guidance
- automatic backup before destructive migration
- migration version table
- migration tests for SQLite and PostgreSQL

No release should require users to delete the control database.

---

# 19. Backup / Restore

v0.5.2 should include:

```bash
./manage.sh backup
./manage.sh restore <backup>
```

Backup:

- Smart Router DB
- PostgreSQL metadata
- routing profiles
- users/groups/ACLs
- virtual keys metadata
- policies
- knowledge metadata
- agent profiles
- benchmark configs
- n8n
- Open WebUI config
- stack state

Secrets should be handled carefully and documented separately.

---

# 20. Doctor / Diagnostics

Add:

```bash
./manage.sh doctor
```

Example:

```text
Hermes Linux Stack Doctor

Docker                     OK
Smart Router 0.5.2         OK
Control DB                 OK
Redis                      OK
PostgreSQL                 OK
9router                    OK
OmniRoute                  N/A
Open WebUI                 OK
n8n                        OK
Execution Broker           OK

Provider health
OpenAI                     OK
Anthropic                  DEGRADED
Gemini                     OK

Routing
FAST                       OK
STANDARD                   OK
STRONG                     OK
CODING                     OK
VISION                     OK

Auth
Local                      OK
OIDC                       OK

Knowledge
Vector DB                  OK
Embedding                  OK
```

This should become the first troubleshooting command documented for users.

---

# 21. Release Phases

## Phase 1 — Reliability foundation

Implement first:

1. provider health scoring
2. circuit breakers
3. Redis shared state
4. PostgreSQL migration hardening
5. DB migrations
6. HA integration tests

Target score:

```text
~9.3–9.4
```

---

## Phase 2 — Enterprise identity and authorization

Implement:

1. OIDC
2. group mapping
3. LDAP
4. SAML
5. fine-grained ACLs
6. secrets backend abstraction

Target:

```text
~9.4–9.5
```

---

## Phase 3 — Production knowledge

Implement:

1. pgvector
2. Qdrant
3. Git connector
4. website connector
5. PDF/file pipeline
6. ACL-aware retrieval
7. source sync

Target:

```text
~9.5
```

---

## Phase 4 — Router intelligence

Implement:

1. outcome capture
2. provider quality registry
3. adaptive quality/cost scoring
4. shadow mode
5. recommend mode
6. benchmark gate before enforce mode

Target:

```text
9.5+
```

---

## Phase 5 — Deployment and UX

Implement:

1. Helm chart
2. Kubernetes examples
3. Control Plane UI v2
4. Grafana dashboards
5. doctor command
6. backup/restore

---

## Phase 6 — Evidence / benchmark release gate

Run and publish the real benchmark.

Do not mark v0.5.2 production-ready until benchmark and reliability gates are met.

---

# 22. v0.5.2 Release Gates

All must pass.

## Code

```text
[ ] full unit test suite passes
[ ] integration tests pass
[ ] smoke tests pass
[ ] no critical static-analysis findings
[ ] no known secret leaks
```

## Docker

```text
[ ] linux/amd64 image passes
[ ] linux/arm64 image passes
[ ] image reports version 0.5.2
[ ] SBOM generated
[ ] provenance generated
```

## Compose

```text
[ ] main / 9router stack passes
[ ] OmniRoute stack passes
[ ] upgrade from v0.5.1 passes
[ ] rollback documentation exists
```

## HA

```text
[ ] PostgreSQL shared state tested
[ ] Redis shared state tested
[ ] two Smart Router replicas tested
[ ] replica failure tested
[ ] gateway failure tested
[ ] provider circuit breaker tested
```

## Authentication

```text
[ ] local login
[ ] OIDC login
[ ] role mapping
[ ] ACL enforcement
[ ] virtual-key enforcement
[ ] audit events
```

## RAG

```text
[ ] Git repository ingestion
[ ] file/PDF ingestion
[ ] vector retrieval
[ ] ACL-aware retrieval
[ ] sync/update
[ ] delete cleanup
```

## Routing

```text
[ ] FAST
[ ] STANDARD
[ ] STRONG
[ ] CODING
[ ] VISION
[ ] capability floors
[ ] route-profile validation
[ ] provider health routing
[ ] circuit breakers
```

## Benchmark

```text
[ ] representative held-out dataset
[ ] >=10,000 requests minimum
[ ] routing accuracy measured
[ ] false-fast measured
[ ] capability violations measured
[ ] real cost measured
[ ] strong-only baseline measured
[ ] latency measured
[ ] fallback reliability measured
[ ] report is reproducible
```

---

# 23. Target Benchmark Goals

These are **engineering targets**, not claims.

```text
Routing accuracy              >= 97%
False-fast rate               <= 1%
Capability violations          0%
Provider fallback success     >= 99%
Usage coverage                >= 98%
Pricing coverage              >= 98%
Measured cost savings         >= 35%
Average latency improvement   >= 20%
```

If real results are lower, publish the real results and improve the router rather than modifying the benchmark to fit the target.

---

# 24. Desired Competitive Position

After v0.5.2, Hermes should be able to credibly position itself as:

> A self-hosted AI agent infrastructure platform that combines capability-aware model routing, provider delivery, enterprise identity, governed knowledge, secure Linux execution, human approval, measurable cost optimization, and production observability.

The differentiating architecture should remain:

```text
                      POLICY / INTELLIGENCE
                               │
                        Smart Router
                               │
            capability / quality / cost / safety
                               │
                               ▼
                       DELIVERY PLANE
                         9router / OmniRoute
                               │
                               ▼
                         Providers / Models


Hermes Agent
     │
     ▼
Execution Policy
     │
     ▼
Human Approval
     │
     ▼
Sandbox / Docker / SSH
```

Do not lose this separation while adding enterprise features.

---

# 25. Expected Competitive Score After v0.5.2

If all major release gates are met and the benchmark proves the routing claims:

```text
Hermes + 9router v0.5.2                   9.5–9.6 / 10

Hermes + OmniRoute v0.5.2
with real capability route profiles       9.5–9.7 / 10
```

Main improvements over v0.5.1:

```text
Enterprise authentication      ↑
Fine-grained authorization     ↑
RAG maturity                   ↑
HA / scaling                   ↑
Provider reliability           ↑
Adaptive routing               ↑
Secrets security               ↑
Control Plane UX               ↑
Kubernetes deployment          ↑
Benchmark credibility          ↑
```

---

# 26. Implementation Priority Summary

If development time is limited, build in this exact order:

```text
P0
1. Provider health + circuit breakers
2. Redis shared state
3. HA integration tests
4. DB migrations
5. OIDC
6. Fine-grained ACLs
7. Secrets backend abstraction

P1
8. pgvector + Qdrant
9. Git repository knowledge
10. ACL-aware RAG
11. Outcome/feedback capture
12. Provider quality registry
13. Adaptive router shadow mode

P2
14. LDAP / SAML
15. Helm/Kubernetes
16. Control Plane UI v2
17. Backup/restore
18. Doctor command
19. Grafana dashboards

RELEASE GATE
20. 10k–25k representative benchmark
21. Public reproducible report
22. Upgrade test from v0.5.1
23. Multi-node failure tests
```

---

# 27. Definition of Done

Hermes Smart Router v0.5.2 is complete only when:

```text
The code works.
The upgrade works.
The two branches work.
The Docker image works.
The HA mode works.
The identity layer works.
The ACL layer works.
The knowledge layer works.
The routing still stays capability-safe.
The provider-failure behavior is tested.
The benchmark is reproducible.
The cost/quality claims are measured rather than assumed.
```

The goal of v0.5.2 is not simply to contain more features.

The goal is to make Hermes Linux Stack **measurably safer, more reliable, more enterprise-ready, and demonstrably more efficient** than v0.5.1.
