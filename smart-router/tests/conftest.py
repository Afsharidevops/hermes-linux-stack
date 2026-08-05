from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1] / "src"))

from smart_router.config import Settings, TierConfig


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return Settings(
        mode="observe",
        upstream_base_url="http://upstream/v1",
        database_path=str(tmp_path / "router.sqlite3"),
        hmac_secret="test-secret-that-is-at-least-32-characters",
        policy_version="test-v1",
        observe_model="ai",
        fail_open_model="ai",
        session_ttl_seconds=2700,
        max_session_age_seconds=43200,
        demotion_turns=3,
        connect_timeout_seconds=1,
        read_timeout_seconds=10,
        max_request_bytes=1024 * 1024,
        preferred_token_field="max_tokens",
        fast=TierConfig("combo-fast", 1024, False, False, 32000),
        standard=TierConfig("combo-standard", 4096, True, False, 128000),
        strong=TierConfig("combo-strong", 6144, True, True, 200000),
    )
