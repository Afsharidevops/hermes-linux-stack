# Hermes Smart Router v0.5.0 dashboard

The dashboard is built into Smart Router itself:

```text
GET /dashboard
GET /dashboard/api/summary?hours=24
```

It is shared by both the 9router (`main`) and OmniRoute branches because the entire `smart-router/` tree must be identical on both branches.

## What is measured

For successful Smart Router-routed responses, v0.5 records upstream usage when the response includes an OpenAI-style `usage` object:

- prompt/input tokens;
- completion/output tokens;
- cached input tokens when reported;
- selected tier and effective model;
- whether usage was available;
- whether a complete price was available;
- actual USD cost for the selected tier;
- same-token strong-tier USD cost;
- enforced output-budget-cap delta.

The ledger is stored in SQLite at `/data/cost-ledger.sqlite3` by default.

## Security

The HTML shell at `/dashboard` contains no telemetry. `/dashboard/api/summary` uses the normal Smart Router client authentication when `SMART_ROUTER_CLIENT_API_KEY` is configured. The dashboard page includes an optional API-key field stored only in browser `sessionStorage` and sends it as a Bearer token to the summary API.

Do not expose port 8080 directly to the public Internet. Use the same reverse proxy/private network controls as the rest of the Smart Router API.

## Pricing

Copy:

```text
smart-router/policy/pricing-v0.5.example.json
```

to:

```text
smart-router/policy/pricing-v0.5.json
```

and enter the current prices for the actual models/routes behind each tier.

Then configure:

```env
SMART_ROUTER_COST_LEDGER_ENABLED=true
SMART_ROUTER_COST_DATABASE_PATH=/data/cost-ledger.sqlite3
SMART_ROUTER_PRICING_FILE=/policy/pricing-v0.5.json
SMART_ROUTER_DASHBOARD_ENABLED=true
```

If prices are absent or incomplete, real token totals remain visible but USD cost and savings remain unavailable.

## Interpreting savings

`strong_same_token_cost_usd` is a **same-token pricing counterfactual**. It answers:

> What would these exact measured input/output token counts cost if priced at the configured strong-tier rates?

It does not claim the strong model would have generated the exact same output length.

`budget_tokens_avoided` measures only the reduction between a client-provided output-token cap and the enforced effective cap. It is not a measured counterfactual of generated tokens.

## Coverage

The dashboard exposes both:

- `usage_coverage`: fraction of routed requests with upstream usage;
- `cost_coverage`: fraction of routed requests with both usage and usable tier pricing.

Low coverage is shown as a warning. Streaming paths without usage are intentionally counted as missing rather than estimated.
