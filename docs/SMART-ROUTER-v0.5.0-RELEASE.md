# Hermes Smart Router v0.5.0 release candidate

v0.5.0 is an evidence-first release focused on measured production cost visibility and a stronger path from measured preference outcomes to learned routing.

## Added

- Built-in `/dashboard` and `/dashboard/api/summary`.
- SQLite measured-usage/cost ledger.
- Optional real USD tier pricing file.
- Same-token strong-only cost counterfactual with explicit coverage metrics.
- Provider/gateway profile validation and env export CLI.
- Preference-derived three-tier training-label builder.
- v0.5 research/evidence plan and README figures.

## Important limitations

- USD cost is only as complete as upstream usage coverage and configured pricing.
- Streaming responses without usage remain unpriced and reduce coverage.
- The same-token strong baseline is a pricing counterfactual, not a claim that strong would generate the same tokens.
- v0.4 synthetic benchmark figures remain synthetic examples; v0.5 does not convert them into production claims.
- Preference-derived labels improve the data pipeline, but RouteLLM-class public research evidence requires a real held-out preference/evaluation dataset.
