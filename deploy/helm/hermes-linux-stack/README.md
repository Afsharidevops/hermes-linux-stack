# Hermes Linux Stack Helm — v0.5.9 foundation

This chart deploys the **Smart Router HA core** with PostgreSQL and Redis, two router replicas, probes, a PDB, security contexts, topology spread, and a baseline NetworkPolicy, plus an optional in-cluster model gateway. It deliberately does **not** claim the full v0.5.9 Helm release gate yet: Hermes, Open WebUI, n8n, execution brokers, ingress/TLS and production External Secrets still require full-stack templates and cluster validation.

Create a Kubernetes Secret named `hermes-smart-router-secrets` with keys `hmac-secret`, `admin-api-key`, `client-api-key`, `bootstrap-admin-password`, `postgres-password`, and `redis-password`, then install:

```bash
helm install hermes ./deploy/helm/hermes-linux-stack --namespace hermes --create-namespace
```

## Upstream gateway

`upstream.baseUrl` and `upstream.healthUrl` are empty by default and the chart derives them. Set both for an external gateway, or enable the optional gateway server and pick the backend:

```bash
helm install hermes ./deploy/helm/hermes-linux-stack --namespace hermes --create-namespace \
  --set upstreamServer.enabled=true --set upstreamServer.backend=9router
```

`upstreamServer.backend` accepts `9router` or `omniroute`. The image, port, persistence, resources, and the `existingSecret` whose keys are the gateway's own environment names live under `upstreamServer.nineRouter` and `upstreamServer.omniRoute`. With an external gateway the environment keeps its own 9router/OmniRoute deployment and the chart only points the router at it.

## Private registries

Set `imagePullSecrets` when the images come from a private registry:

```bash
helm install hermes ./deploy/helm/hermes-linux-stack --namespace hermes --create-namespace \
  --set imagePullSecrets[0].name=my-registry-credentials
```

## Values

| Value | Default | Purpose |
| --- | --- | --- |
| `replicaCount` | `2` | Smart Router replicas |
| `image.repository`, `image.tag`, `image.pullPolicy` | `afsharidevops/hermes-smart-router:0.6.1` | Router image |
| `imagePullSecrets` | `[]` | Pull secrets for a private registry |
| `upstream.baseUrl`, `upstream.healthUrl` | empty | Explicit upstream; empty derives from `upstreamServer` |
| `upstreamServer.enabled`, `upstreamServer.backend` | `false`, `9router` | Deploy an in-cluster gateway |
| `router.orchestrator.approvalMode` | `auto` | Orchestrator approval gate (`auto`, `always`, `never`) |
