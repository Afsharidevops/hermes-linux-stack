# Hermes Linux Stack v0.5.7 — Release / Upgrade Commands

## 1. Back up before upgrading

```bash
cd ~/hermes-linux-stack
./manage.sh backup
```

Do not delete `data/smart-router/` or `data/stack-secrets/` during an in-place upgrade.

## 2. Build and publish Smart Router 0.5.7 (AMD64 + ARM64)

```bash
cd ~/hermes-linux-stack

docker run --privileged --rm tonistiigi/binfmt --install arm64

docker buildx rm hermes-multiarch 2>/dev/null || true

docker buildx create \
  --name hermes-multiarch \
  --driver docker-container \
  --platform linux/amd64,linux/arm64 \
  --use

docker buildx inspect --bootstrap

docker login

docker buildx build \
  --builder hermes-multiarch \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.7 \
  -t afsharidevops/hermes-smart-router:v0.5.7 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router

docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.5.7
```

Verify both `linux/amd64` and `linux/arm64` manifests.

## 3. Build and publish Execution Broker 0.1.2

The v0.5.7 UI requires the new broker/admin code.

```bash
cd ~/hermes-linux-stack

docker buildx build \
  --builder hermes-multiarch \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-execution-broker:0.1.2 \
  -t afsharidevops/hermes-execution-broker:v0.1.2 \
  --push \
  ./execution-broker

docker buildx imagetools inspect afsharidevops/hermes-execution-broker:0.1.2
```

For production, inspect the published manifest digest and set `EXECUTION_BROKER_IMAGE` to the immutable digest form after publishing.

## 4. Upgrade the stack

After replacing/pulling the v0.5.7 source for the correct branch:

```bash
cd ~/hermes-linux-stack

sed -i 's/^SMART_ROUTER_IMAGE_TAG=.*/SMART_ROUTER_IMAGE_TAG=0.5.7/' .env

# If this exact key already exists, update it. Otherwise append it.
if grep -q '^EXECUTION_BROKER_IMAGE=' .env; then
  sed -i 's|^EXECUTION_BROKER_IMAGE=.*|EXECUTION_BROKER_IMAGE=afsharidevops/hermes-execution-broker:0.1.2|' .env
else
  printf '%s\n' 'EXECUTION_BROKER_IMAGE=afsharidevops/hermes-execution-broker:0.1.2' >> .env
fi

docker compose --env-file .env pull smart-router

docker compose --env-file .env \
  up -d --no-deps --force-recreate smart-router

./manage.sh router-status
./manage.sh router-system
./manage.sh health
```

## 5. Enable the v0.5.7 Execution Admin boundary

This does not automatically enable Docker/SSH execution capabilities.

```bash
cd ~/hermes-linux-stack

./manage.sh enable-execution-admin
./manage.sh execution-admin-status
./manage.sh show-execution-admin-key
```

Default endpoint:

```text
http://127.0.0.1:8752
```

Open Operations Center:

```text
http://127.0.0.1:8787/control/
```

Then open **System → Execution & Approvals**, enter the separate Execution Admin key, and connect.

### Remote/private Operations Center access

If your browser accesses the server using a private server address, set an exact private bind/origin before enabling the admin service. Example only:

```bash
sed -i 's/^EXECUTION_ADMIN_BIND_IP=.*/EXECUTION_ADMIN_BIND_IP=192.168.85.243/' .env
sed -i 's|^EXECUTION_ADMIN_ALLOWED_ORIGINS=.*|EXECUTION_ADMIN_ALLOWED_ORIGINS=http://192.168.85.243:8787|' .env

./manage.sh disable-execution-admin
./manage.sh enable-execution-admin
```

Do not use `0.0.0.0` on an untrusted network and do not use wildcard CORS. Prefer private networking and TLS/reverse proxy for remote administration.

## 6. Configure/bootstrap Telegram execution approval

If not already configured:

```bash
./manage.sh set-execution-approval-bot-token
./manage.sh set-execution-users YOUR_NUMERIC_TELEGRAM_ID
```

Execution approver IDs must already be in the Hermes `TELEGRAM_ALLOWED_USERS` list.

Deploy only the execution capability you need:

```bash
./manage.sh enable-execution sandbox
# or
./manage.sh enable-execution docker
# or
./manage.sh enable-execution ssh
```

After first deployment, **Execution & Approvals** can change the live feature policy for those deployed brokers.

## 7. Validation

```bash
./manage.sh execution-status
./manage.sh execution-admin-status
./manage.sh doctor
./manage.sh health

docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'hermes-execution|hermes-smart-router'
```

Expected trust separation:

- `execution-approver`: approval signing key + dedicated Telegram token, no Docker socket/SSH profiles.
- `execution-docker-broker`: Docker socket + approval public key, no signing key/token.
- `execution-ssh-broker`: SSH profiles + approval public key, no signing key/token/Docker socket.
- `execution-admin`: admin key + writable policy/token/control files, **no signing key, Docker socket or SSH private credential mount**.
- Smart Router: no Execution Admin key and no Telegram execution token.

## 8. Git push

### main / 9router

```bash
git checkout main
git status
git add -A
git commit -m 'Release Hermes Linux Stack v0.5.7'
git push origin main
```

### OmniRoute

```bash
git checkout hermes-omniroute-linux-stack
git status
git add -A
git commit -m 'Release Hermes Linux Stack v0.5.7'
git push origin hermes-omniroute-linux-stack
```

### Tag

```bash
git checkout main
git tag -a v0.5.7 -m 'Hermes Linux Stack v0.5.7'
git push origin v0.5.7
```
