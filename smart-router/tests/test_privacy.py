from smart_router.observations import ObservationWriter
from smart_router.privacy import pseudonym, stable_session_id


def test_session_id_is_pseudonymous():
    secret = "x" * 64
    value, source = stable_session_id(secret, {"x-session-id": "raw-session"}, {})
    assert value != "raw-session"
    assert len(value) == 32
    assert source == "x-session-id"
    assert value == pseudonym(secret, "raw-session")


def test_observation_writer_only_writes_given_safe_metadata(tmp_path):
    path = tmp_path / "obs.jsonl"
    writer = ObservationWriter(path, 10000, True)
    writer.write({"event": "decision", "facts": {"estimated_tokens": 12}})
    text = path.read_text()
    assert "estimated_tokens" in text
    assert "prompt" not in text


def test_no_stable_identifier_disables_cross_chat_stickiness():
    session, source = stable_session_id("x" * 64, {"authorization": "Bearer shared"}, {})
    assert session is None
    assert source == "none"
