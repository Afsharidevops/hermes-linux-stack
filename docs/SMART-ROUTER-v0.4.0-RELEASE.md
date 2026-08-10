# Smart Router v0.4.0 release checklist

Smart Router v0.4.0 is the shared router artifact used by the 9router (`main`) and OmniRoute (`hermes-omniroute-linux-stack`) stacks. The canonical Docker release source is **`main`**. The release workflow refuses to publish while the shared `smart-router/` implementation differs between those two remote branches.

## Release hardening in v0.4.0

- RouteLLM-style cost/quality benchmark reports and plots, with explicit measured-quality vs routing-proxy modes.
- CI gates for minimum dataset size, quality retention, false-fast rate, and cost ratio.
- Conservative context-capability safety factor (`SMART_ROUTER_CONTEXT_TOKEN_SAFETY_FACTOR`, default `1.15`).
- Client tier overrides are disabled by default (`SMART_ROUTER_ALLOW_TIER_OVERRIDES=false`). This protects cost policy from ordinary API clients using `auto-fast`/`auto-standard`/`auto-strong` or `X-Router-Tier`.
- Removed the unused `SMART_ROUTER_FAIL_OPEN_MODEL` configuration. Learned-policy failures continue to use the explicit learned heuristic/calibrated fallback path.
- Docker publication now validates the package version, runs tests and benchmark smoke checks before login/push, verifies branch parity, publishes consistent tags, and inspects the resulting multi-platform image.
- Smart Router policy/model artifact defaults move from policy generation 3 to 4 (`learned-v4.*`, `observations-v4.jsonl`). Existing v3 learned artifacts can still be selected explicitly with the file environment variables if compatible with the current feature schema.

## Pre-release

```bash
git fetch origin --prune
git switch main
git pull --ff-only origin main

git diff --exit-code \
  origin/main..origin/hermes-omniroute-linux-stack \
  -- smart-router/

python3 -m venv ~/.venvs/hermes-smart-router-v040
source ~/.venvs/hermes-smart-router-v040/bin/activate
python -m pip install --upgrade pip
python -m pip install -e './smart-router[dev,bench]'
python -m pytest smart-router/tests

smart-router-benchmark \
  smart-router/examples/benchmark-synthetic-v0.4.0.jsonl \
  --output-dir /tmp/hermes-smart-router-v040-benchmark-smoke \
  --cost-config smart-router/examples/benchmark-costs-normalized.json \
  --synthetic \
  --min-rows 200
```

The synthetic command validates the benchmark machinery only. It is **not** release performance evidence.

## Real benchmark gate

Use your own held-out workload before making public cost/quality claims. Example:

```bash
smart-router-benchmark benchmarks/release-v0.4.0.jsonl \
  --output-dir benchmark-output/v0.4.0 \
  --cost-config benchmarks/costs-production.json \
  --token-weighted-cost \
  --min-rows 1000 \
  --require-measured-quality \
  --min-quality-retention 0.95 \
  --max-false-fast-rate 0.01 \
  --max-cost-ratio 0.75
```

Choose gates that match your actual SLOs; the values above are examples, not claims about current Hermes performance.

## Manual multi-arch build/push

After both branches are pushed and parity is clean:

```bash
docker login -u afsharidevops

docker buildx build \
  --builder hermes-builder \
  --platform linux/amd64,linux/arm64 \
  --file smart-router/Dockerfile \
  --tag afsharidevops/hermes-smart-router:0.4.0 \
  --tag afsharidevops/hermes-smart-router:v0.4.0 \
  --tag afsharidevops/hermes-smart-router:latest \
  --provenance=mode=max \
  --sbom=true \
  --push \
  smart-router
```

Verify:

```bash
docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.4.0
docker buildx imagetools inspect afsharidevops/hermes-smart-router:v0.4.0
docker buildx imagetools inspect afsharidevops/hermes-smart-router:latest
```

The `0.4.0` image must contain both `linux/amd64` and `linux/arm64` manifests.

## Canonical GitHub release

Once both branches contain the identical shared router:

```bash
git switch main
git pull --ff-only origin main
git fetch origin hermes-omniroute-linux-stack

git diff --exit-code \
  origin/main..origin/hermes-omniroute-linux-stack \
  -- smart-router/

git tag -a smart-router-v0.4.0 -m 'Hermes Smart Router v0.4.0'
git push origin smart-router-v0.4.0
```

The publishing workflow validates that the tag version equals `smart-router/pyproject.toml`, runs tests, confirms branch parity, and only then pushes the image.
