# Smart Router v0.3.1 release workflow

The same published Smart Router image is used by both Git branches. Build and push it once from either branch after applying and testing v0.3.1.

## Tests

```bash
python3 -m venv ~/.venvs/hermes-smart-router-v031
source ~/.venvs/hermes-smart-router-v031/bin/activate
python -m pip install -e './smart-router[dev]'
python -m pytest smart-router/tests
```

Expected package suite: **44 passed**.

## Build and push

```bash
docker login
docker buildx use hermes-builder
docker buildx inspect --bootstrap

docker buildx build \
  --builder hermes-builder \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.3.1 \
  -t afsharidevops/hermes-smart-router:v0.3.1 \
  -t afsharidevops/hermes-smart-router:latest \
  --sbom=true \
  --provenance=mode=max \
  --push \
  ./smart-router
```

If your BuildKit container cannot reach PyPI, use the same host-network Buildx configuration you used for v0.3.0.

Verify both architectures:

```bash
docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.3.1
```

## Runtime smoke test

```bash
export SMART_ROUTER_TEST_SECRET="$(openssl rand -hex 32)"
docker rm -f smart-router-v031-test 2>/dev/null || true

docker run -d \
  --name smart-router-v031-test \
  -p 18080:8080 \
  -e SMART_ROUTER_MODE=observe \
  -e SMART_ROUTER_POLICY=heuristic \
  -e SMART_ROUTER_HMAC_SECRET="$SMART_ROUTER_TEST_SECRET" \
  -e SMART_ROUTER_UPSTREAM_BASE_URL=http://127.0.0.1:9999/v1 \
  -e SMART_ROUTER_UPSTREAM_HEALTH_URL=http://127.0.0.1:9999/health \
  afsharidevops/hermes-smart-router:0.3.1

curl -fsS http://127.0.0.1:18080/health
docker logs smart-router-v031-test
docker rm -f smart-router-v031-test
unset SMART_ROUTER_TEST_SECRET
```

`/health` should return version `0.3.1`. `/ready` will be 503 in this isolated smoke test because the upstream is deliberately nonexistent.

## Production secrets

Generate `SMART_ROUTER_HMAC_SECRET` once and keep it stable across restarts:

```bash
openssl rand -hex 32
```

Keep real secrets in the deployment `.env` or a secret manager, never in Git.
