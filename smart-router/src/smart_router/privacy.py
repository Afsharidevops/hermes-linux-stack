from __future__ import annotations

import hashlib
import hmac
import json
from typing import Any


def pseudonym(secret: str, value: str) -> str:
    return hmac.new(secret.encode(), value.encode(), hashlib.sha256).hexdigest()[:32]


def stable_session_id(secret: str, headers: dict[str, str], body: dict[str, Any]) -> tuple[str | None, str]:
    # Prefer explicit, stable conversation/user identifiers. Never persist the raw value.
    candidates = (
        ("x-session-id", headers.get("x-session-id")),
        ("x-conversation-id", headers.get("x-conversation-id")),
        ("x-chat-id", headers.get("x-chat-id")),
        ("x-openwebui-chat-id", headers.get("x-openwebui-chat-id")),
        ("x-openwebui-user-id", headers.get("x-openwebui-user-id")),
        ("x-user-id", headers.get("x-user-id")),
        ("body-user", body.get("user")),
    )
    for source, value in candidates:
        if isinstance(value, str) and value.strip():
            return pseudonym(secret, value.strip()), source
    # Do not make a caller-wide API key into a sticky conversation: one difficult
    # chat must not promote every unrelated chat sharing that credential.
    return None, "none"


def safe_json_size(value: Any) -> int:
    try:
        return len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode())
    except Exception:
        return 0
