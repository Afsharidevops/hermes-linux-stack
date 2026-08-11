# v0.5.2 release commands — `main`

Replace `<GITHUB_USER>/<REPO>` if your repository name differs. The package defaults the Smart Router repository to `afsharidevops/hermes-smart-router`; change `DOCKERHUB_USER` if needed.

## Push this package to GitHub

Use a fresh clone so `rsync --delete` cannot remove local runtime state:

```bash
git clone https://github.com/<GITHUB_USER>/<REPO>.git hermes-linux-stack-release
cd hermes-linux-stack-release
git fetch origin
git switch main

# From the directory where the ZIP was extracted:
rsync -a --delete \
  --exclude='.git/' \
  --exclude='.env' \
  --exclude='data/' \
  /path/to/hermes-linux-stack-main-v0.5.2/ ./

git add -A
git status
git commit -m "feat: Hermes Smart Router v0.5.2 (main)"
git push origin main
```

## Build and push the shared Smart Router image

`smart-router/` is kept identical between the two branches, so publish it once.

```bash
export DOCKERHUB_USER=afsharidevops
docker login

docker buildx create --name hermes-builder --use 2>/dev/null || docker buildx use hermes-builder
docker buildx inspect --bootstrap

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t "$DOCKERHUB_USER/hermes-smart-router:0.5.2" \
  -t "$DOCKERHUB_USER/hermes-smart-router:latest" \
  --sbom=true \
  --provenance=mode=max \
  --push ./smart-router

docker buildx imagetools inspect "$DOCKERHUB_USER/hermes-smart-router:0.5.2"
```

## Start/update the branch using mutable defaults

```bash
./install.sh --no-start
# Review .env. By default application images remain latest/main.
docker compose --env-file .env pull
docker compose --env-file .env up -d
./manage.sh doctor
./manage.sh router-info
```

To pin later, edit only the appropriate `*_IMAGE_TAG` values in `.env`, then repeat `docker compose pull` and `docker compose up -d`.
