from __future__ import annotations

import json
import time
from dataclasses import replace
from typing import Any

import httpx
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse, Response
from starlette.routing import Route

from .budget import apply_output_budget
from .config import Settings
from .database import SessionStore
from .metrics import CAPABILITY_UPGRADES, REQUESTS, STICKY_ACTIONS, UPSTREAM_SECONDS
from .observations import ObservationWriter
from .privacy import stable_session_id
from .proxy import forwarded_headers, proxy_json, proxy_stream
from .routing import AUTO_ALIASES, Decision, PolicyEngine, decide


class RouterRuntime:
    def __init__(
        self,
        settings: Settings,
        transport: httpx.AsyncBaseTransport | None = None,
    ):
        self.settings = settings
        self.engine = PolicyEngine(settings)
        self.store = SessionStore(settings.database_path)
        self.observations = ObservationWriter(
            settings.observation_file,
            settings.observation_max_bytes,
            settings.observation_enabled,
        )
        self.client = httpx.AsyncClient(
            timeout=httpx.Timeout(
                settings.read_timeout_seconds,
                connect=settings.connect_timeout_seconds,
            ),
            transport=transport,
        )

    async def close(self) -> None:
        await self.client.aclose()


def create_app(
    settings: Settings | None = None,
    transport: httpx.AsyncBaseTransport | None = None,
) -> Starlette:
    settings = settings or Settings.from_env()
    runtime = RouterRuntime(settings, transport=transport)

    async def health(_: Request) -> JSONResponse:
        return JSONResponse({"status": "ok", "version": "0.2.0", "mode": settings.mode, "policy": runtime.engine.name})

    async def ready(_: Request) -> JSONResponse:
        try:
            # Models endpoint is OpenAI-compatible for both supported gateways.
            response = await runtime.client.get(f"{settings.upstream_base_url}/models", headers=forwarded_headers({}, settings.upstream_api_key))
            return JSONResponse({"ready": response.status_code < 500, "upstream_status": response.status_code}, status_code=200 if response.status_code < 500 else 503)
        except Exception as exc:
            return JSONResponse({"ready": False, "error": type(exc).__name__}, status_code=503)

    async def metrics(_: Request) -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    async def policy(_: Request) -> JSONResponse:
        return JSONResponse({"mode": settings.mode, "policy_version": settings.policy_version, **runtime.engine.describe()})

    async def models(request: Request) -> Response:
        url = f"{settings.upstream_base_url}/models"
        headers = forwarded_headers(dict(request.headers), settings.upstream_api_key)
        try:
            upstream = await runtime.client.get(url, headers=headers)
        except httpx.HTTPError as exc:
            return JSONResponse({"error": {"message": f"upstream unavailable: {type(exc).__name__}", "type": "upstream_error"}}, status_code=502)
        if upstream.status_code >= 400:
            return Response(upstream.content, status_code=upstream.status_code, media_type=upstream.headers.get("content-type"))
        try:
            payload = upstream.json()
        except ValueError:
            return Response(upstream.content, status_code=upstream.status_code, media_type=upstream.headers.get("content-type"))
        if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
            return JSONResponse(payload, status_code=upstream.status_code)
        existing = {str(item.get("id")) for item in payload["data"] if isinstance(item, dict)}
        virtual = []
        now = int(time.time())
        for alias in ("auto", "auto-fast", "auto-standard", "auto-strong"):
            if alias not in existing:
                virtual.append({"id": alias, "object": "model", "created": now, "owned_by": "hermes-smart-router"})
        payload["data"] = virtual + payload["data"]
        return JSONResponse(payload, status_code=upstream.status_code)

    async def chat(request: Request) -> Response:
        raw = await request.body()
        if len(raw) > settings.max_request_bytes:
            return JSONResponse({"error": {"message": "request too large", "type": "invalid_request_error"}}, status_code=413)
        try:
            body = json.loads(raw)
            if not isinstance(body, dict):
                raise ValueError
        except Exception:
            return JSONResponse({"error": {"message": "invalid JSON object", "type": "invalid_request_error"}}, status_code=400)

        initial = decide(body, settings, runtime.engine)
        session_hash, session_source = stable_session_id(settings.hmac_secret, {k.lower(): v for k, v in request.headers.items()}, body)
        if session_hash is not None:
            sticky = runtime.store.choose(
                session_hash,
                initial.selected_tier,
                policy_version=settings.policy_version,
                ttl_seconds=settings.session_ttl_seconds,
                max_age_seconds=settings.max_session_age_seconds,
                demotion_turns=settings.demotion_turns,
            )
            selected_tier = sticky.tier
            sticky_action = sticky.action
        else:
            selected_tier = initial.selected_tier
            sticky_action = "no_stable_session"
        selected_model = settings.tiers[selected_tier].model
        decision = replace(initial, selected_tier=selected_tier, selected_model=selected_model)

        requested_model = str(body.get("model") or "auto")
        is_router_alias = requested_model.lower() in AUTO_ALIASES
        routed = settings.mode == "route" and is_router_alias
        outbound = dict(body)
        budget_meta: dict[str, Any] | None = None
        if routed:
            outbound["model"] = selected_model
            outbound, budget_meta = apply_output_budget(outbound, settings.tiers[selected_tier].max_output_tokens)
        elif settings.mode == "observe" and is_router_alias:
            outbound["model"] = settings.observe_model

        event = {
            "event": "route_decision",
            "mode": settings.mode,
            "policy": decision.policy,
            "policy_version": settings.policy_version,
            "session": session_hash,
            "session_source": session_source,
            "sticky_action": sticky_action,
            "requested_model_kind": "router_alias" if is_router_alias else "passthrough",
            "proposed_tier": decision.proposed_tier,
            "selected_tier": decision.selected_tier,
            "selected_model": outbound.get("model"),
            "score": decision.score,
            "reasons": decision.reasons,
            "capability_upgraded": decision.capability_upgraded,
            "facts": decision.safe_dict()["facts"],
            "budget": budget_meta,
        }
        runtime.observations.write(event)
        STICKY_ACTIONS.labels(sticky_action.split(":", 1)[0]).inc()
        if initial.capability_upgraded:
            CAPABILITY_UPGRADES.labels(initial.proposed_tier, initial.selected_tier).inc()

        url = f"{settings.upstream_base_url}/chat/completions"
        headers = forwarded_headers(dict(request.headers), settings.upstream_api_key)
        # Preserve the original request bytes whenever Smart Router did not
        # modify the OpenAI payload. This keeps explicit model passthrough
        # byte-transparent.
        if outbound == body:
            payload = raw
        else:
            payload = json.dumps(outbound, separators=(",", ":")).encode()
        started = time.monotonic()
        try:
            if outbound.get("stream") is True:
                response = await proxy_stream(runtime.client, "POST", url, headers, payload)
                status = str(response.status_code)
            else:
                response = await proxy_json(runtime.client, "POST", url, headers, payload)
                status = str(response.status_code)
            return response
        except httpx.HTTPError as exc:
            REQUESTS.labels(settings.mode, selected_tier, decision.policy, "upstream_error").inc()
            return JSONResponse({"error": {"message": f"upstream unavailable: {type(exc).__name__}", "type": "upstream_error"}}, status_code=502)
        finally:
            UPSTREAM_SECONDS.observe(time.monotonic() - started)
            if 'status' in locals():
                REQUESTS.labels(settings.mode, selected_tier, decision.policy, status).inc()

    routes = [
        Route("/health", health),
        Route("/ready", ready),
        Route("/metrics", metrics),
        Route("/router/policy", policy),
        Route("/v1/models", models, methods=["GET"]),
        Route("/v1/chat/completions", chat, methods=["POST"]),
    ]
    app = Starlette(routes=routes)
    app.state.runtime = runtime

    @app.on_event("shutdown")
    async def shutdown() -> None:
        await runtime.close()

    return app
