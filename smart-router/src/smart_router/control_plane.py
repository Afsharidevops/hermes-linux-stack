from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import re
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from sqlalchemy import delete, func, select
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse, Response
from starlette.routing import Route

from .control_db import (
    Agent,
    ApiKey,
    AuditEvent,
    Budget,
    ControlDB,
    KnowledgeBase,
    KnowledgeChunk,
    Memory,
    Plugin,
    Policy,
    RateCounter,
    RouteEvent,
    RouteProfile,
    Team,
    User,
)
from .knowledge_v51 import KnowledgeManager
from .panel_v51 import PANEL_HTML
from .policy_v51 import PolicyEngine, TIER_ORDER
from .security_v51 import Identity, ROLE_PERMISSIONS, SecurityManager, bearer


@dataclass
class FinalRoute:
    tier: str
    profile: str
    model: str
    max_output_tokens: int | None = None
    error: JSONResponse | None = None


class ControlPlane:
    """Hermes Smart Router v0.5.1 control plane.

    This module is intentionally additive: the existing v0.5.0 routing policy remains the
    source of truth for capability safety. v0.5.1 adds governance, dynamic route profiles,
    RAG/memory, identities/quotas, agent orchestration, audit and a richer admin panel.
    """

    def __init__(self, settings: Any):
        self.settings = settings
        self.enabled = _env_bool("SMART_ROUTER_CONTROL_PLANE_ENABLED", True)
        self.require_auth = _env_bool("SMART_ROUTER_REQUIRE_AUTH", False)
        self.ha_mode = _env_bool("SMART_ROUTER_HA_MODE", False)
        configured_db_url = os.getenv("SMART_ROUTER_CONTROL_DATABASE_URL")
        if configured_db_url:
            self.db_url = configured_db_url
        else:
            router_db_path = getattr(settings, "database_path", "/data/router.sqlite3")
            control_path = os.path.join(os.path.dirname(router_db_path) or ".", "control-v0.5.1.sqlite3")
            self.db_url = f"sqlite:///{control_path}"
        self.db = ControlDB(self.db_url)
        self.security = SecurityManager(
            self.db,
            settings.hmac_secret,
            os.getenv("SMART_ROUTER_ADMIN_API_KEY") or None,
            int(os.getenv("SMART_ROUTER_SESSION_TTL_SECONDS_V51", "28800")),
        )
        self.knowledge = KnowledgeManager(self.db)
        self.policy = PolicyEngine(self.db)
        self.internal_token = hmac.new(settings.hmac_secret.encode(), b"hermes-v0.5.1-internal", hashlib.sha256).hexdigest()
        self.pricing = self._load_pricing(os.getenv("SMART_ROUTER_PRICING_FILE", "/policy/pricing-v0.5.json"))
        self.default_profiles = {
            "fast": settings.fast.model,
            "standard": settings.standard.model,
            "strong": settings.strong.model,
            "coding": os.getenv("SMART_ROUTER_CODING_MODEL", settings.strong.model),
            "vision": os.getenv("SMART_ROUTER_VISION_MODEL", settings.strong.model),
        }
        self.db.bootstrap_profiles(self.default_profiles)
        self.security.bootstrap_admin(
            os.getenv("SMART_ROUTER_BOOTSTRAP_ADMIN_USER", "admin"),
            os.getenv("SMART_ROUTER_BOOTSTRAP_ADMIN_PASSWORD") or None,
        )
        self.app = Starlette(routes=self._routes())
        self.app.state.control = self

    # -------------------- hooks used by existing Smart Router --------------------

    def authenticate_api_request(self, request: Request) -> Identity | None:
        internal = request.headers.get("x-hermes-internal", "")
        token = bearer(request.headers)
        if (internal and hmac.compare_digest(internal, self.internal_token)) or (token and hmac.compare_digest(token, self.internal_token)):
            identity = Identity(actor="hermes-internal", role="super_admin", team="system")
            request.state.v51_identity = identity
            return identity
        legacy = getattr(self.settings, "client_api_key", "")
        if token and legacy and hmac.compare_digest(token, legacy):
            identity = Identity(actor="legacy-client", role="operator", team="default")
            request.state.v51_identity = identity
            return identity
        identity = self.security.api_key_identity(token)
        if identity:
            request.state.v51_identity = identity
        return identity

    def begin_request(self, request: Request, body: dict[str, Any]) -> JSONResponse | None:
        if not self.enabled:
            return None
        identity: Identity | None = getattr(request.state, "v51_identity", None) or self.authenticate_api_request(request)
        if identity is None:
            if self.require_auth:
                return _error("authentication required", "auth_required", 401)
            identity = Identity(actor="anonymous", role="user", team="default", rpm=int(os.getenv("SMART_ROUTER_ANON_RPM", "30")))
            request.state.v51_identity = identity
        if not identity.can("routing.use"):
            self.db.audit(identity.actor, identity.role, "routing.request", status="denied", detail={"reason": "permission"})
            return _error("role cannot use routing", "permission_denied", 403)
        estimated = _estimate_tokens(body)
        limited = self._rate_limit(identity, estimated)
        if limited:
            self.db.audit(identity.actor, identity.role, "routing.rate_limit", status="denied", detail=limited)
            return _error(limited["message"], "rate_limit_exceeded", 429)
        self._inject_context(body, identity)
        request.state.v51_started = time.monotonic()
        request.state.v51_request_id = self.db.new_request_id()
        return None

    def finalize_routing(self, request: Request, body: dict[str, Any], selected_tier: str, default_model: str, budget: Any) -> FinalRoute:
        identity: Identity = getattr(request.state, "v51_identity", Identity("anonymous", "user"))
        profile = self._detect_profile(request, body, selected_tier)
        policy = self.policy.evaluate(body, identity, selected_tier, profile)
        if not policy.allowed:
            self.db.audit(identity.actor, identity.role, "policy.deny", "chat/completions", "denied", {"reason": policy.deny_reason, "matched": policy.matched})
            return FinalRoute(selected_tier, profile, default_model, error=_error(policy.deny_reason, "policy_denied", 403))
        if policy.force_min_tier and TIER_ORDER[policy.force_min_tier] > TIER_ORDER.get(selected_tier, 0):
            selected_tier = policy.force_min_tier
            # Upgrades remain safe because v0.5.0 already requires tier capabilities to be monotonic.
            default_model = getattr(self.settings, selected_tier).model
            if profile not in {"vision", "coding"}:
                profile = selected_tier
        if selected_tier not in identity.allowed_tiers and identity.api_key_id is not None:
            return FinalRoute(selected_tier, profile, default_model, error=_error("API key is not allowed to use this tier", "tier_not_allowed", 403))
        budget_error = self._budget_guard(identity)
        if budget_error:
            return FinalRoute(selected_tier, profile, default_model, error=budget_error)
        model = default_model if self.settings.mode == "observe" else (self.profile_model(profile) or default_model)
        if self.settings.mode == "observe":
            profile = "observe"
        max_output = policy.max_output_tokens
        if max_output:
            _cap_output(body, max_output)
        request.state.v51_route = {"tier": selected_tier, "profile": profile, "model": model, "policy_matches": policy.matched or []}
        return FinalRoute(selected_tier, profile, model, max_output_tokens=max_output)

    def record_route(self, request: Request, response: Response, policy_name: str = "heuristic", reasons: list[str] | tuple[str, ...] | None = None) -> None:
        if not self.enabled:
            return
        route = getattr(request.state, "v51_route", None)
        if not route:
            return
        identity: Identity = getattr(request.state, "v51_identity", Identity("anonymous", "user"))
        started = getattr(request.state, "v51_started", time.monotonic())
        usage = _usage_from_response(response)
        cost = self._cost(route["model"], route["tier"], usage[0], usage[1])
        row = RouteEvent(
            actor=identity.actor,
            team=identity.team,
            tier=route["tier"],
            profile=route["profile"],
            model=route["model"],
            policy=policy_name,
            status_code=response.status_code,
            latency_ms=(time.monotonic() - started) * 1000,
            input_tokens=usage[0],
            output_tokens=usage[1],
            cost_usd=cost,
            reason_json=json.dumps(list(reasons or []) + list(route.get("policy_matches") or []), separators=(",", ":")),
            request_id=getattr(request.state, "v51_request_id", ""),
        )
        try:
            with self.db.session() as session:
                session.add(row)
                session.commit()
        except Exception:
            # Observability must never break inference.
            pass

    def profile_model(self, profile: str) -> str | None:
        with self.db.session() as session:
            row = session.get(RouteProfile, profile)
            return row.model if row and row.enabled and row.model else None

    # -------------------- panel/admin application --------------------

    def _routes(self) -> list[Route]:
        return [
            Route("/", self.panel, methods=["GET"]),
            Route("/api/login", self.login, methods=["POST"]),
            Route("/api/me", self.me, methods=["GET"]),
            Route("/api/summary", self.summary, methods=["GET"]),
            Route("/api/routes", self.routes_api, methods=["GET", "PUT"]),
            Route("/api/providers/discover", self.provider_discover, methods=["GET"]),
            Route("/api/users", self.users_api, methods=["GET", "POST"]),
            Route("/api/users/{user_id:int}", self.user_api, methods=["PUT", "DELETE"]),
            Route("/api/keys", self.keys_api, methods=["GET", "POST"]),
            Route("/api/keys/{key_id:int}", self.key_api, methods=["DELETE"]),
            Route("/api/budgets", self.budgets_api, methods=["GET", "POST"]),
            Route("/api/budgets/{budget_id:int}", self.budget_api, methods=["DELETE"]),
            Route("/api/policies", self.policies_api, methods=["GET", "POST"]),
            Route("/api/policies/{policy_id:int}", self.policy_api, methods=["PUT", "DELETE"]),
            Route("/api/knowledge", self.knowledge_api, methods=["GET", "POST"]),
            Route("/api/knowledge/{kb_id:int}", self.knowledge_item_api, methods=["DELETE"]),
            Route("/api/knowledge/{kb_id:int}/documents", self.knowledge_documents_api, methods=["POST"]),
            Route("/api/knowledge/search", self.knowledge_search_api, methods=["POST"]),
            Route("/api/memory", self.memory_api, methods=["GET", "POST"]),
            Route("/api/memory/{memory_id:int}", self.memory_item_api, methods=["DELETE"]),
            Route("/api/agents", self.agents_api, methods=["GET", "POST"]),
            Route("/api/agents/{agent_id:int}", self.agent_api, methods=["PUT", "DELETE"]),
            Route("/api/agents/{agent_id:int}/run", self.agent_run_api, methods=["POST"]),
            Route("/api/teams", self.teams_api, methods=["GET", "POST"]),
            Route("/api/teams/{team_id:int}", self.team_api, methods=["PUT", "DELETE"]),
            Route("/api/teams/{team_id:int}/run", self.team_run_api, methods=["POST"]),
            Route("/api/plugins", self.plugins_api, methods=["GET", "POST"]),
            Route("/api/plugins/{plugin_id:int}", self.plugin_api, methods=["PUT", "DELETE"]),
            Route("/api/audit", self.audit_api, methods=["GET"]),
            Route("/api/system", self.system_api, methods=["GET"]),
        ]

    async def panel(self, _: Request) -> Response:
        if not self.enabled:
            return Response(status_code=404)
        return HTMLResponse(PANEL_HTML.replace("__VERSION__", "0.5.1"))

    async def login(self, request: Request) -> Response:
        data = await _json(request)
        username = str(data.get("username", ""))
        password = str(data.get("password", ""))
        token = self.security.login(username, password)
        if not token:
            return _error("invalid credentials", "invalid_credentials", 401)
        return JSONResponse({"token": token})

    async def me(self, request: Request) -> Response:
        identity = self._admin_identity(request, "panel.read")
        if isinstance(identity, Response):
            return identity
        return JSONResponse({"actor": identity.actor, "role": identity.role, "team": identity.team, "permissions": sorted(ROLE_PERMISSIONS.get(identity.role, set()))})

    async def summary(self, request: Request) -> Response:
        identity = self._admin_identity(request, "panel.read")
        if isinstance(identity, Response):
            return identity
        try:
            hours = max(1.0, min(24 * 90, float(request.query_params.get("hours", "24"))))
        except ValueError:
            hours = 24
        since = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
        with self.db.session() as session:
            total = session.scalar(select(func.count(RouteEvent.id)).where(RouteEvent.ts >= since)) or 0
            cost = session.scalar(select(func.coalesce(func.sum(RouteEvent.cost_usd), 0.0)).where(RouteEvent.ts >= since)) or 0.0
            avg_latency = session.scalar(select(func.coalesce(func.avg(RouteEvent.latency_ms), 0.0)).where(RouteEvent.ts >= since)) or 0.0
            tiers = session.execute(select(RouteEvent.tier, func.count(RouteEvent.id)).where(RouteEvent.ts >= since).group_by(RouteEvent.tier)).all()
            profiles = session.execute(select(RouteEvent.profile, func.count(RouteEvent.id)).where(RouteEvent.ts >= since).group_by(RouteEvent.profile)).all()
            models = session.execute(select(RouteEvent.model, func.count(RouteEvent.id), func.coalesce(func.sum(RouteEvent.cost_usd), 0.0)).where(RouteEvent.ts >= since).group_by(RouteEvent.model).order_by(func.count(RouteEvent.id).desc()).limit(12)).all()
            errors = session.scalar(select(func.count(RouteEvent.id)).where(RouteEvent.ts >= since, RouteEvent.status_code >= 400)) or 0
            users = session.scalar(select(func.count(User.id)).where(User.active.is_(True))) or 0
            keys = session.scalar(select(func.count(ApiKey.id)).where(ApiKey.active.is_(True))) or 0
            kbs = session.scalar(select(func.count(KnowledgeBase.id))) or 0
            agents = session.scalar(select(func.count(Agent.id)).where(Agent.active.is_(True))) or 0
            audit_denied = session.scalar(select(func.count(AuditEvent.id)).where(AuditEvent.ts >= since, AuditEvent.status == "denied")) or 0
            recent = list(session.scalars(select(RouteEvent).where(RouteEvent.ts >= since).order_by(RouteEvent.id.desc()).limit(30)))
        payload = {
            "window_hours": hours,
            "requests": total,
            "cost_usd": round(float(cost), 6),
            "avg_latency_ms": round(float(avg_latency), 2),
            "error_rate": round((errors / total * 100) if total else 0, 2),
            "tiers": dict(tiers),
            "profiles": dict(profiles),
            "models": [{"model": m, "requests": c, "cost_usd": round(float(v), 6)} for m, c, v in models],
            "users": users,
            "api_keys": keys,
            "knowledge_bases": kbs,
            "agents": agents,
            "policy_denials": audit_denied,
            "recent": [_row_dict(r, exclude={"reason_json"}) | {"reasons": _loads(r.reason_json, [])} for r in recent],
        }
        return JSONResponse(payload)

    async def routes_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "routing.manage" if request.method == "PUT" else "panel.read")
        if isinstance(identity, Response):
            return identity
        if request.method == "PUT":
            data = await _json(request)
            name = str(data.get("name", ""))
            model = str(data.get("model", "")).strip()
            if name not in {"fast", "standard", "strong", "coding", "vision"} or not model:
                return _error("invalid route profile", "invalid_route", 422)
            with self.db.session() as session:
                row = session.get(RouteProfile, name)
                if row is None:
                    row = RouteProfile(name=name, model=model)
                    session.add(row)
                row.model = model
                row.enabled = bool(data.get("enabled", True))
                row.max_output = max(1, int(data.get("max_output", row.max_output or 4096)))
                row.description = str(data.get("description", row.description or ""))
                row.updated_at = datetime.now(timezone.utc).isoformat()
                session.commit()
            self.db.audit(identity.actor, identity.role, "route.update", name, detail={"model": model})
        with self.db.session() as session:
            rows = list(session.scalars(select(RouteProfile).order_by(RouteProfile.name)))
        return JSONResponse([_row_dict(r) for r in rows])

    async def provider_discover(self, request: Request) -> Response:
        identity = self._admin_identity(request, "panel.read")
        if isinstance(identity, Response):
            return identity
        headers = {}
        if getattr(self.settings, "upstream_api_key", None):
            headers["authorization"] = f"Bearer {self.settings.upstream_api_key}"
        started = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=12) as client:
                models_r, health_r = await asyncio.gather(
                    client.get(self.settings.upstream_base_url.rstrip("/") + "/models", headers=headers),
                    client.get(self.settings.upstream_health_url, headers=headers),
                    return_exceptions=True,
                )
            models: list[str] = []
            if isinstance(models_r, httpx.Response) and models_r.is_success:
                data = models_r.json()
                models = [str(x.get("id")) for x in data.get("data", []) if isinstance(x, dict) and x.get("id")]
            health_ok = isinstance(health_r, httpx.Response) and health_r.is_success
            return JSONResponse({"models": models, "health": health_ok, "latency_ms": round((time.monotonic() - started) * 1000, 2), "upstream": self.settings.upstream_base_url})
        except Exception as exc:
            return JSONResponse({"models": [], "health": False, "error": type(exc).__name__}, status_code=503)

    async def users_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "users.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            role = str(d.get("role", "user"))
            if role not in ROLE_PERMISSIONS: return _error("invalid role", "invalid_role", 422)
            try:
                password_hash = self.security.hash_password(str(d.get("password", "")))
            except ValueError as exc:
                return _error(str(exc), "invalid_password", 422)
            with self.db.session() as s:
                row = User(username=str(d.get("username", "")).strip(), password_hash=password_hash, role=role, team=str(d.get("team", "default")))
                if not row.username: return _error("username required", "invalid_user", 422)
                s.add(row)
                try: s.commit()
                except Exception: s.rollback(); return _error("username already exists", "duplicate_user", 409)
            self.db.audit(identity.actor, identity.role, "user.create", row.username)
        with self.db.session() as s:
            rows = list(s.scalars(select(User).order_by(User.id)))
        return JSONResponse([_row_dict(r, exclude={"password_hash"}) for r in rows])

    async def user_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "users.manage")
        if isinstance(identity, Response): return identity
        uid = int(request.path_params["user_id"])
        with self.db.session() as s:
            row = s.get(User, uid)
            if not row: return Response(status_code=404)
            if request.method == "DELETE":
                row.active = False
            else:
                d = await _json(request)
                if d.get("role") in ROLE_PERMISSIONS: row.role = d["role"]
                if "team" in d: row.team = str(d["team"])
                if "active" in d: row.active = bool(d["active"])
                if d.get("password"):
                    try: row.password_hash = self.security.hash_password(str(d["password"]))
                    except ValueError as exc: return _error(str(exc), "invalid_password", 422)
            s.commit()
        self.db.audit(identity.actor, identity.role, "user.update", str(uid))
        return JSONResponse({"ok": True})

    async def keys_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "keys.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        revealed = None
        if request.method == "POST":
            d = await _json(request)
            try:
                row, revealed = self.security.create_api_key(
                    name=str(d.get("name", "key")), role=str(d.get("role", "user")), team=str(d.get("team", "default")),
                    user_id=int(d["user_id"]) if d.get("user_id") else None, rpm=int(d.get("rpm", 60)), tpm=int(d.get("tpm", 200000)),
                    daily_requests=int(d.get("daily_requests", 5000)), monthly_budget_usd=float(d.get("monthly_budget_usd", 0)),
                    allowed_tiers=d.get("allowed_tiers") or ["fast", "standard", "strong"], expires_at=d.get("expires_at") or None,
                )
            except (ValueError, TypeError) as exc:
                return _error(str(exc), "invalid_key", 422)
            self.db.audit(identity.actor, identity.role, "key.create", row.name)
        with self.db.session() as s:
            rows = list(s.scalars(select(ApiKey).order_by(ApiKey.id.desc())))
        payload: Any = [_row_dict(r, exclude={"key_hash"}) | {"allowed_tiers": _loads(r.allowed_tiers_json, [])} for r in rows]
        if revealed:
            return JSONResponse({"created_key": revealed, "keys": payload})
        return JSONResponse(payload)

    async def key_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "keys.manage")
        if isinstance(identity, Response): return identity
        kid = int(request.path_params["key_id"])
        with self.db.session() as s:
            row = s.get(ApiKey, kid)
            if not row: return Response(status_code=404)
            row.active = False
            s.commit()
        self.db.audit(identity.actor, identity.role, "key.revoke", str(kid))
        return JSONResponse({"ok": True})

    async def budgets_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "budgets.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            scope_type = str(d.get("scope_type", "global")); scope_value = str(d.get("scope_value", "*"))
            if scope_type not in {"global", "user", "team", "agent", "model", "api_key"}: return _error("invalid budget scope", "invalid_budget", 422)
            with self.db.session() as s:
                row = Budget(scope_type=scope_type, scope_value=scope_value, monthly_usd=max(0.0, float(d.get("monthly_usd", 0))), warning_percent=float(d.get("warning_percent", 80)), hard_stop_percent=float(d.get("hard_stop_percent", 100)), action=str(d.get("action", "hard_stop")))
                s.add(row); s.commit()
            self.db.audit(identity.actor, identity.role, "budget.create", f"{scope_type}:{scope_value}")
        with self.db.session() as s: rows = list(s.scalars(select(Budget).order_by(Budget.id)))
        return JSONResponse([_row_dict(r) for r in rows])

    async def budget_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "budgets.manage")
        if isinstance(identity, Response): return identity
        bid = int(request.path_params["budget_id"])
        with self.db.session() as s:
            row = s.get(Budget, bid)
            if not row: return Response(status_code=404)
            s.delete(row); s.commit()
        return JSONResponse({"ok": True})

    async def policies_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "policies.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            with self.db.session() as s:
                row = Policy(name=str(d.get("name", "policy")).strip(), enabled=bool(d.get("enabled", True)), priority=int(d.get("priority", 100)), rule_json=json.dumps(d.get("rule") or {}), action_json=json.dumps(d.get("action") or {}))
                s.add(row)
                try: s.commit()
                except Exception: s.rollback(); return _error("policy name already exists", "duplicate_policy", 409)
            self.db.audit(identity.actor, identity.role, "policy.create", row.name)
        with self.db.session() as s: rows = list(s.scalars(select(Policy).order_by(Policy.priority, Policy.id)))
        return JSONResponse([_row_dict(r, exclude={"rule_json", "action_json"}) | {"rule": _loads(r.rule_json, {}), "action": _loads(r.action_json, {})} for r in rows])

    async def policy_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "policies.manage")
        if isinstance(identity, Response): return identity
        pid = int(request.path_params["policy_id"])
        with self.db.session() as s:
            row = s.get(Policy, pid)
            if not row: return Response(status_code=404)
            if request.method == "DELETE": s.delete(row)
            else:
                d = await _json(request)
                if "enabled" in d: row.enabled = bool(d["enabled"])
                if "priority" in d: row.priority = int(d["priority"])
                if "rule" in d: row.rule_json = json.dumps(d["rule"])
                if "action" in d: row.action_json = json.dumps(d["action"])
            s.commit()
        return JSONResponse({"ok": True})

    async def knowledge_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "knowledge.manage" if request.method == "POST" else "knowledge.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            try: row = self.knowledge.create_base(str(d.get("name", "")).strip(), str(d.get("description", "")), identity.actor)
            except Exception: return _error("knowledge base name is required and must be unique", "invalid_knowledge_base", 422)
            self.db.audit(identity.actor, identity.role, "knowledge.create", row.name)
        with self.db.session() as s:
            rows = list(s.scalars(select(KnowledgeBase).order_by(KnowledgeBase.id)))
            counts = dict(s.execute(select(KnowledgeChunk.kb_id, func.count(KnowledgeChunk.id)).group_by(KnowledgeChunk.kb_id)).all())
        return JSONResponse([_row_dict(r) | {"chunks": counts.get(r.id, 0)} for r in rows])

    async def knowledge_item_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "knowledge.manage")
        if isinstance(identity, Response): return identity
        self.knowledge.delete_base(int(request.path_params["kb_id"]))
        return JSONResponse({"ok": True})

    async def knowledge_documents_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "knowledge.manage")
        if isinstance(identity, Response): return identity
        d = await _json(request)
        content = str(d.get("content", ""))
        if not content: return _error("content required", "invalid_document", 422)
        count = self.knowledge.add_document(int(request.path_params["kb_id"]), str(d.get("source", "manual")), str(d.get("title", "")), content, d.get("metadata") or {})
        self.db.audit(identity.actor, identity.role, "knowledge.ingest", str(request.path_params["kb_id"]), detail={"chunks": count})
        return JSONResponse({"chunks": count})

    async def knowledge_search_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "knowledge.read")
        if isinstance(identity, Response): return identity
        d = await _json(request)
        return JSONResponse(self.knowledge.search([int(x) for x in d.get("kb_ids", [])], str(d.get("query", "")), int(d.get("limit", 5))))

    async def memory_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            try: self.knowledge.set_memory(str(d.get("scope_type", "user")), str(d.get("scope_value", identity.actor)), str(d.get("key", "")), str(d.get("value", "")), d.get("metadata") or {}, d.get("expires_at") or None)
            except ValueError as exc: return _error(str(exc), "invalid_memory", 422)
        with self.db.session() as s: rows = list(s.scalars(select(Memory).order_by(Memory.id.desc()).limit(500)))
        return JSONResponse([_row_dict(r, exclude={"metadata_json"}) | {"metadata": _loads(r.metadata_json, {})} for r in rows])

    async def memory_item_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.manage")
        if isinstance(identity, Response): return identity
        with self.db.session() as s:
            row = s.get(Memory, int(request.path_params["memory_id"]))
            if row: s.delete(row); s.commit()
        return JSONResponse({"ok": True})

    async def agents_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            with self.db.session() as s:
                row = Agent(name=str(d.get("name", "agent")).strip(), description=str(d.get("description", "")), system_prompt=str(d.get("system_prompt", "")), tier=str(d.get("tier", "auto")), profile=str(d.get("profile", "auto")), knowledge_json=json.dumps(d.get("knowledge") or []), plugins_json=json.dumps(d.get("plugins") or []), permissions_json=json.dumps(d.get("permissions") or []), active=bool(d.get("active", True)))
                s.add(row)
                try: s.commit()
                except Exception: s.rollback(); return _error("agent name already exists", "duplicate_agent", 409)
            self.db.audit(identity.actor, identity.role, "agent.create", row.name)
        return await self._agents_list()

    async def _agents_list(self) -> Response:
        with self.db.session() as s: rows = list(s.scalars(select(Agent).order_by(Agent.id)))
        return JSONResponse([_agent_dict(r) for r in rows])

    async def agent_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.manage")
        if isinstance(identity, Response): return identity
        aid = int(request.path_params["agent_id"])
        with self.db.session() as s:
            row = s.get(Agent, aid)
            if not row: return Response(status_code=404)
            if request.method == "DELETE": row.active = False
            else:
                d = await _json(request)
                for key in ("name", "description", "system_prompt", "tier", "profile"):
                    if key in d: setattr(row, key, str(d[key]))
                if "knowledge" in d: row.knowledge_json = json.dumps(d["knowledge"])
                if "plugins" in d: row.plugins_json = json.dumps(d["plugins"])
                if "permissions" in d: row.permissions_json = json.dumps(d["permissions"])
                if "active" in d: row.active = bool(d["active"])
            s.commit()
        return JSONResponse({"ok": True})

    async def agent_run_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.run")
        if isinstance(identity, Response): return identity
        d = await _json(request)
        result = await self._run_agent(int(request.path_params["agent_id"]), str(d.get("task", "")), d.get("messages"))
        if isinstance(result, Response): return result
        self.db.audit(identity.actor, identity.role, "agent.run", str(request.path_params["agent_id"]))
        return JSONResponse(result)

    async def teams_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            with self.db.session() as s:
                row = Team(name=str(d.get("name", "team")).strip(), strategy=str(d.get("strategy", "sequential")), agent_ids_json=json.dumps(d.get("agent_ids") or []), synthesis_tier=str(d.get("synthesis_tier", "strong")), active=bool(d.get("active", True)))
                s.add(row)
                try: s.commit()
                except Exception: s.rollback(); return _error("team name already exists", "duplicate_team", 409)
        with self.db.session() as s: rows = list(s.scalars(select(Team).order_by(Team.id)))
        return JSONResponse([_team_dict(r) for r in rows])

    async def team_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.manage")
        if isinstance(identity, Response): return identity
        tid = int(request.path_params["team_id"])
        with self.db.session() as s:
            row = s.get(Team, tid)
            if not row: return Response(status_code=404)
            if request.method == "DELETE": row.active = False
            else:
                d = await _json(request)
                if "name" in d: row.name = str(d["name"])
                if "strategy" in d: row.strategy = str(d["strategy"])
                if "agent_ids" in d: row.agent_ids_json = json.dumps(d["agent_ids"])
                if "synthesis_tier" in d: row.synthesis_tier = str(d["synthesis_tier"])
                if "active" in d: row.active = bool(d["active"])
            s.commit()
        return JSONResponse({"ok": True})

    async def team_run_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "agents.run")
        if isinstance(identity, Response): return identity
        d = await _json(request); task = str(d.get("task", ""))
        with self.db.session() as s: team = s.get(Team, int(request.path_params["team_id"]))
        if not team or not team.active: return Response(status_code=404)
        agent_ids = [int(x) for x in _loads(team.agent_ids_json, [])]
        if not agent_ids: return _error("team has no agents", "empty_team", 422)
        if team.strategy == "parallel":
            outputs = await asyncio.gather(*(self._run_agent(aid, task, None) for aid in agent_ids))
        else:
            outputs = []
            context = task
            for aid in agent_ids:
                out = await self._run_agent(aid, context, None)
                outputs.append(out)
                if isinstance(out, dict): context = task + "\n\nPrevious agent result:\n" + _extract_text(out)
        clean = [o for o in outputs if isinstance(o, dict)]
        if len(clean) == 1: return JSONResponse({"team": team.name, "results": clean, "final": clean[0]})
        synthesis_prompt = "Synthesize the following specialist results into one accurate answer. Preserve disagreements and do not invent facts.\n\n" + "\n\n---\n\n".join(_extract_text(o) for o in clean)
        synthesis_profile = team.synthesis_tier if team.synthesis_tier in TIER_ORDER else "strong"
        final = await self._local_chat({"model": "auto", "messages": [{"role": "user", "content": synthesis_prompt}]}, profile=synthesis_profile)
        self.db.audit(identity.actor, identity.role, "team.run", team.name, detail={"strategy": team.strategy, "agents": agent_ids})
        return JSONResponse({"team": team.name, "results": clean, "final": final})

    async def plugins_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "plugins.manage" if request.method == "POST" else "panel.read")
        if isinstance(identity, Response): return identity
        if request.method == "POST":
            d = await _json(request)
            with self.db.session() as s:
                row = Plugin(name=str(d.get("name", "plugin")).strip(), kind=str(d.get("kind", "mcp")), description=str(d.get("description", "")), endpoint=str(d.get("endpoint", "")), manifest_json=json.dumps(d.get("manifest") or {}), risk=str(d.get("risk", "medium")), enabled=bool(d.get("enabled", False)))
                s.add(row)
                try: s.commit()
                except Exception: s.rollback(); return _error("plugin name already exists", "duplicate_plugin", 409)
            self.db.audit(identity.actor, identity.role, "plugin.create", row.name)
        with self.db.session() as s: rows = list(s.scalars(select(Plugin).order_by(Plugin.id)))
        return JSONResponse([_plugin_dict(r) for r in rows])

    async def plugin_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "plugins.manage")
        if isinstance(identity, Response): return identity
        pid = int(request.path_params["plugin_id"])
        with self.db.session() as s:
            row = s.get(Plugin, pid)
            if not row: return Response(status_code=404)
            if request.method == "DELETE": s.delete(row)
            else:
                d = await _json(request)
                for key in ("name", "kind", "description", "endpoint", "risk"):
                    if key in d: setattr(row, key, str(d[key]))
                if "manifest" in d: row.manifest_json = json.dumps(d["manifest"])
                if "enabled" in d: row.enabled = bool(d["enabled"])
            s.commit()
        return JSONResponse({"ok": True})

    async def audit_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "audit.read")
        if isinstance(identity, Response): return identity
        limit = max(1, min(1000, int(request.query_params.get("limit", "200"))))
        with self.db.session() as s: rows = list(s.scalars(select(AuditEvent).order_by(AuditEvent.id.desc()).limit(limit)))
        return JSONResponse([_row_dict(r, exclude={"detail_json"}) | {"detail": _loads(r.detail_json, {})} for r in rows])

    async def system_api(self, request: Request) -> Response:
        identity = self._admin_identity(request, "panel.read")
        if isinstance(identity, Response): return identity
        return JSONResponse({
            "version": "0.5.1", "control_db": self.db_url.split("@")[-1], "database_ok": self.db.ping(), "ha_mode": self.ha_mode,
            "require_auth": self.require_auth, "upstream": self.settings.upstream_base_url, "upstream_health": self.settings.upstream_health_url,
            "router_mode": self.settings.mode, "router_policy": self.settings.policy,
        })

    # -------------------- internals --------------------

    def _admin_identity(self, request: Request, permission: str) -> Identity | Response:
        token = bearer(request.headers)
        identity = self.security.session_identity(token) or self.security.api_key_identity(token)
        if identity is None:
            return _error("authentication required", "auth_required", 401)
        if not identity.can(permission):
            self.db.audit(identity.actor, identity.role, "permission.denied", permission, "denied")
            return _error("permission denied", "permission_denied", 403)
        return identity

    def _detect_profile(self, request: Request, body: dict[str, Any], tier: str) -> str:
        explicit = request.headers.get("x-router-profile", "").lower().strip()
        identity: Identity = getattr(request.state, "v51_identity", Identity("anonymous", "user"))
        if explicit in {"fast", "standard", "strong", "coding", "vision"} and (identity.role in {"super_admin", "admin", "operator"} or getattr(self.settings, "allow_tier_overrides", False)):
            return explicit
        if _has_vision(body): return "vision"
        if _looks_like_code(body): return "coding"
        return tier

    def _inject_context(self, body: dict[str, Any], identity: Identity) -> None:
        metadata = body.get("metadata")
        hermes: dict[str, Any] = {}
        if isinstance(metadata, dict) and isinstance(metadata.get("hermes"), dict):
            hermes = dict(metadata["hermes"])
            metadata = dict(metadata)
            metadata.pop("hermes", None)
            if metadata: body["metadata"] = metadata
            else: body.pop("metadata", None)
        query = _last_user_text(body)
        contexts: list[str] = []
        kb_ids = [int(x) for x in hermes.get("knowledge_bases", []) if str(x).isdigit()]
        if kb_ids and query:
            ctx = self.knowledge.context(kb_ids, query, int(hermes.get("rag_limit", 4)))
            if ctx: contexts.append(ctx)
        scopes: list[tuple[str, str]] = [("user", identity.actor), ("team", identity.team)]
        if hermes.get("agent_id") is not None: scopes.append(("agent", str(hermes["agent_id"])))
        if hermes.get("project"): scopes.append(("project", str(hermes["project"])))
        if hermes.get("organization"): scopes.append(("organization", str(hermes["organization"])))
        mem = self.knowledge.memory_context(scopes)
        if mem: contexts.append(mem)
        if contexts:
            body.setdefault("messages", []).insert(0, {"role": "system", "content": "\n\n".join(contexts)})

    def _rate_limit(self, identity: Identity, estimated_tokens: int) -> dict[str, Any] | None:
        now = int(time.time()); minute = now // 60; day = now // 86400
        key_base = f"key:{identity.api_key_id}" if identity.api_key_id else f"actor:{identity.actor}"
        with self.db.session() as s:
            minute_key = key_base + f":m:{minute}"
            row = s.get(RateCounter, minute_key)
            if row is None:
                row = RateCounter(key=minute_key, window_start=minute, requests=0, tokens=0); s.add(row)
            if row.requests + 1 > identity.rpm: return {"message": f"RPM quota exceeded ({identity.rpm})", "scope": "rpm"}
            if row.tokens + estimated_tokens > identity.tpm: return {"message": f"TPM quota exceeded ({identity.tpm})", "scope": "tpm"}
            day_key = key_base + f":d:{day}"
            drow = s.get(RateCounter, day_key)
            if drow is None:
                drow = RateCounter(key=day_key, window_start=day, requests=0, tokens=0); s.add(drow)
            if drow.requests + 1 > identity.daily_requests: return {"message": f"daily request quota exceeded ({identity.daily_requests})", "scope": "daily"}
            row.requests += 1; row.tokens += estimated_tokens; drow.requests += 1; drow.tokens += estimated_tokens; s.commit()
        return None

    def _budget_guard(self, identity: Identity) -> JSONResponse | None:
        month = datetime.now(timezone.utc).replace(day=1, hour=0, minute=0, second=0, microsecond=0).isoformat()
        with self.db.session() as s:
            spent_user = float(s.scalar(select(func.coalesce(func.sum(RouteEvent.cost_usd), 0.0)).where(RouteEvent.ts >= month, RouteEvent.actor == identity.actor)) or 0.0)
            spent_team = float(s.scalar(select(func.coalesce(func.sum(RouteEvent.cost_usd), 0.0)).where(RouteEvent.ts >= month, RouteEvent.team == identity.team)) or 0.0)
            budgets = list(s.scalars(select(Budget)))
        checks: list[tuple[str, float, float]] = []
        if identity.monthly_budget_usd > 0: checks.append(("api_key", identity.monthly_budget_usd, spent_user))
        for b in budgets:
            if b.monthly_usd <= 0: continue
            if b.scope_type == "global":
                with self.db.session() as s:
                    spent = float(s.scalar(select(func.coalesce(func.sum(RouteEvent.cost_usd), 0.0)).where(RouteEvent.ts >= month)) or 0.0)
                checks.append(("global", b.monthly_usd * b.hard_stop_percent / 100, spent))
            elif b.scope_type == "user" and b.scope_value == identity.actor: checks.append(("user", b.monthly_usd * b.hard_stop_percent / 100, spent_user))
            elif b.scope_type == "team" and b.scope_value == identity.team: checks.append(("team", b.monthly_usd * b.hard_stop_percent / 100, spent_team))
        for scope, limit, spent in checks:
            if limit > 0 and spent >= limit:
                self.db.audit(identity.actor, identity.role, "budget.block", scope, "denied", {"spent": spent, "limit": limit})
                return _error(f"{scope} monthly budget exhausted", "budget_exhausted", 402)
        return None

    async def _run_agent(self, agent_id: int, task: str, messages: Any) -> dict[str, Any] | Response:
        with self.db.session() as s:
            agent = s.get(Agent, agent_id)
        if not agent or not agent.active: return _error("agent not found", "agent_not_found", 404)
        msg = list(messages) if isinstance(messages, list) else [{"role": "user", "content": task}]
        if agent.system_prompt: msg.insert(0, {"role": "system", "content": agent.system_prompt})
        # Internal orchestration stays on the public `auto` model so existing
        # SMART_ROUTER_ALLOW_TIER_OVERRIDES safety semantics are preserved.
        # A trusted v0.5.1 profile selects the desired capability pool instead.
        profile = agent.profile if agent.profile in {"fast", "standard", "strong", "coding", "vision"} else agent.tier
        if profile not in {"fast", "standard", "strong", "coding", "vision"}:
            profile = "auto"
        metadata = {"hermes": {"agent_id": agent.id, "knowledge_bases": _loads(agent.knowledge_json, [])}}
        body = {"model": "auto", "messages": msg, "metadata": metadata}
        return await self._local_chat(body, profile=profile)

    async def _local_chat(self, body: dict[str, Any], profile: str = "auto") -> dict[str, Any]:
        headers = {"authorization": f"Bearer {self.internal_token}"}
        if profile in {"fast", "standard", "strong", "coding", "vision"}: headers["x-router-profile"] = profile
        async with httpx.AsyncClient(timeout=max(30, float(getattr(self.settings, "read_timeout_seconds", 600)))) as client:
            r = await client.post("http://127.0.0.1:8080/v1/chat/completions", headers=headers, json=body)
            try: payload = r.json()
            except Exception: payload = {"error": {"message": r.text[:2000]}}
            if r.status_code >= 400: payload.setdefault("_http_status", r.status_code)
            return payload

    def _load_pricing(self, path: str) -> dict[str, Any]:
        try:
            with open(path, "r", encoding="utf-8") as fh: return json.load(fh)
        except Exception: return {}

    def _cost(self, model: str, tier: str, input_tokens: int, output_tokens: int) -> float:
        # Accept both model- and tier-keyed v0.5 pricing shapes; unknown prices remain zero.
        candidates = [self.pricing.get("models", {}).get(model), self.pricing.get("tiers", {}).get(tier), self.pricing.get(model), self.pricing.get(tier)]
        price = next((x for x in candidates if isinstance(x, dict)), {})
        inp = float(price.get("input_per_1m", price.get("input", 0)) or 0)
        out = float(price.get("output_per_1m", price.get("output", 0)) or 0)
        return round((input_tokens * inp + output_tokens * out) / 1_000_000, 8)


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None: return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


async def _json(request: Request) -> dict[str, Any]:
    try:
        data = await request.json()
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _error(message: str, code: str, status: int) -> JSONResponse:
    return JSONResponse({"error": {"message": message, "type": "hermes_v051", "code": code}}, status_code=status)


def _row_dict(row: Any, exclude: set[str] | None = None) -> dict[str, Any]:
    exclude = exclude or set()
    return {column.name: getattr(row, column.name) for column in row.__table__.columns if column.name not in exclude}


def _agent_dict(r: Agent) -> dict[str, Any]:
    return _row_dict(r, {"knowledge_json", "plugins_json", "permissions_json"}) | {"knowledge": _loads(r.knowledge_json, []), "plugins": _loads(r.plugins_json, []), "permissions": _loads(r.permissions_json, [])}


def _team_dict(r: Team) -> dict[str, Any]:
    return _row_dict(r, {"agent_ids_json"}) | {"agent_ids": _loads(r.agent_ids_json, [])}


def _plugin_dict(r: Plugin) -> dict[str, Any]:
    return _row_dict(r, {"manifest_json"}) | {"manifest": _loads(r.manifest_json, {})}


def _loads(value: str, fallback: Any) -> Any:
    try: return json.loads(value)
    except Exception: return fallback


def _estimate_tokens(body: dict[str, Any]) -> int:
    return max(1, len(json.dumps(body, ensure_ascii=False)) // 4)


def _last_user_text(body: dict[str, Any]) -> str:
    for msg in reversed(body.get("messages") or []):
        if isinstance(msg, dict) and msg.get("role") == "user":
            c = msg.get("content")
            if isinstance(c, str): return c
            if isinstance(c, list): return "\n".join(str(x.get("text", "")) for x in c if isinstance(x, dict) and x.get("type") == "text")
    return ""


def _has_vision(body: dict[str, Any]) -> bool:
    for msg in body.get("messages") or []:
        content = msg.get("content") if isinstance(msg, dict) else None
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get("type") in {"image_url", "input_image", "image"}: return True
    return False


_CODE = re.compile(r"```|\b(kubernetes|terraform|ansible|dockerfile|python|javascript|typescript|golang|rust|sql|debug|stack trace|compile|function|class|api endpoint|helm|yaml)\b", re.I)

def _looks_like_code(body: dict[str, Any]) -> bool:
    return bool(_CODE.search(_last_user_text(body)))


def _cap_output(body: dict[str, Any], limit: int) -> None:
    for field in ("max_completion_tokens", "max_tokens"):
        if field in body:
            try: body[field] = min(int(body[field]), limit)
            except Exception: body[field] = limit
            return
    body["max_tokens"] = limit


def _usage_from_response(response: Response) -> tuple[int, int]:
    body = getattr(response, "body", b"")
    if not body: return (0, 0)
    try:
        payload = json.loads(body)
        usage = payload.get("usage") or {}
        return (int(usage.get("prompt_tokens", usage.get("input_tokens", 0)) or 0), int(usage.get("completion_tokens", usage.get("output_tokens", 0)) or 0))
    except Exception: return (0, 0)


def _extract_text(payload: dict[str, Any]) -> str:
    try: return str(payload["choices"][0]["message"]["content"])
    except Exception: return json.dumps(payload, ensure_ascii=False)[:12000]
