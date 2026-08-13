# Hermes Linux Stack release process

This document is the current generic release checklist. Historical version-specific command transcripts are archived under `docs/archive/release-commands/`.

## 1. Branch policy

- `main` is the 9router backend branch.
- `hermes-omniroute-linux-stack` is the OmniRoute backend branch.
- Backend-specific installer, Compose, and management logic is intentionally different.
- Shared Smart Router, Execution Broker, stack plugin, and shared-test changes should remain equivalent unless a documented backend-specific reason requires otherwise.

## 2. Before a release

1. Ensure the working tree is clean.
2. Run `bash -n install.sh manage.sh tests/smoke.sh`.
3. Install `smart-router/requirements-dev.txt` into an isolated Python environment and run `./tests/smoke.sh`.
4. Run focused execution/plugin regression tests when those areas changed.
5. Run `sha256sum -c MANIFEST.sha256`.
6. Verify both branches and intentional branch differences before publishing shared images.
7. Back up a real test deployment and perform an in-place upgrade test.

## 3. Versioning

Do not bump `VERSION`, Smart Router package/image versions, or Execution Broker versions merely because development work has started.

For the current preparation state:

- stack/runtime release: `v0.5.8`
- Smart Router image: `afsharidevops/hermes-smart-router:0.5.8`
- Execution Broker image: `afsharidevops/hermes-execution-broker:0.1.3`

The v0.5.9 version bump belongs in the actual v0.5.9 release commit after its acceptance criteria pass.

## 4. Docker publishing policy

Only rebuild an image when files in that image's build context or required build inputs changed.

For Smart Router releases, publish the plain version tag and `latest` after multi-architecture validation. Do not publish a redundant `v<version>` alias.

For Execution Broker, choose a new broker version only when broker source/runtime behavior changes; do not infer a broker version from the stack version.

Never place registry credentials in repository files or command transcripts.

## 5. Git release policy

Do not create a Git release tag as part of routine branch preparation. Create release tags only as an explicit release action after validation.

## 6. Security release gate

A release must preserve the execution trust boundary:

- Smart Router does not receive the Execution Admin key, approval signing private key, Docker socket, or SSH credentials.
- Execution Admin does not receive the approval signing private key, Docker socket, or SSH credentials.
- The approval service receives only the dedicated approval-bot token, signing material, and configured execution-user policy needed for approval.
- Visual workflow edges define orchestration; they do not grant execution authority.
