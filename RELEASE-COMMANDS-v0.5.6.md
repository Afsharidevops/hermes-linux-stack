# Hermes Linux Stack v0.5.6 — Release / Upgrade Commands

## Upgrade an existing checkout

```bash
cd ~/hermes-linux-stack
./manage.sh backup

git fetch origin
git pull --ff-only

# Keep your real secrets in .env; add/adjust only the new v0.5.6 settings you need.
sed -i 's/^SMART_ROUTER_IMAGE_TAG=.*/SMART_ROUTER_IMAGE_TAG=0.5.6/' .env

docker compose --env-file .env pull smart-router
docker compose --env-file .env up -d --no-deps --force-recreate smart-router

./manage.sh router-status
./manage.sh router-system
./manage.sh health
```

## Build and publish Smart Router 0.5.6 for AMD64 + ARM64

```bash
cd ~/hermes-linux-stack

docker run --privileged --rm tonistiigi/binfmt --install arm64

docker buildx rm hermes-multiarch 2>/dev/null || true
docker buildx create --name hermes-multiarch --driver docker-container --use
docker buildx inspect --bootstrap

docker buildx build \
  --builder hermes-multiarch \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.6 \
  -t afsharidevops/hermes-smart-router:v0.5.6 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router

docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.5.6
```

## Run the v0.5.6 HA example

```bash
cd ~/hermes-linux-stack
# Set required secrets and upstream URL in your shell or private .env first.
docker compose -f smart-router/compose-ha-v0.5.6.example.yml up -d
./scripts/ha-smoke-v0.5.6.sh
python3 scripts/load-test-v0.5.6.py --base-url http://127.0.0.1:8787 --requests 500 --concurrency 40
```

To benchmark real `model=auto` completions, export the client token only in your shell and add `--chat`; this may incur provider cost:

```bash
export HERMES_BENCHMARK_TOKEN='...'
python3 scripts/load-test-v0.5.6.py --base-url http://127.0.0.1:8787 --requests 100 --concurrency 10 --chat --model auto
unset HERMES_BENCHMARK_TOKEN
```

## Verify the v0.5.6 UI and lifecycle fixes

Open `/dashboard` and `/control/`. Check light/dark mode, Traces, Guardrails, Router Pipelines, Model Catalog, Workflows, Prompts, Evaluations, Marketplace and Onboarding. For Agents/Teams/Groups/Plugins/Skills/Routes verify that Disable changes the visible state, Enable restores it, and permanent Delete/Uninstall is a separate destructive action.
