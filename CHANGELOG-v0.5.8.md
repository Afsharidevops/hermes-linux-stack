# Hermes Linux Stack — v0.5.8 Changelog

## Release focus

v0.5.8 is the visual-building and operator-UX release for the OmniRoute branch. It keeps the v0.5.7 trust-separated execution design while making browser connectivity failures diagnosable and adding visual studios for workflows, agents, router pipelines, and knowledge pipelines.

## Execution & Approvals reliability

- Execution Broker target advances to `0.1.3`.
- The Operations Center now probes the Execution Admin `/health` endpoint before attempting key authentication. Network/bind/CORS failures are reported separately from key failures.
- Added `./manage.sh configure-execution-admin-browser ORIGIN [PRIVATE_IPV4]` to configure a private bind plus exact browser origin without printing the Execution Admin key.
- Execution Admin CORS preflight supports the Private Network Access response header for explicitly allowed origins.
- The key remains browser-memory-only and is still sent directly from the operator browser to Execution Admin; Smart Router does not receive it.
- Wildcard/public bind shortcuts are intentionally refused by the helper.

## Operations Center redesign

- Reworked dark and light palettes around semantic surface/text/border tokens.
- Reorganized navigation into Observe, Build, Tools, Routing, Access, and System.
- Added Dify-inspired visual interaction patterns without copying Dify branding or assets.
- Added Workflow Studio with draggable nodes, visible edges, node inspector, references, and save/edit lifecycle.
- Added Agent Studio with visible Input → Knowledge → Agent → Tools → Answer path and configuration inspector.
- Added Router Pipeline Studio for conditions, capability/health filters, scoring, load balance, route, retry, fallback, and approval stages.
- Added Knowledge Pipeline Studio and persistent `v58_knowledge_pipelines` registry.
- Added Publish & Monitor workspace that links API, Flight Deck, agent testing, and runtime status.
- Improved Flight Deck light-mode surfaces, sidebar, controls, and status pills.

## Data and API

- Smart Router runtime/control schema marker advances in place to `0.5.8`.
- Compatibility database filename remains `control-v0.5.2.sqlite3`; persistent Operations Center state is upgraded in place.
- New Operations API routes:
  - `GET/POST /control/api/knowledge-pipelines`
  - `PUT/DELETE /control/api/knowledge-pipelines/{id}`
- Knowledge pipeline graph validation accepts only managed ingestion/indexing node types and validates node IDs, edge references, and graph limits.

## Image targets

- Smart Router: `afsharidevops/hermes-smart-router:0.5.8`
- Execution Broker: `afsharidevops/hermes-execution-broker:0.1.3`
- Intended platforms: `linux/amd64`, `linux/arm64`

## Validation performed in packaging environment

- Smart Router pytest suite: 96 passed per branch.
- Execution Admin focused unittest suite: 5 passed per branch.
- `manage.sh` UX tests: passed per branch.
- `bash -n` for `manage.sh` and `install.sh`: passed.
- Python compilation for modified Smart Router UI/control files: passed.
- Operations Center JavaScript syntax (`node --check`): passed.

The broader root Python test discovery also contains environment-dependent tests requiring `ssh-keygen` and a fully usable npm prefix. Those checks could not complete in this packaging environment and should be run in the normal CI/release host before production publication.

## Security invariant

UI convenience must not collapse execution authority into Smart Router. Execution Admin continues to exclude the Ed25519 approval-signing private key, Docker socket, and SSH private credentials, while Smart Router continues to exclude the Execution Admin key and execution approval secrets.
