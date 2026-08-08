# Smart Router v0.2 implementation notes

This package extends the `main`/9router topology without adding RouteLLM as a runtime dependency.

## Data plane

`Hermes / Open WebUI / n8n -> Smart Router -> 9router -> provider/model`

The Smart Router proposes fast/standard/strong, enforces capability gates, applies session stickiness, and in route mode clamps output budgets. 9router remains responsible for model/combo/provider fallback.

## Calibration rollout

1. Start with `SMART_ROUTER_MODE=observe` and `SMART_ROUTER_POLICY=heuristic`.
2. Collect privacy-safe `data/smart-router/observations.jsonl` plus your external quality/cost labels.
3. Build a labeled JSONL (see `smart-router/examples/labeled-workload.jsonl`).
4. Run `./manage.sh router-calibrate PATH` and `./manage.sh router-report PATH`.
5. Review `smart-router/policy/calibrated.json` in version control.
6. Run `./manage.sh router-policy calibrated`; keep observe mode while validating.
7. Finally run `./manage.sh router-mode route`.

Capability gates remain authoritative regardless of calibrated scores.
