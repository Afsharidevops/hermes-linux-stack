# v0.5.3 release commands

Smart Router v0.5.3 changes runtime UI code, so publish a new image before deploying the v0.5.3 stack.

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.3 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router
```

Fresh v0.5.3 installs default to `SMART_ROUTER_IMAGE_TAG=0.5.3`. Existing `.env` values are preserved on reconfiguration.
