from dataclasses import replace

from smart_router.database import RouteStore


def test_sticky_route_promotes_and_demotes_conservatively(settings):
    store = RouteStore(settings)
    first = store.resolve("session", "auto", "standard", "initial", now=100)
    assert first.tier == "standard"
    promoted = store.resolve("session", "auto", "strong", "complex", now=101)
    assert promoted.tier == "strong"
    assert promoted.action == "promoted"
    assert store.resolve("session", "auto", "standard", "simple", now=102).tier == "strong"
    assert store.resolve("session", "auto", "standard", "simple", now=103).tier == "strong"
    demoted = store.resolve("session", "auto", "standard", "simple", now=104)
    assert demoted.tier == "standard"
    assert demoted.action == "demoted"


def test_policy_version_invalidates_route(settings):
    RouteStore(settings).resolve("session", "auto", "strong", "initial", now=100)
    changed = replace(settings, policy_version="test-v2")
    result = RouteStore(changed).resolve("session", "auto", "fast", "new-policy", now=101)
    assert result.tier == "fast"
    assert result.hit is False


def test_expired_route_is_replaced(settings):
    short = replace(settings, session_ttl_seconds=10)
    store = RouteStore(short)
    store.resolve("session", "auto", "strong", "initial", now=100)
    result = store.resolve("session", "auto", "fast", "expired", now=111)
    assert result.tier == "fast"
    assert result.hit is False
