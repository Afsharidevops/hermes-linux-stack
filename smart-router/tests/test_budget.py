from smart_router.budget import apply_output_budget


def test_budget_never_increases_client_limit():
    body, meta = apply_output_budget({"max_tokens": 200}, 1024)
    assert body["max_tokens"] == 200
    assert meta["applied"] == 200


def test_budget_clamps_and_supports_completion_field():
    body, _ = apply_output_budget({"max_completion_tokens": 9000}, 4096)
    assert body["max_completion_tokens"] == 4096
    assert "max_tokens" not in body
