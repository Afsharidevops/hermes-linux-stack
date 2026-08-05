import sqlite3

from smart_router.database import RouteStore
from smart_router.privacy import session_identity


def test_session_identity_is_hmac_and_does_not_contain_source(settings):
    synthetic_session = "telegram-user-test-12345"
    value, source = session_identity(
        {"X-Router-Session": synthetic_session},
        {"messages": []},
        settings.hmac_secret,
    )
    assert source == "router-header"
    assert value
    assert synthetic_session not in value


def test_database_stores_no_prompt_or_credential(settings):
    store = RouteStore(settings)
    session_hash, _ = session_identity(
        {"Authorization": "Bearer very-secret", "X-Router-Session": "private-user"},
        {"messages": [{"role": "user", "content": "private prompt"}]},
        settings.hmac_secret,
    )
    store.resolve(session_hash, "auto", "standard", "initial")
    raw = open(settings.database_path, "rb").read()
    assert b"very-secret" not in raw
    assert b"private-user" not in raw
    assert b"private prompt" not in raw
