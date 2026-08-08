> Branch scope: **hermes-omniroute-linux-stack** only. Runtime gateway: **OmniRoute** only. This package does not include or run the alternate gateway.

# Hermes Smart Router v0.2

An OpenAI-compatible routing layer for Hermes Linux Stack. It keeps capability safety deterministic while allowing the cost/quality policy to be calibrated offline from your own workload.

## Request path

`Hermes / Open WebUI / n8n -> Smart Router -> OmniRoute -> provider/model`

The router has four separate responsibilities:

1. **Policy** proposes `fast`, `standard`, or `strong` from privacy-safe request features.
2. **Capability gates** upgrade proposals when tools, vision, or context do not fit a tier.
3. **Sticky sessions** promote immediately and delay demotion to reduce model thrashing.
4. **Output budgets** clamp routed requests to a per-tier maximum without ever increasing a client-specified lower limit.

## Modes

- `SMART_ROUTER_MODE=observe`: calculate/log a decision, but send router aliases to `SMART_ROUTER_OBSERVE_MODEL`.
- `SMART_ROUTER_MODE=route`: aliases `auto`, `auto-fast`, `auto-standard`, `auto-strong` are routed. Explicit non-alias model names pass through untouched.

## Policies

- `SMART_ROUTER_POLICY=heuristic`: original deterministic scoring.
- `SMART_ROUTER_POLICY=calibrated`: load weights/thresholds from `SMART_ROUTER_CALIBRATION_FILE`.

`policy/calibrated.json` is a safe bootstrap that exactly matches the heuristic. It is **not claimed to be trained**. Replace it only after evaluating your own workload.

## Offline calibration

Install locally with `pip install -e '.[dev]'`, set a 32+ character `SMART_ROUTER_HMAC_SECRET`, then:

```bash
smart-router-calibrate examples/labeled-workload.jsonl -o policy/calibrated.json
smart-router-report examples/labeled-workload.jsonl --policy policy/calibrated.json
```

The calibration dataset can contain derived `features`, `facts`, or a `body`. For production data, prefer `features`/`facts` so prompts never leave your normal request path.

`smart-router-replay requests.jsonl -o replay-decisions.jsonl` is provided for offline request replay. Its output omits prompts/tool arguments and contains decisions/features only.

## Privacy

The production observation writer accepts only derived features and routing metadata. Session identifiers are HMAC-pseudonymized. No prompt text, response text, tool arguments, credentials, or raw conversation IDs are written to the observation JSONL by this code.
