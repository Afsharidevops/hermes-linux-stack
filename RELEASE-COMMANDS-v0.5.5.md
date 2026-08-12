# v0.5.5 release and upgrade commands

## 1. Back up the current Smart Router database

On the Hermes server, before upgrading:

```bash
cd ~/hermes-linux-stack
mkdir -p backups/manual

if [ -f data/smart-router/control-v0.5.2.sqlite3 ]; then
  cp -a data/smart-router/control-v0.5.2.sqlite3 \
    "backups/manual/control-v0.5.2.sqlite3.$(date +%Y%m%d-%H%M%S).bak"
fi
```

Do not delete `data/smart-router/`. v0.5.5 upgrades the schema in place.

## 2. Build and publish Smart Router v0.5.5

From the repository root:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.5 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router
```

Optional alias:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.5 \
  -t afsharidevops/hermes-smart-router:v0.5.5 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router
```

Verify:

```bash
docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.5.5
```

## 3. Upgrade an existing server

After the Git branch and Docker image are published:

```bash
cd ~/hermes-linux-stack
git pull --ff-only

sed -i 's/^SMART_ROUTER_IMAGE_TAG=.*/SMART_ROUTER_IMAGE_TAG=0.5.5/' .env

docker compose --env-file .env pull smart-router
docker compose --env-file .env up -d --no-deps --force-recreate smart-router
```

Validate:

```bash
./manage.sh router-status
./manage.sh router-system
docker logs --tail 100 hermes-smart-router
```

Expected system output includes:

```text
version: 0.5.5
control_schema: 0.5.5
control_db: sqlite:////data/control-v0.5.2.sqlite3
```

## 4. UI validation

Open:

```text
http://SERVER:8787/dashboard
http://SERVER:8787/control/
```

Check:

- System → mode/policy/HA controls
- Access → Groups
- Intelligence → Skills
- Intelligence → Plugins suggested catalog
- Intelligence → Agents create/edit/delete and visible errors
- System → Docs

## 5. First Selen test

Create Selen with Knowledge left empty for the first test:

```text
Name: Selen
Tier: auto
Profile: auto
Knowledge: none
Skills: Linux Operations, Network Engineering (optional after installing them)
System prompt:
Your name is Selen.
You are my Telegram infrastructure and network engineering assistant.
You assist with Linux, MikroTik, Docker, networking, automation and Hermes Linux Stack.
```

If `Selen` already exists, v0.5.5 displays the backend `409 agent name already exists` error in the modal.
