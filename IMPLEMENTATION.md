# Smart Router v0.2 implementation notes

This package extends `hermes-omniroute-linux-stack` without adding RouteLLM as a runtime dependency.

## Data plane

`Hermes / Open WebUI / n8n -> Smart Router -> OmniRoute -> provider/model`

The Smart Router decides task tier/capability. OmniRoute remains responsible for provider/model selection, quota, cost and fallback.

Fresh OmniRoute installs keep all three Smart Router tier model names at `auto`. That is deliberately safe but means tier selection initially changes only the router's output budget/capability decision. For real fast/standard/strong differentiation, create suitable OmniRoute endpoint/combo/model names and set `SMART_ROUTER_FAST_MODEL`, `SMART_ROUTER_STANDARD_MODEL`, and `SMART_ROUTER_STRONG_MODEL` in `.env`.

## Calibration rollout

Use observe+heuristic first, label your workload, run `./manage.sh router-calibrate PATH` and `router-report`, then enable `SMART_ROUTER_POLICY=calibrated` while still observing. Switch to `route` only after the report and live observations look acceptable. Capability gates remain authoritative.
