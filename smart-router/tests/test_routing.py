from dataclasses import replace

from smart_router.budget import enforce_budget, propose_budget
from smart_router.routing import decide


def test_simple_request_uses_fast(settings):
    decision = decide({"messages": [{"role": "user", "content": "translate hello"}]}, settings)
    assert decision.proposed_tier == "fast"


def test_tools_upgrade_fast_to_standard(settings):
    body = {
        "messages": [{"role": "user", "content": "translate hello"}],
        "tools": [{"type": "function", "function": {"name": "read"}}],
    }
    decision = decide(body, settings, "fast")
    assert decision.proposed_tier == "standard"
    assert "capability_upgrade_fast_to_standard" in decision.reasons


def test_vision_upgrades_to_strong(settings):
    body = {
        "messages": [
            {
                "role": "user",
                "content": [{"type": "image_url", "image_url": {"url": "x"}}],
            }
        ]
    }
    assert decide(body, settings).proposed_tier == "strong"


def test_budget_never_increases_client_limit(settings):
    body = {"max_tokens": 500, "messages": [{"role": "user", "content": "hi"}]}
    proposal = propose_budget(body, decide(body, settings, "strong"), settings)
    result = enforce_budget(body, proposal, settings)
    assert body["max_tokens"] == 500
    assert result.enforced is False


def test_budget_clamps_in_route_mode(settings):
    body = {"max_completion_tokens": 9000, "messages": [{"role": "user", "content": "hi"}]}
    proposal = propose_budget(body, decide(body, settings, "standard"), settings)
    result = enforce_budget(body, proposal, settings)
    assert body["max_completion_tokens"] == 4096
    assert result.enforced is True
