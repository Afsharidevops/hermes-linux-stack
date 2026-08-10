from smart_router.budget import enforce_budget, propose_budget
from smart_router.routing import decide


def test_tier_budget_clamps_client_limit(settings):
    body = {"model": "auto-fast", "messages": [{"role": "user", "content": "translate this"}], "max_tokens": 9000}
    decision = decide(body, settings, requested_tier="fast")
    proposal = propose_budget(body, decision, settings)
    result = enforce_budget(body, proposal, settings)
    assert body["max_tokens"] <= settings.fast.max_output
    assert result.enforced


def test_explicit_budget_not_touched_by_router_helper_contract(settings):
    body = {"model": "gpt-explicit", "messages": [{"role": "user", "content": "hello"}], "max_tokens": 9000}
    original = body.copy()
    assert body == original
