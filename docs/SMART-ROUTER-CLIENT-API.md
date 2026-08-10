# OpenAI-compatible client API — Smart Router v0.3

Smart Router is the OpenAI-compatible API entry point for external applications. Client applications should call Smart Router rather than calling 9router or OmniRoute directly.

This guide intentionally uses generic **OpenAI-compatible client application** terminology. It does not require or document any particular editor, extension, agent UI, or vendor-specific client.

## Client endpoint

A public deployment normally gives client applications a base URL such as:

```text
https://api.example.com/v1
```

Configure the client with:

```text
API type / provider: OpenAI-compatible
Base URL:            https://api.example.com/v1
API key:             <SMART_ROUTER_CLIENT_API_KEY>
Model:               auto
```

Any client that can send OpenAI-compatible Chat Completions requests can use this interface. The automatic routing aliases are:

```text
auto
auto-fast
auto-standard
auto-strong
```

For normal use, prefer `auto` so Smart Router can select the least expensive compatible tier according to policy and hard capability requirements.

## Separate client and upstream credentials

Keep provider and downstream-gateway credentials on the server. Configure a client-facing ingress key:

```env
SMART_ROUTER_CLIENT_API_KEY=<generate-a-random-secret>
```

If the downstream gateway itself requires authentication, configure a separate server-side credential:

```env
SMART_ROUTER_UPSTREAM_API_KEY=<downstream-gateway-key>
```

When client authentication is enabled, Smart Router accepts either:

```http
Authorization: Bearer <SMART_ROUTER_CLIENT_API_KEY>
```

or:

```http
x-api-key: <SMART_ROUTER_CLIENT_API_KEY>
```

The client credential terminates at Smart Router and is not forwarded. When `SMART_ROUTER_UPSTREAM_API_KEY` is configured, Smart Router uses that server-side key for the downstream request.

The built-in client key is intentionally simple. If you serve multiple independent customers, place an API gateway or identity-aware reverse proxy in front so each customer can have separate credentials, rate limits, quotas, revocation, and audit identity.

## Test the public API

List models:

```bash
curl https://api.example.com/v1/models \
  -H 'Authorization: Bearer YOUR_CLIENT_KEY'
```

Send an automatic request:

```bash
curl https://api.example.com/v1/chat/completions \
  -H 'Authorization: Bearer YOUR_CLIENT_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"auto",
    "messages":[{"role":"user","content":"Explain this shell error briefly"}]
  }'
```

## Private/local testing

If you do not expose a public domain, use a private network, VPN, or SSH tunnel. For example:

```bash
ssh -L 8080:127.0.0.1:8080 user@your-server
```

Then use:

```text
Base URL: http://127.0.0.1:8080/v1
Model:    auto
```

Do not expose an unauthenticated Smart Router port directly to the public Internet.

## How automatic routing can reduce cost

A client should normally request `model=auto`. Smart Router first proposes a tier and then applies hard compatibility rules. For example, a request that requires tools cannot remain on a tier whose configured target does not support tools. The request is upgraded before it reaches the downstream gateway.

This means cost reduction comes from choosing the least expensive **compatible** tier, not from bypassing tool, vision, context-window, session, or output-budget safety rules.

### `main`

The 9router branch maps Smart Router tiers to:

```text
fast     -> combo-fast
standard -> combo-standard
strong   -> combo-strong
```

This allows the downstream gateway to deliver different cost/quality profiles for each selected tier.

### `hermes-omniroute-linux-stack`

The safe initial OmniRoute configuration keeps the three targets at `auto`. To obtain distinct tier-based delivery, first create or verify real OmniRoute route IDs in the running instance, then set those validated IDs in:

```env
SMART_ROUTER_FAST_MODEL=...
SMART_ROUTER_STANDARD_MODEL=...
SMART_ROUTER_STRONG_MODEL=...
```

Do not guess OmniRoute route names.

## Recommended rollout

Start with:

```env
SMART_ROUTER_MODE=observe
SMART_ROUTER_POLICY=heuristic
```

Collect privacy-safe observations and evaluate a representative workload. After training a learned artifact, use:

```env
SMART_ROUTER_MODE=observe
SMART_ROUTER_POLICY=learned
```

Only after evaluation is acceptable switch to:

```env
SMART_ROUTER_MODE=route
SMART_ROUTER_POLICY=learned
```

Rollback remains one environment change back to `heuristic` or `calibrated`.

## Public ingress choices

Smart Router does not need to own TLS itself. The stack supports two optional ingress patterns:

1. **Standalone Caddy TLS** — Caddy on the stack VM owns the domain and certificates.
2. **External reverse proxy** — a separate edge/reverse-proxy VM owns DNS/TLS and forwards private HTTP to Caddy on the stack VM.

See `docs/SMART-ROUTER-PUBLIC-INGRESS.md` after applying this package.
