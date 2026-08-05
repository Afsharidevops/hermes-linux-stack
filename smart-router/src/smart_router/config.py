from __future__ import annotations

import math
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class TierConfig:
    model: str
    max_output: int
    supports_tools: bool
    supports_vision: bool
    max_context: int


@dataclass(frozen=True)
class Settings:
    mode: str
    upstream_base_url: str
    database_path: str
    hmac_secret: str
    policy_version: str
    observe_model: str
    fail_open_model: str
    session_ttl_seconds: int
    max_session_age_seconds: int
    demotion_turns: int
    connect_timeout_seconds: float
    read_timeout_seconds: float
    max_request_bytes: int
    preferred_token_field: str
    fast: TierConfig
    standard: TierConfig
    strong: TierConfig

    @classmethod
    def from_env(cls) -> "Settings":
        mode = os.getenv("SMART_ROUTER_MODE", "observe").lower()
        if mode not in {"observe", "route"}:
            raise ValueError("SMART_ROUTER_MODE must be observe or route")
        preferred = os.getenv("SMART_ROUTER_PREFERRED_TOKEN_FIELD", "max_tokens")
        if preferred not in {"max_tokens", "max_completion_tokens"}:
            raise ValueError("SMART_ROUTER_PREFERRED_TOKEN_FIELD is invalid")
        secret = os.getenv("SMART_ROUTER_HMAC_SECRET", "")
        if (
            len(secret.strip()) < 32
            or secret.startswith("CHANGE_ME")
            or len(set(secret.strip())) < 8
        ):
            raise ValueError("SMART_ROUTER_HMAC_SECRET must be a strong secret of at least 32 characters")

        settings = cls(
            mode=mode,
            upstream_base_url=os.getenv(
                "SMART_ROUTER_UPSTREAM_BASE_URL", "http://nine-router:20128/v1"
            ).rstrip("/"),
            database_path=os.getenv("SMART_ROUTER_DATABASE_PATH", "/data/router.sqlite3"),
            hmac_secret=secret,
            policy_version=_required_text("SMART_ROUTER_POLICY_VERSION", "1"),
            observe_model=_required_text("SMART_ROUTER_OBSERVE_MODEL", "ai"),
            fail_open_model=_required_text("SMART_ROUTER_FAIL_OPEN_MODEL", "ai"),
            session_ttl_seconds=_positive_int("SMART_ROUTER_SESSION_TTL_SECONDS", 2700),
            max_session_age_seconds=_positive_int("SMART_ROUTER_MAX_SESSION_AGE_SECONDS", 43200),
            demotion_turns=_positive_int("SMART_ROUTER_DEMOTION_TURNS", 5),
            connect_timeout_seconds=_positive_float("SMART_ROUTER_CONNECT_TIMEOUT_SECONDS", 10),
            read_timeout_seconds=_positive_float("SMART_ROUTER_READ_TIMEOUT_SECONDS", 600),
            max_request_bytes=_positive_int("SMART_ROUTER_MAX_REQUEST_BYTES", 10485760),
            preferred_token_field=preferred,
            fast=_tier("FAST", "combo-fast", 1024, False, False, 32000),
            standard=_tier("STANDARD", "combo-standard", 4096, True, False, 128000),
            strong=_tier("STRONG", "combo-strong", 6144, True, True, 200000),
        )
        if not any(tier.supports_tools for tier in (settings.fast, settings.standard, settings.strong)):
            raise ValueError("at least one tier must support tools")
        if not any(tier.supports_vision for tier in (settings.fast, settings.standard, settings.strong)):
            raise ValueError("at least one tier must support vision")
        return settings

    def tier(self, name: str) -> TierConfig:
        return {"fast": self.fast, "standard": self.standard, "strong": self.strong}[name]


def _tier(
    prefix: str,
    default_model: str,
    default_output: int,
    default_tools: bool,
    default_vision: bool,
    default_context: int,
) -> TierConfig:
    return TierConfig(
        model=_required_text(f"SMART_ROUTER_{prefix}_MODEL", default_model),
        max_output=_positive_int(f"SMART_ROUTER_{prefix}_MAX_TOKENS", default_output),
        supports_tools=_bool_env(f"SMART_ROUTER_{prefix}_SUPPORTS_TOOLS", default_tools),
        supports_vision=_bool_env(f"SMART_ROUTER_{prefix}_SUPPORTS_VISION", default_vision),
        max_context=_positive_int(f"SMART_ROUTER_{prefix}_MAX_CONTEXT", default_context),
    )


def _required_text(name: str, default: str) -> str:
    value = os.getenv(name, default).strip()
    if not value:
        raise ValueError(f"{name} must not be empty")
    return value


def _positive_int(name: str, default: int) -> int:
    value = int(os.getenv(name, str(default)))
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


def _positive_float(name: str, default: float) -> float:
    value = float(os.getenv(name, str(default)))
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be a finite positive number")
    return value


def _bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    normalized = value.lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be true or false")
