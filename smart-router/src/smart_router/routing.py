from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from .config import Settings, TierConfig
from .privacy import safe_json_size

TIER_ORDER = {"fast": 0, "standard": 1, "strong": 2}
ORDER_TIER = {value: key for key, value in TIER_ORDER.items()}
AUTO_ALIASES = {"auto": None, "auto-fast": "fast", "auto-standard": "standard", "auto-strong": "strong"}

DEFAULT_WEIGHTS: dict[str, float] = {
    "context_gt_8k": 2.0,
    "context_gt_25k": 2.0,
    "context_gt_50k": 3.0,
    "tools_present": 1.0,
    "large_tool_schema": 1.0,
    "large_tool_results": 1.0,
    "multiple_code_blocks": 1.0,
    "many_referenced_files": 2.0,
    "structured_output": 1.0,
    "complex_language": 2.0,
    "simple_language": -2.0,
    "failure_language": 2.0,
}
DEFAULT_THRESHOLDS = {"fast_max": 0.0, "standard_max": 5.0}

COMPLEX_TERMS = re.compile(
    r"\b(architect(?:ure)?|security|threat model|migration|migrate|refactor|debug|root cause|"
    r"performance|optimi[sz]e|distributed|concurrency|race condition|database schema|"
    r"kubernetes|terraform|docker compose|production|incident|benchmark|evaluate|compare|"
    r"multi[- ]step|plan and implement|analy[sz]e)\b",
    re.I,
)
SIMPLE_TERMS = re.compile(
    r"\b(translate|define|meaning|spell|rewrite this|fix grammar|summari[sz]e briefly|"
    r"one sentence|short answer|yes or no|hello|thanks)\b",
    re.I,
)
FAILURE_TERMS = re.compile(
    r"\b(error|exception|failed|failure|broken|doesn'?t work|not working|traceback|timeout|"
    r"segfault|panic|regression|retry|still failing)\b",
    re.I,
)
FILE_REF = re.compile(r"(?:^|\s)(?:[\w.-]+/)+[\w.-]+|\b[\w.-]+\.(?:py|js|ts|tsx|jsx|go|rs|java|yaml|yml|toml|json|sh|md|sql)\b", re.I)
CODE_FENCE = re.compile(r"```")


@dataclass(frozen=True)
class RequestFacts:
    estimated_tokens: int
    message_count: int
    tools_present: bool
    tool_count: int
    large_tool_schema: bool
    large_tool_results: bool
    vision_present: bool
    structured_output: bool
    code_block_count: int
    referenced_file_count: int
    complex_language: bool
    simple_language: bool
    failure_language: bool


@dataclass(frozen=True)
class PolicyResult:
    tier: str
    score: float
    reasons: list[str]
    policy: str


@dataclass(frozen=True)
class Decision:
    requested_model: str
    proposed_tier: str
    selected_tier: str
    selected_model: str
    score: float
    reasons: list[str]
    policy: str
    capability_upgraded: bool
    facts: RequestFacts

    def safe_dict(self) -> dict[str, Any]:
        result = asdict(self)
        result["facts"] = asdict(self.facts)
        return result


def _content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        pieces: list[str] = []
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") in {"text", "input_text"} and isinstance(item.get("text"), str):
                pieces.append(item["text"])
        return "\n".join(pieces)
    return ""


def _has_vision(content: Any) -> bool:
    if not isinstance(content, list):
        return False
    for item in content:
        if not isinstance(item, dict):
            continue
        if item.get("type") in {"image_url", "input_image", "image"}:
            return True
    return False


def extract_facts(body: dict[str, Any]) -> RequestFacts:
    messages = body.get("messages") if isinstance(body.get("messages"), list) else []
    text_parts: list[str] = []
    vision = False
    large_tool_results = False
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        text = _content_text(content)
        if text:
            text_parts.append(text)
        vision = vision or _has_vision(content)
        if msg.get("role") == "tool" and safe_json_size(msg) > 8000:
            large_tool_results = True

    text = "\n".join(text_parts)
    tools = body.get("tools") if isinstance(body.get("tools"), list) else []
    tool_schema_size = safe_json_size(tools)
    # Approximate token count without sending prompt text to another model/tokenizer.
    request_bytes = safe_json_size(messages) + tool_schema_size
    estimated_tokens = max(1, (request_bytes + 3) // 4)
    response_format = body.get("response_format")
    structured_output = bool(response_format) or bool(body.get("json_schema"))
    return RequestFacts(
        estimated_tokens=estimated_tokens,
        message_count=len(messages),
        tools_present=bool(tools),
        tool_count=len(tools),
        large_tool_schema=tool_schema_size > 12000,
        large_tool_results=large_tool_results,
        vision_present=vision,
        structured_output=structured_output,
        code_block_count=len(CODE_FENCE.findall(text)) // 2,
        referenced_file_count=len(FILE_REF.findall(text)),
        complex_language=bool(COMPLEX_TERMS.search(text)),
        simple_language=bool(SIMPLE_TERMS.search(text)),
        failure_language=bool(FAILURE_TERMS.search(text)),
    )


def feature_flags(facts: RequestFacts) -> dict[str, float]:
    return {
        "context_gt_8k": float(facts.estimated_tokens > 8000),
        "context_gt_25k": float(facts.estimated_tokens > 25000),
        "context_gt_50k": float(facts.estimated_tokens > 50000),
        "tools_present": float(facts.tools_present),
        "large_tool_schema": float(facts.large_tool_schema),
        "large_tool_results": float(facts.large_tool_results),
        "multiple_code_blocks": float(facts.code_block_count > 2),
        "many_referenced_files": float(facts.referenced_file_count > 3),
        "structured_output": float(facts.structured_output),
        "complex_language": float(facts.complex_language),
        "simple_language": float(facts.simple_language),
        "failure_language": float(facts.failure_language),
    }


def _load_calibration(path: Path) -> tuple[dict[str, float], dict[str, float], str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    weights = dict(DEFAULT_WEIGHTS)
    thresholds = dict(DEFAULT_THRESHOLDS)
    for name, value in payload.get("weights", {}).items():
        if name in weights:
            weights[name] = float(value)
    for name in ("fast_max", "standard_max"):
        if name in payload.get("thresholds", {}):
            thresholds[name] = float(payload["thresholds"][name])
    if thresholds["fast_max"] >= thresholds["standard_max"]:
        raise ValueError("calibrated fast_max must be below standard_max")
    return weights, thresholds, str(payload.get("name", path.stem))


class PolicyEngine:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.weights = dict(DEFAULT_WEIGHTS)
        self.thresholds = dict(DEFAULT_THRESHOLDS)
        self.name = "heuristic-v1"
        if settings.policy == "calibrated":
            self.weights, self.thresholds, loaded_name = _load_calibration(settings.calibration_file)
            self.name = f"calibrated:{loaded_name}"

    def evaluate(self, facts: RequestFacts) -> PolicyResult:
        flags = feature_flags(facts)
        score = sum(self.weights[key] * value for key, value in flags.items())
        reasons = [f"{key}:{self.weights[key]:+g}" for key, value in flags.items() if value]
        if score <= self.thresholds["fast_max"]:
            tier = "fast"
        elif score <= self.thresholds["standard_max"]:
            tier = "standard"
        else:
            tier = "strong"
        return PolicyResult(tier=tier, score=score, reasons=reasons, policy=self.name)

    def describe(self) -> dict[str, Any]:
        return {"name": self.name, "weights": self.weights, "thresholds": self.thresholds}


def _tier_can_handle(tier: TierConfig, facts: RequestFacts) -> bool:
    if facts.tools_present and not tier.supports_tools:
        return False
    if facts.vision_present and not tier.supports_vision:
        return False
    # Leave a small output/system overhead margin rather than route at exact ceiling.
    if facts.estimated_tokens > int(tier.context_limit * 0.92):
        return False
    return True


def apply_capability_gate(proposed: str, facts: RequestFacts, tiers: dict[str, TierConfig]) -> tuple[str, bool, list[str]]:
    start = TIER_ORDER[proposed]
    reasons: list[str] = []
    for index in range(start, 3):
        tier_name = ORDER_TIER[index]
        if _tier_can_handle(tiers[tier_name], facts):
            upgraded = index != start
            if upgraded:
                reasons.append(f"capability_gate:{proposed}->{tier_name}")
            return tier_name, upgraded, reasons
    # Strong is the final safety tier even if operator configuration claims it lacks a capability.
    reasons.append("capability_gate:no_declared_tier_satisfies_request")
    return "strong", proposed != "strong", reasons


def decide(body: dict[str, Any], settings: Settings, engine: PolicyEngine | None = None) -> Decision:
    engine = engine or PolicyEngine(settings)
    requested_model = str(body.get("model") or "auto")
    forced = AUTO_ALIASES.get(requested_model.lower(), "not-auto")
    facts = extract_facts(body)
    if forced != "not-auto" and forced is not None:
        policy_result = PolicyResult(tier=forced, score=0.0, reasons=[f"alias:{requested_model}"], policy="explicit-alias")
    else:
        policy_result = engine.evaluate(facts)
    gated, upgraded, gate_reasons = apply_capability_gate(policy_result.tier, facts, settings.tiers)
    return Decision(
        requested_model=requested_model,
        proposed_tier=policy_result.tier,
        selected_tier=gated,
        selected_model=settings.tiers[gated].model,
        score=policy_result.score,
        reasons=policy_result.reasons + gate_reasons,
        policy=policy_result.policy,
        capability_upgraded=upgraded,
        facts=facts,
    )
