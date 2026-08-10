# Smart Router v0.4.0 — cost/quality benchmarking

Smart Router v0.4.0 adds a release-grade benchmark command intended to answer the same operational question made visible by systems such as RouteLLM: **how much cost can the router remove while preserving quality?**

The command deliberately separates two kinds of evidence:

- **Measured response quality** — every benchmark row supplies `quality_by_tier` (or `tier_scores`) for `fast`, `standard`, and `strong`, produced by your chosen grader or human evaluation. This is suitable for a public quality-vs-cost plot when the workload and grading protocol are disclosed.
- **Safe-routing proxy** — rows have expected routing labels but do not have answer-quality scores for every tier. This is useful for router classification regression testing, but **must not be presented as end-to-end model quality**.

## Install benchmark dependencies

```bash
python -m pip install -e './smart-router[dev,bench]'
```

`matplotlib` is kept in the optional `bench` extra, so the production Docker image does not need plotting dependencies.

## JSONL schema

Each line is one request/evaluation example. Aliases accepted by the CLI are noted below.

```json
{
  "expected_tier": "standard",
  "selected_tier": "fast",
  "minimum_tier": "fast",
  "probabilities": {"fast": 0.60, "standard": 0.35, "strong": 0.05},
  "confidence": 0.60,
  "quality_by_tier": {"fast": 0.72, "standard": 0.91, "strong": 0.94},
  "usage": {"input_tokens": 1800, "output_tokens": 420}
}
```

Accepted aliases:

- expected: `expected_tier`, `label`, `target_tier`
- selected: `selected_tier`, `final_tier`, `predicted_tier`, `proposed_tier`
- quality: `quality_by_tier`, `tier_scores`
- usage: `input_tokens`/`output_tokens` or OpenAI-style `prompt_tokens`/`completion_tokens`, either at top level or under `usage`

`minimum_tier` is the deterministic capability floor. Benchmark baselines and probability sweeps apply this floor, so a synthetic `fast-only` baseline cannot pretend that a vision/tool/context request could actually run on an incapable fast tier.

## Cost models

Without a config file the benchmark uses explicitly labeled normalized weights:

```json
{
  "kind": "normalized_tier_weight",
  "costs": {"fast": 1.0, "standard": 3.0, "strong": 10.0}
}
```

These weights are useful for regression testing, not a dollar claim. For a public dollar-cost claim, use per-tier input/output rates and include token usage in every row, for example:

```json
{
  "kind": "usd_per_million_tokens",
  "costs": {
    "fast": {"input_per_million": 0.10, "output_per_million": 0.40},
    "standard": {"input_per_million": 0.50, "output_per_million": 2.00},
    "strong": {"input_per_million": 2.00, "output_per_million": 8.00}
  }
}
```

Those numbers are schema examples only, not current provider prices. With object rate entries the CLI automatically calculates cost from input/output tokens. For scalar weights, `--token-weighted-cost` optionally weights the configured tier value by total tokens.

## Generate RouteLLM-style plots

```bash
smart-router-benchmark benchmarks/release-v0.4.0.jsonl \
  --output-dir benchmark-output/v0.4.0 \
  --cost-config benchmarks/costs-production.json \
  --token-weighted-cost \
  --min-rows 1000 \
  --require-measured-quality \
  --min-quality-retention 0.95 \
  --max-false-fast-rate 0.01 \
  --max-cost-ratio 0.75
```

The command writes:

- `quality_vs_cost.png` — router and fixed baselines plus a probability-threshold sweep and Pareto frontier when class probabilities are present;
- `tier_distribution.png` — fast/standard/strong traffic mix;
- `confusion_matrix.png` — expected vs selected tiers;
- `confidence_risk.png` — under-routing rate by confidence bucket when confidence is present;
- `frontier.csv` — non-dominated threshold configurations;
- `summary.json` — machine-readable release evidence;
- `report.md` — human-readable release report.

The CLI exits with status `2` when configured release gates fail, so the exact same evidence can gate CI or a release candidate.

## Example data and figures

`smart-router/examples/benchmark-synthetic-v0.4.0.jsonl` exists only to exercise the pipeline. The generated example under `docs/smart-router-v0.4.0/synthetic-benchmark/` is visibly watermarked **SYNTHETIC EXAMPLE, NOT A PERFORMANCE CLAIM**.

Do not copy its numbers into release notes. Replace the input with a representative held-out workload and keep the generated `summary.json` alongside the release evidence.

## Recommended public release evidence

For a credible v0.4.0 result, publish at least:

1. workload size and sampling method;
2. tier/provider/model mapping used during the evaluation;
3. grading method (human, task success, judge model, unit tests, or a combination);
4. cost model and date;
5. quality retention vs strong-only;
6. cost ratio/savings vs strong-only;
7. false-fast and overall under-route rates;
8. strong over-route rate and traffic mix;
9. confidence intervals or repeated-run variability when feasible;
10. the generated report, JSON summary, and plot artifacts.

This keeps benchmark claims reproducible instead of turning routing-label accuracy into an unsupported model-quality claim.
