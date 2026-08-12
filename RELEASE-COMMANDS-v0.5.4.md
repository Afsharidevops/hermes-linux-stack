# v0.5.4 release commands

Smart Router v0.5.4 changes runtime routing, quota handling, RAG storage, and the Hermes Operations Center UI. Publish the v0.5.4 image before upgrading a running stack.

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t afsharidevops/hermes-smart-router:0.5.4 \
  -t afsharidevops/hermes-smart-router:latest \
  --push \
  ./smart-router

docker buildx imagetools inspect afsharidevops/hermes-smart-router:0.5.4
```

Fresh v0.5.4 installs default to `SMART_ROUTER_IMAGE_TAG=0.5.4`. Existing `.env` values remain operator-owned and are not overwritten during normal reconfiguration.

The stack client defaults are now explicit and suitable for long Hermes tool sessions:

```text
SMART_ROUTER_CLIENT_RPM=120
SMART_ROUTER_CLIENT_TPM=2000000
SMART_ROUTER_CLIENT_DAILY_REQUESTS=10000
```

RAG knowledge tables share the Operations database when `SMART_ROUTER_KNOWLEDGE_DATABASE_URL` is empty. Set that variable to a SQLAlchemy PostgreSQL DSN to keep knowledge data in a separate database.
