from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from smart_router.routing import DEFAULT_THRESHOLDS, DEFAULT_WEIGHTS
from .common import flags_from_record, iter_jsonl, score, tier_for_score, weighted_mistake_cost


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate a calibrated policy against labeled JSONL.")
    parser.add_argument("input", type=Path)
    parser.add_argument("--policy", type=Path, default=None)
    parser.add_argument("--under-penalty", type=float, default=3.0)
    parser.add_argument("--over-penalty", type=float, default=1.0)
    args = parser.parse_args()

    if args.policy:
        payload = json.loads(args.policy.read_text(encoding="utf-8"))
        weights = {**DEFAULT_WEIGHTS, **{k: float(v) for k, v in payload.get("weights", {}).items() if k in DEFAULT_WEIGHTS}}
        thresholds = {**DEFAULT_THRESHOLDS, **{k: float(v) for k, v in payload.get("thresholds", {}).items() if k in DEFAULT_THRESHOLDS}}
    else:
        weights, thresholds = dict(DEFAULT_WEIGHTS), dict(DEFAULT_THRESHOLDS)

    confusion: Counter[tuple[str, str]] = Counter()
    total = correct = 0
    total_loss = 0.0
    selected_cost = selected_quality = 0.0
    cost_n = quality_n = 0
    for record in iter_jsonl(args.input):
        label = str(record.get("label_tier", "")).lower()
        if label not in {"fast", "standard", "strong"}:
            raise ValueError("report input requires label_tier")
        predicted = tier_for_score(score(flags_from_record(record), weights), thresholds["fast_max"], thresholds["standard_max"])
        confusion[(label, predicted)] += 1
        total += 1
        correct += int(label == predicted)
        total_loss += weighted_mistake_cost(predicted, label, args.under_penalty, args.over_penalty)
        costs = record.get("tier_cost")
        qualities = record.get("tier_quality")
        if isinstance(costs, dict) and isinstance(costs.get(predicted), (int, float)):
            selected_cost += float(costs[predicted]); cost_n += 1
        if isinstance(qualities, dict) and isinstance(qualities.get(predicted), (int, float)):
            selected_quality += float(qualities[predicted]); quality_n += 1

    report = {
        "records": total,
        "accuracy": (correct / total if total else None),
        "weighted_loss": total_loss,
        "thresholds": thresholds,
        "mean_selected_cost": (selected_cost / cost_n if cost_n else None),
        "mean_selected_quality": (selected_quality / quality_n if quality_n else None),
        "confusion": {expected: {predicted: confusion[(expected, predicted)] for predicted in ("fast", "standard", "strong")} for expected in ("fast", "standard", "strong")},
    }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
