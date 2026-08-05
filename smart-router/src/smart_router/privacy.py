from __future__ import annotations

import base64
import hashlib
import hmac
import json
from typing import Any, Mapping


def session_identity(
    headers: Mapping[str, str], body: dict[str, Any], secret: str
) -> tuple[str | None, str]:
    candidates = (
        ("router-header", _header(headers, "x-router-session")),
        ("hermes-header", _header(headers, "x-hermes-session-key")),
        ("session-id", body.get("session_id")),
        ("metadata", (body.get("metadata") or {}).get("conversation_id") if isinstance(body.get("metadata"), dict) else None),
        ("prompt-cache-key", body.get("prompt_cache_key")),
        ("user", body.get("user")),
    )
    for source, value in candidates:
        if isinstance(value, str) and value.strip():
            return _digest(secret, source, value.strip()), source

    fingerprint = _conversation_fingerprint(body)
    if fingerprint:
        credential = _credential_namespace(headers, secret)
        return _digest(secret, "fingerprint", credential + "\0" + fingerprint), "fingerprint"
    return None, "none"


def _credential_namespace(headers: Mapping[str, str], secret: str) -> str:
    for name in ("authorization", "x-api-key", "x-goog-api-key"):
        value = _header(headers, name)
        if value:
            return _digest(secret, "credential", name + "\0" + value)
    return "anonymous"


def _conversation_fingerprint(body: dict[str, Any]) -> str | None:
    messages = body.get("messages")
    if not isinstance(messages, list):
        return None
    stable: list[dict[str, Any]] = []
    for message in messages:
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        if role not in {"system", "user"}:
            continue
        content = message.get("content")
        if content in (None, "", []):
            continue
        stable.append({"role": role, "content": content})
        if role == "user":
            break
    if not stable:
        return None
    raw = json.dumps(stable, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode()).hexdigest()


def _digest(secret: str, domain: str, value: str) -> str:
    raw = hmac.new(
        secret.encode(),
        ("smart-router/v0.1/" + domain + "\0" + value).encode(),
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _header(headers: Mapping[str, str], name: str) -> str | None:
    for key, value in headers.items():
        if key.lower() == name:
            return value
    return None
