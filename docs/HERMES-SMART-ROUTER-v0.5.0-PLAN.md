# Hermes Smart Router v0.5.0 — Evidence-First Routing Plan

Status: **release-candidate engineering plan**  
Target branches: `main` and `hermes-omniroute-linux-stack`  
Shared invariant: `smart-router/` must remain byte-identical on both branches.

## Objective

Hermes v0.5.0 should keep the production-safety advantages of v0.4.0 while closing the biggest gaps with research routers such as RouteLLM: provider portability, preference-derived learning, reproducible cost/quality evidence, public benchmark maturity, and real production-cost measurement.

The release must **not** turn synthetic results into production claims. A score or capability is considered “earned” only when the evidence gate in this plan is satisfied.

## v0.5 target scorecard

| Factor | v0.4 baseline | v0.5 target | What v0.5 implements | Evidence required to claim target |
|---|---:|---:|---|---|
| Provider portability | 8/10 | **9/10** | Provider/gateway profile validator and env exporter; keeps OpenAI-compatible upstream contract | Validate at least 3 distinct gateways/providers in CI or documented integration tests |
| Learned routing sophistication | 7/10 | **9/10** | Preference-derived three-tier labels feeding the existing local learned trainer; preserves hard capability floors | Held-out learned-router comparison vs heuristic/calibrated baselines with confidence/risk plots |
| Preference-data training | 5/10 | **9–10/10 goal** | `smart-router-preference-build` converts measured per-tier outcomes into training labels at a chosen quality-retention target | Representative multi-model preference/outcome dataset; documented grader/human protocol |
| Cost-quality research evidence | 5/10 | **9–10/10 goal** | Existing Pareto benchmark retained; real USD pricing and production ledger added; evidence protocol documented | Held-out workload, real model prices, quality grading, confidence intervals, reproducible manifest |
| Public benchmark maturity | 4/10 | **8–9/10 goal** | Public evidence layout, README figures, reproducibility checklist, external benchmark roadmap | Publish real benchmark artifacts; ideally add LLMRouterBench-compatible evaluation |
| Production cost evidence | 3/10 | **8/10** | Built-in measured token/USD ledger and `/dashboard`; same-token strong-only counterfactual; usage coverage | ≥1,000 representative routed requests with high usage coverage and actual tier prices |

**Important:** the “goal” scores above are targets, not current claims.

## Architecture

```text
Client / Hermes / Open WebUI / n8n
                |
                v
        Hermes Smart Router v0.5
                |
     +----------+-----------+
     |                      |
 privacy-safe features   hard capability floor
     |                  tools / vision / context
     v                      |
 heuristic / calibrated / learned / preference-derived
     |                      |
     +----------+-----------+
                v
        fast / standard / strong
                |
        +-------+--------+
        |                |
     9router          OmniRoute
        |                |
        +-------+--------+
                v
          provider / model

Telemetry side path:
route result -> measured upstream usage -> SQLite cost ledger -> /dashboard
```

## Built-in Smart Router dashboard

v0.5 adds a lightweight dashboard directly to the Smart Router service:

- `GET /dashboard`
- `GET /dashboard/api/summary?hours=24`

The dashboard uses no external JavaScript framework. It is served by Starlette and reads a local SQLite ledger.

### Dashboard metrics

- Routed request count
- Real upstream input tokens
- Real upstream output tokens
- Cached input tokens when reported
- Usage coverage percentage
- Tier mix: fast / standard / strong
- Actual measured USD cost when real prices are configured
- Same-token strong-only counterfactual cost
- Measured USD savings and savings percentage
- Pricing coverage percentage
- Streaming request count
- Output-budget cap reduction

### Measurement honesty rules

1. Missing upstream usage is recorded as missing, not estimated into USD.
2. Cost calculations include only requests with both usage and valid pricing.
3. Dashboard always exposes `usage_coverage` and `cost_coverage`.
4. “Strong-only savings” means **the same measured token counts priced at the strong tier**. It does not claim that the strong model would generate exactly the same number of tokens.
5. “Token reduction” is limited to the enforced output-budget-cap delta. It is not presented as counterfactual generated-token savings.
6. Streaming paths that do not expose usage reduce coverage rather than producing invented values.

## Pricing configuration

v0.5 adds a pricing template under:

```text
smart-router/policy/pricing-v0.5.example.json
```

Copy it to `pricing-v0.5.json`, fill in the actual prices for the models/routes behind each tier, and configure:

```env
SMART_ROUTER_COST_LEDGER_ENABLED=true
SMART_ROUTER_COST_DATABASE_PATH=/data/cost-ledger.sqlite3
SMART_ROUTER_PRICING_FILE=/policy/pricing-v0.5.json
SMART_ROUTER_DASHBOARD_ENABLED=true
```

If pricing is absent, the dashboard still shows real token usage and coverage but USD values remain unavailable.

## Provider portability

New CLI:

```bash
smart-router-provider-profile smart-router/examples/provider-profile-9router-v0.5.json
smart-router-provider-profile smart-router/examples/provider-profile-omniroute-v0.5.json
```

It validates a generic OpenAI-compatible gateway profile and emits Smart Router environment settings. A generic template is included for other OpenAI-compatible gateways.

v0.5 deliberately does **not** hard-code vendor SDKs into the routing core. Provider portability remains at the gateway/profile boundary.

## Preference-derived training

New CLI:

```bash
smart-router-preference-build outcomes.jsonl \
  --output preference-training.jsonl \
  --retention 0.95 \
  --cost-config real-provider-costs.json

smart-router-train preference-training.jsonl \
  --output policy/learned-v5.joblib \
  --metadata policy/learned-v5.json
```

Each preference input row must contain:

- the existing complete privacy-safe `features` object;
- measured `quality_by_tier` for fast, standard, and strong;
- optional `minimum_tier` capability floor.

The builder chooses the cheapest tier that both:

1. respects the capability floor; and
2. meets the configured quality-retention target relative to strong.

This converts measured outcomes into three-tier labels while preserving the runtime rule that learned routing cannot bypass hard capability constraints.

## Research evidence protocol

A public Hermes cost/quality claim should include:

1. A representative held-out workload, preferably ≥1,000 rows for release evidence.
2. Real per-model/per-tier input and output prices with a timestamp/source.
3. Measured input/output token counts.
4. Per-tier response quality using a disclosed evaluator, task score, or human preference protocol.
5. Fixed baselines: fast-only, standard-only, strong-only.
6. Hermes heuristic, calibrated, and learned/preference-derived policies on the same rows.
7. Quality retention, cost ratio, cost savings, false-fast, under-route, over-route, safe-routing, tier distribution.
8. Confidence/risk analysis for learned policies.
9. Confidence intervals or bootstrap uncertainty where practical.
10. The raw benchmark config, machine-readable summary, plots, and Git commit SHA.
11. Clear separation between synthetic examples and production evidence.

## RouteLLM-inspired improvements without cloning RouteLLM

RouteLLM’s research strength is learned cost/quality routing and threshold calibration. Hermes should borrow the evidence discipline while preserving its own production architecture:

- Keep three tiers rather than collapsing to weak/strong.
- Keep tools/vision/context as hard capability floors.
- Keep local/network-free learned inference as an available path.
- Use preference outcomes to train the proposer, not to override capability gates.
- Calibrate the operating point using quality retention and cost/SLO constraints.
- Evaluate multiple policy families on identical held-out data.

External research references:

- RouteLLM: https://github.com/lm-sys/RouteLLM
- LLMRouterBench: https://github.com/ynulihao/LLMRouterBench

## Public benchmark maturity roadmap

### v0.5.0 release candidate

- [x] Built-in real token/cost ledger
- [x] `/dashboard`
- [x] Provider profile validator/exporter
- [x] Preference-derived label builder
- [x] README-friendly evidence figures
- [x] Existing synthetic Pareto benchmark retained
- [ ] Real held-out benchmark data
- [ ] External benchmark adapter/run
- [ ] Published confidence intervals

### v0.5.x evidence release

- Collect 1k–10k representative requests.
- Grade all three tier outputs on the same requests.
- Add actual provider prices and token usage.
- Train preference-derived policy on train split only.
- Freeze test split before tuning thresholds.
- Compare heuristic/calibrated/learned/preference policies.
- Publish a release evidence bundle.

### v0.6 research target

- Ordinal or pairwise three-tier preference model rather than only derived class labels.
- Cost/SLO threshold calibration directly from held-out curves.
- Optional embedding/router backends behind a local interface.
- LLMRouterBench adapter and reproducible public leaderboard script.
- Streaming usage parser where upstream SSE includes usage frames.

## Branch release procedure

1. Apply and validate the v0.5 `main` pack.
2. Push `main`.
3. Apply the OmniRoute pack; it should sync `smart-router/` from `origin/main` first.
4. Run complete tests and smoke checks.
5. Confirm:

```bash
git diff --exit-code origin/main..origin/hermes-omniroute-linux-stack -- smart-router/
```

6. Push OmniRoute branch.
7. Publish one canonical Smart Router image from `main`:

```text
afsharidevops/hermes-smart-router:0.5.0
afsharidevops/hermes-smart-router:v0.5.0
afsharidevops/hermes-smart-router:latest
```

8. Verify `linux/amd64` and `linux/arm64` manifests.

## Definition of done

v0.5.0 engineering release is done when:

- all Smart Router tests pass;
- dashboard tests pass;
- cost ledger tests pass;
- preference builder tests pass;
- provider profile tests pass;
- synthetic benchmark still passes its explicit gates;
- Docker image builds for amd64 and arm64;
- both remote branches have identical `smart-router/`;
- README explicitly labels synthetic figures;
- no public production-savings claim is made without measured production evidence.
