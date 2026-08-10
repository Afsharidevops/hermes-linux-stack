from __future__ import annotations

import json
import os
import secrets
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Iterator

from sqlalchemy import Boolean, Float, Integer, String, Text, create_engine, select, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "v51_users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(Text)
    role: Mapped[str] = mapped_column(String(40), default="user", index=True)
    team: Mapped[str] = mapped_column(String(120), default="default", index=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class ApiKey(Base):
    __tablename__ = "v51_api_keys"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120))
    key_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    prefix: Mapped[str] = mapped_column(String(24), index=True)
    user_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    role: Mapped[str] = mapped_column(String(40), default="user")
    team: Mapped[str] = mapped_column(String(120), default="default")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    expires_at: Mapped[str | None] = mapped_column(String(40), nullable=True)
    rpm: Mapped[int] = mapped_column(Integer, default=60)
    tpm: Mapped[int] = mapped_column(Integer, default=200000)
    daily_requests: Mapped[int] = mapped_column(Integer, default=5000)
    monthly_budget_usd: Mapped[float] = mapped_column(Float, default=0.0)
    allowed_tiers_json: Mapped[str] = mapped_column(Text, default='["fast","standard","strong"]')
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class RouteProfile(Base):
    __tablename__ = "v51_route_profiles"
    name: Mapped[str] = mapped_column(String(40), primary_key=True)
    model: Mapped[str] = mapped_column(String(240))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    min_tier: Mapped[str] = mapped_column(String(20), default="fast")
    max_output: Mapped[int] = mapped_column(Integer, default=4096)
    description: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class Budget(Base):
    __tablename__ = "v51_budgets"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    scope_type: Mapped[str] = mapped_column(String(30), index=True)
    scope_value: Mapped[str] = mapped_column(String(160), index=True)
    monthly_usd: Mapped[float] = mapped_column(Float, default=0.0)
    warning_percent: Mapped[float] = mapped_column(Float, default=80.0)
    hard_stop_percent: Mapped[float] = mapped_column(Float, default=100.0)
    action: Mapped[str] = mapped_column(String(40), default="downgrade")
    updated_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class AuditEvent(Base):
    __tablename__ = "v51_audit_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ts: Mapped[str] = mapped_column(String(40), default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(160), default="anonymous", index=True)
    role: Mapped[str] = mapped_column(String(40), default="anonymous")
    action: Mapped[str] = mapped_column(String(120), index=True)
    resource: Mapped[str] = mapped_column(String(240), default="")
    status: Mapped[str] = mapped_column(String(40), default="ok")
    detail_json: Mapped[str] = mapped_column(Text, default="{}")


class RouteEvent(Base):
    __tablename__ = "v51_route_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ts: Mapped[str] = mapped_column(String(40), default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(160), default="anonymous", index=True)
    team: Mapped[str] = mapped_column(String(120), default="default", index=True)
    tier: Mapped[str] = mapped_column(String(30), index=True)
    profile: Mapped[str] = mapped_column(String(30), index=True)
    model: Mapped[str] = mapped_column(String(240), index=True)
    policy: Mapped[str] = mapped_column(String(80), default="heuristic")
    status_code: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[float] = mapped_column(Float, default=0.0)
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cost_usd: Mapped[float] = mapped_column(Float, default=0.0)
    reason_json: Mapped[str] = mapped_column(Text, default="[]")
    request_id: Mapped[str] = mapped_column(String(80), default="", index=True)


class Policy(Base):
    __tablename__ = "v51_policies"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    priority: Mapped[int] = mapped_column(Integer, default=100, index=True)
    rule_json: Mapped[str] = mapped_column(Text, default="{}")
    action_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class KnowledgeBase(Base):
    __tablename__ = "v51_knowledge_bases"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(160), unique=True)
    description: Mapped[str] = mapped_column(Text, default="")
    owner: Mapped[str] = mapped_column(String(160), default="admin")
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class KnowledgeChunk(Base):
    __tablename__ = "v51_knowledge_chunks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    kb_id: Mapped[int] = mapped_column(Integer, index=True)
    source: Mapped[str] = mapped_column(String(500), default="manual")
    title: Mapped[str] = mapped_column(String(300), default="")
    content: Mapped[str] = mapped_column(Text)
    metadata_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class Memory(Base):
    __tablename__ = "v51_memories"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    scope_type: Mapped[str] = mapped_column(String(30), index=True)
    scope_value: Mapped[str] = mapped_column(String(160), index=True)
    key: Mapped[str] = mapped_column(String(180), index=True)
    value: Mapped[str] = mapped_column(Text)
    metadata_json: Mapped[str] = mapped_column(Text, default="{}")
    expires_at: Mapped[str | None] = mapped_column(String(40), nullable=True)
    updated_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class Agent(Base):
    __tablename__ = "v51_agents"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(160), unique=True)
    description: Mapped[str] = mapped_column(Text, default="")
    system_prompt: Mapped[str] = mapped_column(Text, default="")
    tier: Mapped[str] = mapped_column(String(30), default="auto")
    profile: Mapped[str] = mapped_column(String(30), default="auto")
    knowledge_json: Mapped[str] = mapped_column(Text, default="[]")
    plugins_json: Mapped[str] = mapped_column(Text, default="[]")
    permissions_json: Mapped[str] = mapped_column(Text, default="[]")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class Team(Base):
    __tablename__ = "v51_agent_teams"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(160), unique=True)
    strategy: Mapped[str] = mapped_column(String(30), default="sequential")
    agent_ids_json: Mapped[str] = mapped_column(Text, default="[]")
    synthesis_tier: Mapped[str] = mapped_column(String(30), default="strong")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class Plugin(Base):
    __tablename__ = "v51_plugins"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(160), unique=True)
    kind: Mapped[str] = mapped_column(String(40), default="mcp")
    description: Mapped[str] = mapped_column(Text, default="")
    endpoint: Mapped[str] = mapped_column(Text, default="")
    manifest_json: Mapped[str] = mapped_column(Text, default="{}")
    risk: Mapped[str] = mapped_column(String(30), default="medium")
    enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[str] = mapped_column(String(40), default=utcnow)


class RateCounter(Base):
    __tablename__ = "v51_rate_counters"
    key: Mapped[str] = mapped_column(String(240), primary_key=True)
    window_start: Mapped[int] = mapped_column(Integer, default=0)
    requests: Mapped[int] = mapped_column(Integer, default=0)
    tokens: Mapped[int] = mapped_column(Integer, default=0)


class ControlDB:
    def __init__(self, url: str):
        connect_args = {"check_same_thread": False} if url.startswith("sqlite") else {}
        self.engine = create_engine(url, future=True, pool_pre_ping=True, connect_args=connect_args)
        Base.metadata.create_all(self.engine)
        if url.startswith("sqlite"):
            with self.engine.begin() as conn:
                conn.execute(text("PRAGMA journal_mode=WAL"))
                conn.execute(text("PRAGMA busy_timeout=5000"))

    @contextmanager
    def session(self) -> Iterator[Session]:
        with Session(self.engine) as session:
            yield session

    def ping(self) -> bool:
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            return True
        except Exception:
            return False

    def bootstrap_profiles(self, defaults: dict[str, str]) -> None:
        with self.session() as session:
            changed = False
            for name, model in defaults.items():
                if session.get(RouteProfile, name) is None:
                    session.add(RouteProfile(name=name, model=model, min_tier=_profile_min_tier(name)))
                    changed = True
            if changed:
                session.commit()

    def audit(self, actor: str, role: str, action: str, resource: str = "", status: str = "ok", detail: dict[str, Any] | None = None) -> None:
        with self.session() as session:
            session.add(AuditEvent(actor=actor, role=role, action=action, resource=resource, status=status, detail_json=json.dumps(detail or {}, separators=(",", ":"))))
            session.commit()

    def new_request_id(self) -> str:
        return "rq_" + secrets.token_hex(10)


def _profile_min_tier(name: str) -> str:
    if name in {"vision", "coding"}:
        return "strong"
    if name in {"standard"}:
        return "standard"
    if name in {"strong"}:
        return "strong"
    return "fast"
