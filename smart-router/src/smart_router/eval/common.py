from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from smart_router.routing import DEFAULT_WEIGHTS, RequestFacts, extract_facts, feature_flags

TIERS = ["fast", "standard", "strong"]
TIER_ORDER = {name: index for index, name in enumerate(TIERS)}


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid JSON: {exc}") from exc
            if not isinstance(value, dict):
                raise ValueError(f"{path}:{line_no}: expected JSON object")
            yield value


def flags_from_record(record: dict[str, Any]) -> dict[str, float]:
    if isinstance(record.get("features"), dict):
        flags = {key: float(record["features"].get(key, 0.0)) for key in DEFAULT_WEIGHTS}
        return flags
    if isinstance(record.get("facts"), dict):
        values = record["facts"]
        facts = RequestFacts(
            estimated_tokens=int(values.get("estimated_tokens", 1)),
            message_count=int(values.get("message_count", 0)),
            tools_present=bool(values.get("tools_present", False)),
            tool_count=int(values.get("tool_count", 0)),
            large_tool_schema=bool(values.get("large_tool_schema", False)),
            large_tool_results=bool(values.get("large_tool_results", False)),
            vision_present=bool(values.get("vision_present", False)),
            structured_output=bool(values.get("structured_output", False)),
            code_block_count=int(values.get("code_block_count", 0)),
            referenced_file_count=int(values.get("referenced_file_count", 0)),
            complex_language=bool(values.get("complex_language", False)),
            simple_language=bool(values.get("simple_language", False)),
            failure_language=bool(values.get("failure_language", False)),
        )
        return feature_flags(facts)
    body = record.get("body", record)
    if isinstance(body, dict) and "messages" in body:
        return feature_flags(extract_facts(body))
    raise ValueError("record must contain features, facts, or an OpenAI body/messages object")


def score(flags: dict[str, float], weights: dict[str, float]) -> float:
    return sum(float(flags.get(key, 0.0)) * float(value) for key, value in weights.items())


def tier_for_score(value: float, fast_max: float, standard_max: float) -> str:
    if value <= fast_max:
        return "fast"
    if value <= standard_max:
        return "standard"
    return "strong"


def weighted_mistake_cost(predicted: str, expected: str, under_penalty: float = 3.0, over_penalty: float = 1.0) -> float:
    delta = TIER_ORDER[predicted] - TIER_ORDER[expected]
    if delta < 0:
        return abs(delta) * under_penalty
    return delta * over_penalty
