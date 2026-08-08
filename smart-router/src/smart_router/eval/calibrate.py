from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

from smart_router.routing import DEFAULT_THRESHOLDS, DEFAULT_WEIGHTS
from .common import flags_from_record, iter_jsonl, score, tier_for_score, weighted_mistake_cost


def load_labeled(path: Path) -> list[tuple[dict[str, float], str]]:
    rows = []
    for record in iter_jsonl(path):
        label = str(record.get("label_tier", "")).lower()
        if label not in {"fast", "standard", "strong"}:
            raise ValueError("every calibration record needs label_tier=fast|standard|strong")
        rows.append((flags_from_record(record), label))
    if len(rows) < 3:
        raise ValueError("need at least 3 labeled records")
    return rows


def threshold_candidates(values: list[float]) -> list[float]:
    unique = sorted(set(values))
    candidates = [unique[0] - 0.5]
    candidates += [(a + b) / 2.0 for a, b in zip(unique, unique[1:])]
    candidates.append(unique[-1] + 0.5)
    return candidates


def fit_thresholds(rows: list[tuple[dict[str, float], str]], weights: dict[str, float], under: float, over: float) -> tuple[dict[str, float], float]:
    scored = [(score(flags, weights), label) for flags, label in rows]
    candidates = threshold_candidates([value for value, _ in scored])
    best = None
    for fast_max in candidates:
        for standard_max in candidates:
            if fast_max >= standard_max:
                continue
            loss = sum(weighted_mistake_cost(tier_for_score(value, fast_max, standard_max), label, under, over) for value, label in scored)
            key = (loss, abs(fast_max - DEFAULT_THRESHOLDS["fast_max"]) + abs(standard_max - DEFAULT_THRESHOLDS["standard_max"]), fast_max, standard_max)
            if best is None or key < best[0]:
                best = (key, {"fast_max": fast_max, "standard_max": standard_max})
    assert best is not None
    return best[1], float(best[0][0])


def coordinate_fit(rows: list[tuple[dict[str, float], str]], under: float, over: float, passes: int) -> tuple[dict[str, float], dict[str, float], float]:
    weights = dict(DEFAULT_WEIGHTS)
    thresholds, best_loss = fit_thresholds(rows, weights, under, over)
    # Small, explainable coordinate search. No ML runtime dependency is introduced.
    multipliers = [0.0, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    for _ in range(max(0, passes)):
        improved = False
        for name, base in list(weights.items()):
            sign = -1.0 if base < 0 else 1.0
            magnitude = abs(base) if base != 0 else 1.0
            candidate_values = sorted(set(sign * magnitude * m for m in multipliers))
            local_best = (best_loss, weights[name], thresholds)
            for candidate in candidate_values:
                trial = dict(weights)
                trial[name] = candidate
                trial_thresholds, loss = fit_thresholds(rows, trial, under, over)
                key = (loss, abs(candidate - DEFAULT_WEIGHTS[name]))
                current_key = (local_best[0], abs(local_best[1] - DEFAULT_WEIGHTS[name]))
                if key < current_key:
                    local_best = (loss, candidate, trial_thresholds)
            if local_best[0] < best_loss or local_best[1] != weights[name]:
                weights[name] = local_best[1]
                thresholds = local_best[2]
                best_loss = local_best[0]
                improved = True
        if not improved:
            break
    return weights, thresholds, best_loss


def main() -> None:
    parser = argparse.ArgumentParser(description="Fit Smart Router weights/thresholds to labeled workload JSONL.")
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--under-penalty", type=float, default=3.0, help="Penalty per tier for routing below the label")
    parser.add_argument("--over-penalty", type=float, default=1.0, help="Penalty per tier for routing above the label")
    parser.add_argument("--weight-passes", type=int, default=1, help="0=thresholds only; >0 also coordinate-fit feature weights")
    args = parser.parse_args()

    rows = load_labeled(args.input)
    weights, thresholds, loss = coordinate_fit(rows, args.under_penalty, args.over_penalty, args.weight_passes)
    payload: dict[str, Any] = {
        "schema_version": 1,
        "name": f"calibrated-{args.input.stem}",
        "description": "Generated offline from labeled feature/request records. Review before production route mode.",
        "training_records": len(rows),
        "loss": loss,
        "under_penalty": args.under_penalty,
        "over_penalty": args.over_penalty,
        "weights": weights,
        "thresholds": thresholds,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"records": len(rows), "loss": loss, "output": str(args.output), "thresholds": thresholds}, indent=2))


if __name__ == "__main__":
    main()
