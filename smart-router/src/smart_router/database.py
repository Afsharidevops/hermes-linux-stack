from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from .config import Settings
from .routing import TIER_RANK


@dataclass(frozen=True)
class StickyResult:
    tier: str
    hit: bool
    action: str


class RouteStore:
    def __init__(self, settings: Settings):
        self.settings = settings
        Path(settings.database_path).parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        os.umask(0o077)
        connection = sqlite3.connect(self.settings.database_path, timeout=5)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 5000")
        return connection

    @contextmanager
    def _connection(self):
        connection = self._connect()
        try:
            # sqlite3.Connection's context manager handles commit/rollback but does
            # not close the file descriptor. Wrap it so every operation closes.
            with connection:
                yield connection
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS session_routes (
                    session_hash TEXT NOT NULL,
                    auto_alias TEXT NOT NULL,
                    policy_version TEXT NOT NULL,
                    tier TEXT NOT NULL,
                    previous_tier TEXT,
                    promotion_reason TEXT,
                    simple_turn_count INTEGER NOT NULL DEFAULT 0,
                    failure_count INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    last_seen_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    PRIMARY KEY(session_hash, auto_alias, policy_version)
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS session_routes_expiry ON session_routes(expires_at)"
            )
        self.purge_expired()

    def purge_expired(self, now: int | None = None, limit: int = 500) -> int:
        now = now or int(time.time())
        with self._connection() as connection:
            cursor = connection.execute(
                """
                DELETE FROM session_routes WHERE rowid IN (
                    SELECT rowid FROM session_routes
                    WHERE expires_at <= ? OR created_at + ? <= ?
                    LIMIT ?
                )
                """,
                (now, self.settings.max_session_age_seconds, now, limit),
            )
            return cursor.rowcount or 0

    def ready(self) -> bool:
        try:
            with self._connection() as connection:
                connection.execute("BEGIN IMMEDIATE")
                connection.execute("SELECT 1")
                connection.rollback()
            return True
        except sqlite3.Error:
            return False

    def reset(self, session_hash: str, alias: str) -> None:
        with self._connection() as connection:
            connection.execute(
                "DELETE FROM session_routes WHERE session_hash = ? AND auto_alias = ?",
                (session_hash, alias),
            )

    def resolve(
        self,
        session_hash: str,
        alias: str,
        proposed_tier: str,
        promotion_reason: str,
        now: int | None = None,
    ) -> StickyResult:
        now = now or int(time.time())
        with self._lock, self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                """
                DELETE FROM session_routes WHERE rowid IN (
                    SELECT rowid FROM session_routes
                    WHERE expires_at <= ? OR created_at + ? <= ?
                    LIMIT 100
                )
                """,
                (now, self.settings.max_session_age_seconds, now),
            )
            row = connection.execute(
                """
                SELECT * FROM session_routes
                WHERE session_hash = ? AND auto_alias = ? AND policy_version = ?
                """,
                (session_hash, alias, self.settings.policy_version),
            ).fetchone()
            if row and (
                row["expires_at"] <= now
                or row["created_at"] + self.settings.max_session_age_seconds <= now
            ):
                connection.execute(
                    """
                    DELETE FROM session_routes
                    WHERE session_hash = ? AND auto_alias = ? AND policy_version = ?
                    """,
                    (session_hash, alias, self.settings.policy_version),
                )
                row = None
            if row is None:
                self._insert(connection, session_hash, alias, proposed_tier, now)
                connection.commit()
                return StickyResult(proposed_tier, False, "created")

            current = row["tier"]
            selected = current
            action = "sticky"
            simple_count = row["simple_turn_count"]
            previous = row["previous_tier"]
            reason = row["promotion_reason"]
            if TIER_RANK[proposed_tier] > TIER_RANK[current]:
                selected = proposed_tier
                previous = current
                reason = promotion_reason
                simple_count = 0
                action = "promoted"
            elif TIER_RANK[proposed_tier] < TIER_RANK[current]:
                simple_count += 1
                if simple_count >= self.settings.demotion_turns:
                    selected = proposed_tier
                    previous = current
                    reason = "consecutive_simple_turns"
                    simple_count = 0
                    action = "demoted"
            else:
                simple_count = 0

            connection.execute(
                """
                UPDATE session_routes
                SET tier = ?, previous_tier = ?, promotion_reason = ?,
                    simple_turn_count = ?, last_seen_at = ?, expires_at = ?
                WHERE session_hash = ? AND auto_alias = ? AND policy_version = ?
                """,
                (
                    selected,
                    previous,
                    reason,
                    simple_count,
                    now,
                    now + self.settings.session_ttl_seconds,
                    session_hash,
                    alias,
                    self.settings.policy_version,
                ),
            )
            connection.commit()
            return StickyResult(selected, True, action)

    def _insert(
        self,
        connection: sqlite3.Connection,
        session_hash: str,
        alias: str,
        tier: str,
        now: int,
    ) -> None:
        connection.execute(
            """
            INSERT INTO session_routes(
                session_hash, auto_alias, policy_version, tier,
                created_at, last_seen_at, expires_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_hash,
                alias,
                self.settings.policy_version,
                tier,
                now,
                now,
                now + self.settings.session_ttl_seconds,
            ),
        )
