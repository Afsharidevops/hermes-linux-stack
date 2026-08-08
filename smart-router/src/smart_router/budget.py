from __future__ import annotations

from typing import Any


def apply_output_budget(body: dict[str, Any], tier_limit: int) -> tuple[dict[str, Any], dict[str, Any]]:
    out = dict(body)
    field = "max_completion_tokens" if "max_completion_tokens" in out else "max_tokens"
    requested = out.get(field)
    if isinstance(requested, int) and requested > 0:
        applied = min(requested, tier_limit)
    else:
        applied = tier_limit
    out[field] = applied
    return out, {"field": field, "requested": requested, "limit": tier_limit, "applied": applied}
