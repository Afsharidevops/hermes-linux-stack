from dataclasses import replace

from smart_router.routing import decide


def test_simple_translation_is_fast(settings):
    decision = decide({"model": "auto", "messages": [{"role": "user", "content": "Translate hello to French"}]}, settings)
    assert decision.proposed_tier == "fast"


def test_tools_upgrade_forced_fast_to_standard(settings):
    body = {
        "model": "auto-fast",
        "messages": [{"role": "user", "content": "Read the repository"}],
        "tools": [{"type": "function", "function": {"name": "read"}}],
    }
    decision = decide(body, settings, requested_tier="fast")
    assert decision.proposed_tier == "standard"
    assert decision.capability_upgrade == "tools"


def test_vision_upgrades_to_strong(settings):
    body = {
        "model": "auto",
        "messages": [{"role": "user", "content": [{"type": "image_url", "image_url": {"url": "data:image/png;base64,AA"}}]}],
    }
    decision = decide(body, settings)
    assert decision.proposed_tier == "strong"
    assert decision.capability_upgrade == "vision"


def test_context_gate_is_authoritative(settings):
    small = replace(settings, fast=replace(settings.fast, max_context=100), standard=replace(settings.standard, max_context=200))
    body = {"model": "auto-fast", "messages": [{"role": "user", "content": "x" * 1000}], "max_tokens": 300}
    decision = decide(body, small, requested_tier="fast")
    assert decision.proposed_tier == "strong"
    assert decision.capability_upgrade == "context"


def test_auto_strong_stays_strong(settings):
    body = {"model": "auto-strong", "messages": [{"role": "user", "content": "hi"}]}
    assert decide(body, settings, requested_tier="strong").proposed_tier == "strong"
