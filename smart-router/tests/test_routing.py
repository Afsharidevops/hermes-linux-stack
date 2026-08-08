import json

from smart_router.config import Settings
from smart_router.routing import PolicyEngine, apply_capability_gate, decide, extract_facts


def test_simple_request_routes_fast():
    settings = Settings.from_env()
    body = {"model": "auto", "messages": [{"role": "user", "content": "Translate this sentence."}]}
    decision = decide(body, settings)
    assert decision.proposed_tier == "fast"
    assert decision.selected_tier == "fast"


def test_tools_upgrade_fast_to_standard(monkeypatch):
    settings = Settings.from_env()
    body = {
        "model": "auto-fast",
        "messages": [{"role": "user", "content": "hello"}],
        "tools": [{"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}],
    }
    decision = decide(body, settings)
    assert decision.proposed_tier == "fast"
    assert decision.selected_tier == "standard"
    assert decision.capability_upgraded


def test_vision_upgrades_to_strong():
    settings = Settings.from_env()
    body = {"model": "auto", "messages": [{"role": "user", "content": [{"type": "text", "text": "What is here?"}, {"type": "image_url", "image_url": {"url": "data:image/png;base64,AA=="}}]}]}
    decision = decide(body, settings)
    assert decision.selected_tier == "strong"


def test_calibrated_policy_loads(monkeypatch, tmp_path):
    policy = tmp_path / "calibrated.json"
    policy.write_text(json.dumps({"name": "test", "weights": {"complex_language": 8}, "thresholds": {"fast_max": 0, "standard_max": 5}}))
    monkeypatch.setenv("SMART_ROUTER_POLICY", "calibrated")
    monkeypatch.setenv("SMART_ROUTER_CALIBRATION_FILE", str(policy))
    settings = Settings.from_env()
    engine = PolicyEngine(settings)
    body = {"model": "auto", "messages": [{"role": "user", "content": "Analyze the architecture."}]}
    assert decide(body, settings, engine).proposed_tier == "strong"

def test_virtual_aliases_are_defined():
    from smart_router.routing import AUTO_ALIASES
    assert set(AUTO_ALIASES) == {"auto", "auto-fast", "auto-standard", "auto-strong"}
