from smart_router.database import SessionStore


def test_sticky_promotes_immediately_demotes_later(tmp_path):
    store = SessionStore(tmp_path / "db.sqlite3")
    args = dict(policy_version="2", ttl_seconds=100, max_age_seconds=1000, demotion_turns=3)
    assert store.choose("s", "fast", now=10, **args).tier == "fast"
    assert store.choose("s", "strong", now=11, **args).tier == "strong"
    assert store.choose("s", "fast", now=12, **args).tier == "strong"
    assert store.choose("s", "fast", now=13, **args).tier == "strong"
    result = store.choose("s", "fast", now=14, **args)
    assert result.tier == "fast"
    assert result.action == "demoted"


def test_policy_version_invalidates_session(tmp_path):
    store = SessionStore(tmp_path / "db.sqlite3")
    base = dict(ttl_seconds=100, max_age_seconds=1000, demotion_turns=5)
    store.choose("s", "strong", policy_version="1", now=10, **base)
    result = store.choose("s", "fast", policy_version="2", now=11, **base)
    assert result.tier == "fast"
    assert result.action == "new_or_expired"
