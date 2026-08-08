import os

import pytest


@pytest.fixture(autouse=True)
def router_env(monkeypatch, tmp_path):
    monkeypatch.setenv("SMART_ROUTER_HMAC_SECRET", "x" * 64)
    monkeypatch.setenv("SMART_ROUTER_DATABASE_PATH", str(tmp_path / "router.sqlite3"))
    monkeypatch.setenv("SMART_ROUTER_OBSERVATION_FILE", str(tmp_path / "observations.jsonl"))
    monkeypatch.setenv("SMART_ROUTER_CALIBRATION_FILE", str(tmp_path / "calibrated.json"))


@pytest.fixture
def settings(router_env):
    from smart_router.config import Settings

    return Settings.from_env()
