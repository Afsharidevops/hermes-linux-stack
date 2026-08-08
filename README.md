# Hermes + 9router + Calibrated Smart Router

This is a complete deployment package built from the current Hermes Linux Stack `main` topology, with **Smart Router v0.2 calibration/evaluation** added. RouteLLM is **not** placed in the runtime request path.

## Architecture

```text
Hermes Agent ───┐
Open WebUI ─────┼──> Hermes Smart Router v0.2 ──> 9router ──> AI providers
n8n / clients ──┘    capability gates
                      calibrated/heuristic policy
                      sticky sessions
                      output budgets
```

The Smart Router answers **what capability/tier does this request need?**. 9router remains the delivery layer for model/provider selection and fallback.

## What is new

- pluggable `heuristic` and `calibrated` policies
- deterministic capability gates for tools, vision and context
- fast/standard/strong sticky-session routing with immediate promotion and delayed demotion
- request-aware output budgets in route mode
- privacy-safe JSONL observations (derived features/metadata only)
- offline `replay`, `calibrate`, and `report` commands
- published multi-architecture Smart Router image: `afsharidevops/hermes-smart-router:0.2.0`
- Open WebUI defaults to `http://smart-router:8080/v1`
- Smart Router upstream is `http://nine-router:20128/v1`
- current default tier models: `combo-fast`, `combo-standard`, `combo-strong`

## Quick start

```bash
chmod +x install.sh manage.sh
./install.sh
./manage.sh status
./manage.sh router-info
```

The packaged default is intentionally **observe + heuristic**. Do not jump straight to calibrated route mode.

## Recommended rollout

```bash
# 1. Run real traffic in shadow/observe mode
./manage.sh router-mode observe
./manage.sh router-policy heuristic

# 2. Create a labeled workload JSONL, using the example schema
./manage.sh router-calibrate my-labeled-workload.jsonl
./manage.sh router-report my-labeled-workload.jsonl

# 3. Review smart-router/policy/calibrated.json, then shadow it
./manage.sh router-policy calibrated

# 4. After validation, enable enforcement
./manage.sh router-mode route
```

See `IMPLEMENTATION.md` and `smart-router/README.md` for the data format and privacy boundary.

## Router aliases

| Model | Behavior |
|---|---|
| `auto` | policy chooses a tier; capability gates may upgrade |
| `auto-fast` | request fast; capability gates may upgrade |
| `auto-standard` | request standard; capability gates may upgrade |
| `auto-strong` | force strong tier |
| any other model name | pass through explicitly, unchanged |

## Privacy and calibration

Production observations contain pseudonymous session hash, derived request facts, policy score/reasons, selected tier/model and budget metadata. The router does **not** write prompts, response text, tool arguments, credentials, or raw conversation IDs to its observation file.

The bundled `smart-router/policy/calibrated.json` intentionally equals the original heuristic. It is a bootstrap file, **not a trained claim**. Generate your own after labeling representative workloads.

## Included upstream reference

`README.upstream.md` preserves the branch README used as a reference while assembling this package. The existing Compose topology, including optional n8n/Caddy/execution services, is retained; execution profiles remain opt-in.

## Validation

```bash
./tests/smoke.sh
```

The smoke test validates shell syntax, Python compilation/tests, Compose YAML structure, gateway wiring, and calibration/report tooling. Docker runtime/provider credentials cannot be exercised inside the package build environment, so perform a real provider smoke test before production cutover.

## License

MIT for this repository code; third-party images retain their own licenses.
