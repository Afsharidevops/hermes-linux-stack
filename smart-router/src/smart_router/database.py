from __future__ import annotations

import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path

from .routing import TIER_ORDER


@dataclass(frozen=True)
class StickyResult:
    tier: str
    action: str


class SessionStore:
    def __init__(self, path: Path):
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=5)
        conn.row_factory = sqlite3.Row
        return conn

    def _init(self) -> None:
        with self._connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    session_hash TEXT PRIMARY KEY,
                    tier TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    lower_turns INTEGER NOT NULL DEFAULT 0,
                    policy_version TEXT NOT NULL
                )
                """
            )

    def choose(
        self,
        session_hash: str,
        proposed_tier: str,
        *,
        policy_version: str,
        ttl_seconds: int,
        max_age_seconds: int,
        demotion_turns: int,
        now: int | None = None,
    ) -> StickyResult:
        now = int(now or time.time())
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM sessions WHERE session_hash=?", (session_hash,)).fetchone()
            if row is None or row["policy_version"] != policy_version or now - row["updated_at"] > ttl_seconds or now - row["created_at"] > max_age_seconds:
                conn.execute(
                    "INSERT OR REPLACE INTO sessions(session_hash,tier,created_at,updated_at,lower_turns,policy_version) VALUES(?,?,?,?,?,?)",
                    (session_hash, proposed_tier, now, now, 0, policy_version),
                )
                return StickyResult(proposed_tier, "new_or_expired")

            current = row["tier"]
            if TIER_ORDER[proposed_tier] > TIER_ORDER[current]:
                conn.execute("UPDATE sessions SET tier=?,updated_at=?,lower_turns=0 WHERE session_hash=?", (proposed_tier, now, session_hash))
                return StickyResult(proposed_tier, "promoted")
            if TIER_ORDER[proposed_tier] == TIER_ORDER[current]:
                conn.execute("UPDATE sessions SET updated_at=?,lower_turns=0 WHERE session_hash=?", (now, session_hash))
                return StickyResult(current, "kept")

            lower_turns = int(row["lower_turns"]) + 1
            if lower_turns >= max(1, demotion_turns):
                conn.execute("UPDATE sessions SET tier=?,updated_at=?,lower_turns=0 WHERE session_hash=?", (proposed_tier, now, session_hash))
                return StickyResult(proposed_tier, "demoted")
            conn.execute("UPDATE sessions SET updated_at=?,lower_turns=? WHERE session_hash=?", (now, lower_turns, session_hash))
            return StickyResult(current, f"sticky_hold:{lower_turns}/{max(1, demotion_turns)}")
