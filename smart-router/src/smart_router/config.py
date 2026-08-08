from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer") from exc


def _float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError as exc:
        raise ValueError(f"{name} must be a number") from exc


@dataclass(frozen=True)
class TierConfig:
    model: str
    max_output_tokens: int
    context_limit: int
    supports_tools: bool
    supports_vision: bool


@dataclass(frozen=True)
class Settings:
    mode: str
    policy: str
    calibration_file: Path
    upstream_base_url: str
    upstream_api_key: str | None
    database_path: Path
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
    observation_enabled: bool
    observation_file: Path
    observation_max_bytes: int
    tiers: dict[str, TierConfig]

    @classmethod
    def from_env(cls) -> "Settings":
        mode = os.getenv("SMART_ROUTER_MODE", "observe").strip().lower()
        if mode not in {"observe", "route"}:
            raise ValueError("SMART_ROUTER_MODE must be observe or route")
        policy = os.getenv("SMART_ROUTER_POLICY", "heuristic").strip().lower()
        if policy not in {"heuristic", "calibrated"}:
            raise ValueError("SMART_ROUTER_POLICY must be heuristic or calibrated")
        secret = os.getenv("SMART_ROUTER_HMAC_SECRET", "")
        if len(secret) < 32:
            raise ValueError("SMART_ROUTER_HMAC_SECRET must be at least 32 characters")

        tiers = {
            "fast": TierConfig(
                model=os.getenv("SMART_ROUTER_FAST_MODEL", "combo-fast"),
                max_output_tokens=_int("SMART_ROUTER_FAST_MAX_TOKENS", 1024),
                context_limit=_int("SMART_ROUTER_FAST_CONTEXT_LIMIT", 32000),
                supports_tools=_bool("SMART_ROUTER_FAST_SUPPORTS_TOOLS", False),
                supports_vision=_bool("SMART_ROUTER_FAST_SUPPORTS_VISION", False),
            ),
            "standard": TierConfig(
                model=os.getenv("SMART_ROUTER_STANDARD_MODEL", "combo-standard"),
                max_output_tokens=_int("SMART_ROUTER_STANDARD_MAX_TOKENS", 4096),
                context_limit=_int("SMART_ROUTER_STANDARD_CONTEXT_LIMIT", 128000),
                supports_tools=_bool("SMART_ROUTER_STANDARD_SUPPORTS_TOOLS", True),
                supports_vision=_bool("SMART_ROUTER_STANDARD_SUPPORTS_VISION", False),
            ),
            "strong": TierConfig(
                model=os.getenv("SMART_ROUTER_STRONG_MODEL", "combo-strong"),
                max_output_tokens=_int("SMART_ROUTER_STRONG_MAX_TOKENS", 6144),
                context_limit=_int("SMART_ROUTER_STRONG_CONTEXT_LIMIT", 200000),
                supports_tools=_bool("SMART_ROUTER_STRONG_SUPPORTS_TOOLS", True),
                supports_vision=_bool("SMART_ROUTER_STRONG_SUPPORTS_VISION", True),
            ),
        }
        return cls(
            mode=mode,
            policy=policy,
            calibration_file=Path(os.getenv("SMART_ROUTER_CALIBRATION_FILE", "/policy/calibrated.json")),
            upstream_base_url=os.getenv("SMART_ROUTER_UPSTREAM_BASE_URL", "http://nine-router:20128/v1").rstrip("/"),
            upstream_api_key=os.getenv("SMART_ROUTER_UPSTREAM_API_KEY") or None,
            database_path=Path(os.getenv("SMART_ROUTER_DATABASE_PATH", "/data/router.sqlite3")),
            hmac_secret=secret,
            policy_version=os.getenv("SMART_ROUTER_POLICY_VERSION", "2"),
            observe_model=os.getenv("SMART_ROUTER_OBSERVE_MODEL", "ai"),
            fail_open_model=os.getenv("SMART_ROUTER_FAIL_OPEN_MODEL", "ai"),
            session_ttl_seconds=_int("SMART_ROUTER_SESSION_TTL_SECONDS", 2700),
            max_session_age_seconds=_int("SMART_ROUTER_MAX_SESSION_AGE_SECONDS", 43200),
            demotion_turns=_int("SMART_ROUTER_DEMOTION_TURNS", 5),
            connect_timeout_seconds=_float("SMART_ROUTER_CONNECT_TIMEOUT_SECONDS", 10),
            read_timeout_seconds=_float("SMART_ROUTER_READ_TIMEOUT_SECONDS", 600),
            max_request_bytes=_int("SMART_ROUTER_MAX_REQUEST_BYTES", 10485760),
            observation_enabled=_bool("SMART_ROUTER_OBSERVATION_ENABLED", True),
            observation_file=Path(os.getenv("SMART_ROUTER_OBSERVATION_FILE", "/data/observations.jsonl")),
            observation_max_bytes=_int("SMART_ROUTER_OBSERVATION_MAX_BYTES", 50 * 1024 * 1024),
            tiers=tiers,
        )
