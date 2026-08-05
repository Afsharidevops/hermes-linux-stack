from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

from .config import Settings

AUTO_ALIASES = {
    "auto": None,
    "auto-fast": "fast",
    "auto-standard": "standard",
    "auto-strong": "strong",
}
TIER_RANK = {"fast": 0, "standard": 1, "strong": 2}
COMPLEX_TERMS = (
    "architecture",
    "security review",
    "root cause",
    "production incident",
    "multi-file",
    "migration",
    "refactor",
    "race condition",
    "performance investigation",
    "threat model",
)
SIMPLE_TERMS = (
    "translate",
    "grammar",
    "rewrite",
    "reformat",
    "extract",
    "reply briefly",
    "summarize briefly",
)
FAILURE_TERMS = ("failed", "failure", "didn't work", "did not work", "try again", "error")


@dataclass(frozen=True)
class RequestFacts:
    estimated_message_tokens: int
    estimated_tool_schema_tokens: int
    estimated_tool_result_tokens: int
    estimated_total_tokens: int
    has_tools: bool
    has_vision: bool
    structured_output: bool
    code_blocks: int
    referenced_files: int
    text: str


@dataclass(frozen=True)
class Decision:
    proposed_tier: str
    proposed_model: str
    score: int
    reasons: tuple[str, ...]
    facts: RequestFacts


def analyze_request(body: dict[str, Any]) -> RequestFacts:
    messages = body.get("messages") or []
    text_parts: list[str] = []
    non_tool_parts: list[str] = []
    message_chars = 0
    tool_result_chars = 0
    has_vision = False

    for message in messages:
        if not isinstance(message, dict):
            continue
        content = message.get("content", "")
        serialized = _stable_text(content)
        if message.get("role") == "tool":
            tool_result_chars += len(serialized)
        else:
            message_chars += len(serialized)
            non_tool_parts.append(serialized)
        text_parts.append(serialized)
        has_vision = has_vision or _contains_image(content)

    tools = body.get("tools") or []
    tool_chars = len(json.dumps(tools, sort_keys=True, separators=(",", ":")))
    text = "\n".join(text_parts).lower()
    non_tool_text = "\n".join(non_tool_parts).lower()
    code_chars = sum(len(block) for block in re.findall(r"```.*?```", non_tool_text, re.S))
    message_tokens = max(1, (message_chars - code_chars) // 4 + code_chars // 3)
    tool_schema_tokens = tool_chars * 2 // 7
    tool_result_tokens = tool_result_chars // 3
    total = message_tokens + tool_schema_tokens + tool_result_tokens
    referenced_files = len(
        set(re.findall(r"(?:^|\s)(?:[\w.-]+/)+[\w.-]+", text, re.M))
    )
    response_format = body.get("response_format")
    structured = bool(
        response_format
        and isinstance(response_format, dict)
        and response_format.get("type") in {"json_object", "json_schema"}
    )
    return RequestFacts(
        estimated_message_tokens=message_tokens,
        estimated_tool_schema_tokens=tool_schema_tokens,
        estimated_tool_result_tokens=tool_result_tokens,
        estimated_total_tokens=total,
        has_tools=bool(tools),
        has_vision=has_vision,
        structured_output=structured,
        code_blocks=text.count("```" ) // 2,
        referenced_files=referenced_files,
        text=text,
    )


def decide(
    body: dict[str, Any],
    settings: Settings,
    requested_tier: str | None = None,
) -> Decision:
    facts = analyze_request(body)
    score = 0
    reasons: list[str] = []

    if facts.estimated_total_tokens > 8_000:
        score += 2
        reasons.append("context_gt_8000")
    if facts.estimated_total_tokens > 25_000:
        score += 2
        reasons.append("context_gt_25000")
    if facts.estimated_total_tokens > 50_000:
        score += 3
        reasons.append("context_gt_50000")
    if facts.has_tools:
        score += 1
        reasons.append("tools_present")
    if facts.estimated_tool_schema_tokens > 2_000:
        score += 1
        reasons.append("large_tool_schema")
    if facts.estimated_tool_result_tokens > 2_000:
        score += 1
        reasons.append("large_tool_results")
    if facts.code_blocks > 2:
        score += 1
        reasons.append("multiple_code_blocks")
    if facts.referenced_files > 3:
        score += 2
        reasons.append("multiple_files")
    if facts.structured_output:
        score += 1
        reasons.append("structured_output")
    if any(term in facts.text for term in COMPLEX_TERMS):
        score += 2
        reasons.append("complex_intent")
    if any(term in facts.text for term in SIMPLE_TERMS):
        score -= 2
        reasons.append("simple_intent")
    if any(term in facts.text for term in FAILURE_TERMS):
        score += 2
        reasons.append("failure_language")

    tier = requested_tier or ("fast" if score <= 0 else "standard" if score <= 5 else "strong")
    tier = _apply_capability_gates(tier, facts, settings, reasons)
    return Decision(
        proposed_tier=tier,
        proposed_model=settings.tier(tier).model,
        score=score,
        reasons=tuple(reasons or [f"default_{tier}"]),
        facts=facts,
    )


def _apply_capability_gates(
    tier: str, facts: RequestFacts, settings: Settings, reasons: list[str]
) -> str:
    if facts.has_vision:
        reasons.append("vision_required")
    requested_rank = TIER_RANK[tier]
    for rank in range(requested_rank, TIER_RANK["strong"] + 1):
        candidate_name = _tier_name(rank)
        candidate = settings.tier(candidate_name)
        if facts.has_tools and not candidate.supports_tools:
            continue
        if facts.has_vision and not candidate.supports_vision:
            continue
        if facts.estimated_total_tokens + candidate.max_output > candidate.max_context:
            continue
        if candidate_name != tier:
            reasons.append(f"capability_upgrade_{tier}_to_{candidate_name}")
        return candidate_name
    raise ValueError("no configured tier can satisfy request capabilities and context")


def _tier_name(rank: int) -> str:
    return ("fast", "standard", "strong")[rank]


def _contains_image(value: Any) -> bool:
    if isinstance(value, list):
        return any(_contains_image(item) for item in value)
    if isinstance(value, dict):
        kind = str(value.get("type", "")).lower()
        mime = str(value.get("mime_type", value.get("media_type", ""))).lower()
        return kind in {"image", "image_url", "input_image"} or mime.startswith("image/") or any(
            _contains_image(child) for child in value.values()
        )
    return False


def _stable_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
