# Hermes Linux Stack v0.5.8 — Release / Upgrade Commands

These commands are maintainer/operator guidance. Verify Git, Docker Hub, Buildx, and test-server state before claiming release completion.

## Test-server fix for Execution & Approvals

If Operations Center is opened remotely, `enable-execution-admin` alone intentionally binds Execution Admin to loopback. Configure the exact Operations Center origin and the server's private IPv4:

```bash
cd ~/hermes-linux-stack
./manage.sh configure-execution-admin-browser http://YOUR_PRIVATE_SERVER_IP:8787 YOUR_PRIVATE_SERVER_IP
./manage.sh execution-admin-status
```

Then retrieve the key only from an interactive trusted terminal:

```bash
./manage.sh show-execution-admin-key
```

Enter it in **System → Execution & Approvals**. Do not paste the key into shell arguments, Git, logs, screenshots, or documentation.

## Build/publish Smart Router

```bash
docker buildx build \
  --builder hermes-multiarch \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.8 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router

docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.5.8
```

## Build/publish Execution Broker

```bash
docker buildx build \
  --builder hermes-multiarch \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-execution-broker:0.1.3 \
  --push \
  ./execution-broker

docker buildx imagetools inspect afsharidevops/hermes-execution-broker:0.1.3
```

## Server upgrade

```bash
cd ~/hermes-linux-stack
./manage.sh backup

sed -i 's/^SMART_ROUTER_IMAGE_TAG=.*/SMART_ROUTER_IMAGE_TAG=0.5.8/' .env
if grep -q '^EXECUTION_BROKER_IMAGE=' .env; then
  sed -i 's|^EXECUTION_BROKER_IMAGE=.*|EXECUTION_BROKER_IMAGE=afsharidevops/hermes-execution-broker:0.1.3|' .env
else
  printf '%s\n' 'EXECUTION_BROKER_IMAGE=afsharidevops/hermes-execution-broker:0.1.3' >> .env
fi

docker compose --env-file .env pull smart-router
docker compose --env-file .env up -d --no-deps --force-recreate smart-router
./manage.sh router-status
./manage.sh router-system
./manage.sh health
```

If Execution Admin is used from a remote private browser, run the browser helper again after migrating/replacing `.env` so the exact origin and bind remain explicit.

## Branch publication

This package is the `9router` variant. Keep branch contents separate from the other gateway branch and publish only after reviewing `git diff`, staged files, and secret scans.

## v0.5.8 Execution Admin private-ingress hotfix

Execution Admin must stay on the internal execution-control network for broker communication while also joining a dedicated non-internal bridge used only for the private host-port publication. Do not make `execution-control-net` non-internal.

Expected service networking:

```text
execution-admin -> execution-control-net + execution-admin-ingress-net
other execution brokers -> execution-control-net only
```

After configuring remote browser access, verify:

```bash
docker port hermes-execution-admin
curl -fsS http://YOUR_PRIVATE_SERVER_IP:8752/health
```

The expected published port is `YOUR_PRIVATE_SERVER_IP:8752->8752/tcp`.
