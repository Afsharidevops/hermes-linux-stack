from __future__ import annotations

import asyncio
import json
import logging
import time
from contextlib import asynccontextmanager
from typing import Any
from urllib.parse import urlencode

import httpx
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Route

from . import __version__
from .budget import BudgetResult, enforce_budget, propose_budget
from .config import Settings
from .database import RouteStore
from .metrics import (
    ACTIVE_STREAMS,
    BUDGET_ENFORCEMENTS,
    DURATION,
    EFFECTIVE_OUTPUT,
    FAIL_OPEN,
    PROPOSED_OUTPUT,
    PROPOSED_TIERS,
    READINESS,
    REQUESTS,
    STICKY,
    TOKEN_ESTIMATES,
    UPSTREAM_CACHED_INPUT_TOKENS,
    UPSTREAM_ERRORS,
    UPSTREAM_INPUT_TOKENS,
    UPSTREAM_OUTPUT_TOKENS,
    USAGE_MISSING,
)
from .privacy import session_identity
from .proxy import forward_headers, proxy_buffered, proxy_streaming, response_header_pairs
from .routing import AUTO_ALIASES, Decision, decide

logger = logging.getLogger("smart-router")
logging.basicConfig(level=logging.INFO, format="%(message)s")


def create_app(
    settings: Settings | None = None,
    transport: httpx.AsyncBaseTransport | None = None,
) -> Starlette:
    settings = settings or Settings.from_env()
    store = RouteStore(settings)
    timeout = httpx.Timeout(
        connect=settings.connect_timeout_seconds,
        read=settings.read_timeout_seconds,
        write=settings.read_timeout_seconds,
        pool=settings.connect_timeout_seconds,
    )

    @asynccontextmanager
    async def lifespan(app: Starlette):
        app.state.client = httpx.AsyncClient(timeout=timeout, transport=transport)
        try:
            yield
        finally:
            await app.state.client.aclose()

    async def health(_: Request) -> JSONResponse:
        return JSONResponse({"status": "ok", "version": __version__})

    async def ready(request: Request) -> JSONResponse:
        database_ok = store.ready()
        upstream_ok = False
        try:
            response = await request.app.state.client.get(
                settings.upstream_base_url.removesuffix("/v1") + "/api/health"
            )
            upstream_ok = response.is_success
        except httpx.HTTPError:
            pass
        READINESS.labels("database").set(int(database_ok))
        READINESS.labels("upstream").set(int(upstream_ok))
        ready_ok = database_ok and upstream_ok
        return JSONResponse(
            {
                "status": "ready" if ready_ok else "not-ready",
                "components": {"database": database_ok, "upstream": upstream_ok},
            },
            status_code=200 if ready_ok else 503,
        )

    async def metrics(_: Request) -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    async def models(request: Request) -> Response:
        started = time.monotonic()
        try:
            headers = forward_headers(request.scope["headers"])
        except ValueError as error:
            return _openai_error(str(error), "duplicate_credential_header", 400)
        url = settings.upstream_base_url + "/models"
        if request.scope["query_string"]:
            url += "?" + request.scope["query_string"].decode("ascii")
        try:
            upstream = await request.app.state.client.get(url, headers=headers)
            upstream.read()
        except httpx.HTTPError:
            return _openai_error("upstream unavailable", "upstream_unavailable", 503)
        response: Response
        if upstream.is_success:
            try:
                payload = upstream.json()
                existing = {item.get("id") for item in payload.get("data", [])}
                for alias in AUTO_ALIASES:
                    if alias not in existing:
                        payload.setdefault("data", []).append(
                            {"id": alias, "object": "model", "owned_by": "smart-router"}
                        )
                response = JSONResponse(payload, status_code=upstream.status_code)
                response.raw_headers = [
                    (name, value)
                    for name, value in response_header_pairs(upstream.headers)
                    if name.lower() not in {b"content-encoding", b"content-length"}
                ] + [
                    (b"content-length", str(len(response.body)).encode()),
                ]
            except (ValueError, TypeError):
                response = Response(upstream.content, status_code=upstream.status_code)
                response.raw_headers = response_header_pairs(upstream.headers)
        else:
            response = Response(upstream.content, status_code=upstream.status_code)
            response.raw_headers = response_header_pairs(upstream.headers)
        _record_request("models", settings.mode, "explicit", False, response.status_code, started)
        return response

    async def completions(request: Request) -> Response:
        started = time.monotonic()
        try:
            raw = await _bounded_body(request, settings.max_request_bytes)
        except ValueError:
            return _openai_error("request body too large", "request_too_large", 413)
        try:
            body = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            return _openai_error("invalid JSON body", "invalid_json", 400)
        if not isinstance(body, dict) or not isinstance(body.get("model"), str):
            return _openai_error("model is required", "invalid_model", 400)

        requested_model = body["model"]
        stream = body.get("stream") is True
        try:
            headers = forward_headers(request.scope["headers"])
        except ValueError as error:
            return _openai_error(str(error), "duplicate_credential_header", 400)
        url = settings.upstream_base_url + "/chat/completions"
        if request.scope["query_string"]:
            url += "?" + request.scope["query_string"].decode("ascii")

        if requested_model not in AUTO_ALIASES:
            return await _dispatch(
                request,
                raw,
                headers,
                url,
                stream,
                settings.mode,
                "explicit",
                started,
            )

        requested_tier = AUTO_ALIASES[requested_model]
        header_tier = request.headers.get("x-router-tier")
        if header_tier in {"fast", "standard", "strong"}:
            requested_tier = header_tier
        try:
            decision = decide(body, settings, requested_tier)
            proposal = propose_budget(body, decision, settings)
        except (TypeError, ValueError, OverflowError) as error:
            return _openai_error(str(error), "invalid_routing_request", 422)

        _safe_record_proposal(decision, proposal, settings.mode)
        session_hash, session_source = session_identity(
            request.headers, body, settings.hmac_secret
        )
        selected_tier = decision.proposed_tier
        sticky_action = "stateless"
        if settings.mode == "route" and session_hash:
            try:
                if request.headers.get("x-router-reset", "").lower() == "true":
                    await asyncio.to_thread(store.reset, session_hash, requested_model)
                sticky = await asyncio.to_thread(
                    store.resolve,
                    session_hash,
                    requested_model,
                    decision.proposed_tier,
                    decision.reasons[-1],
                )
                selected_tier = sticky.tier
                sticky_action = sticky.action
                STICKY.labels(sticky.action, session_source, sticky.tier).inc()
            except Exception as error:
                sticky_action = "store-error-stateless"
                logger.error(
                    json.dumps(
                        {"event": "sticky_store_error", "reason": type(error).__name__}
                    )
                )
        if settings.mode == "observe":
            effective_model = settings.observe_model
            budget = BudgetResult(
                proposal.client_limit,
                proposal.proposed_limit,
                proposal.client_limit,
                False,
                proposal.fields,
            )
        else:
            effective_model = settings.tier(selected_tier).model
            if selected_tier != decision.proposed_tier:
                selected_decision = Decision(
                    selected_tier,
                    effective_model,
                    decision.score,
                    decision.reasons,
                    decision.facts,
                )
                proposal = propose_budget(body, selected_decision, settings)
            budget = enforce_budget(body, proposal, settings)
            if budget.enforced:
                BUDGET_ENFORCEMENTS.labels(
                    selected_tier, "+".join(budget.fields) or "none"
                ).inc()
        body["model"] = effective_model
        outbound = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode()
        _safe_log_decision(
            settings.mode,
            requested_model,
            effective_model,
            decision,
            selected_tier,
            budget,
            session_source,
            sticky_action,
        )

        return await _dispatch(
            request,
            outbound,
            headers,
            url,
            stream,
            settings.mode,
            "auto",
            started,
        )

    routes = [
        Route("/health", health),
        Route("/ready", ready),
        Route("/metrics", metrics),
        Route("/v1/models", models, methods=["GET"]),
        Route("/v1/chat/completions", completions, methods=["POST"]),
    ]
    app = Starlette(routes=routes, lifespan=lifespan)
    app.state.settings = settings
    app.state.store = store
    return app


async def _dispatch(
    request: Request,
    content: bytes,
    headers: dict[str, str],
    url: str,
    stream: bool,
    mode: str,
    request_kind: str,
    started: float,
) -> Response:
    try:
        if stream:
            ACTIVE_STREAMS.inc()

            def stream_complete(completed: bool) -> None:
                ACTIVE_STREAMS.dec()
                USAGE_MISSING.labels("true").inc()
                _record_request(
                    "chat",
                    mode,
                    request_kind,
                    True,
                    response.status_code if completed else 502,
                    started,
                )

            response = await proxy_streaming(
                request.app.state.client,
                "POST",
                url,
                headers,
                content,
                on_complete=stream_complete,
            )
        else:
            response = await proxy_buffered(
                request.app.state.client, "POST", url, headers, content
            )
            _record_actual_usage(response)
    except httpx.HTTPError as error:
        logger.error(json.dumps({"event": "upstream_error", "reason": type(error).__name__}))
        _record_request("chat", mode, request_kind, stream, 503, started)
        return _openai_error("upstream unavailable", "upstream_unavailable", 503)
    if response.status_code >= 400:
        UPSTREAM_ERRORS.labels(_status_class(response.status_code)).inc()
    if not stream:
        _record_request("chat", mode, request_kind, False, response.status_code, started)
    return response


def _safe_record_proposal(decision: Decision, budget: BudgetResult, mode: str) -> None:
    try:
        _record_proposal(decision, budget, mode)
    except Exception as error:  # metrics must never break routing
        logger.error(json.dumps({"event": "metrics_error", "reason": type(error).__name__}))


def _safe_log_decision(*args: object) -> None:
    try:
        _log_decision(*args)  # type: ignore[arg-type]
    except Exception as error:
        logger.error(json.dumps({"event": "log_error", "reason": type(error).__name__}))


def _record_proposal(decision: Decision, budget: BudgetResult, mode: str) -> None:
    PROPOSED_TIERS.labels(mode, decision.proposed_tier, decision.reasons[0]).inc()
    PROPOSED_OUTPUT.observe(budget.proposed_limit)
    facts = decision.facts
    TOKEN_ESTIMATES.labels("messages").inc(facts.estimated_message_tokens)
    TOKEN_ESTIMATES.labels("tool_schema").inc(facts.estimated_tool_schema_tokens)
    TOKEN_ESTIMATES.labels("tool_results").inc(facts.estimated_tool_result_tokens)
    TOKEN_ESTIMATES.labels("total").inc(facts.estimated_total_tokens)


def _record_actual_usage(response: Response) -> None:
    found = False
    try:
        payload = json.loads(response.body)
        usage = payload.get("usage") or {}
        prompt = usage.get("prompt_tokens") or usage.get("input_tokens")
        completion = usage.get("completion_tokens") or usage.get("output_tokens")
        details = usage.get("prompt_tokens_details") or usage.get("input_tokens_details") or {}
        cached = details.get("cached_tokens")
        if isinstance(prompt, (int, float)):
            UPSTREAM_INPUT_TOKENS.inc(prompt)
            found = True
        if isinstance(cached, (int, float)):
            UPSTREAM_CACHED_INPUT_TOKENS.inc(cached)
            found = True
        if isinstance(completion, (int, float)):
            UPSTREAM_OUTPUT_TOKENS.inc(completion)
            found = True
    except (ValueError, TypeError, AttributeError):
        pass
    if not found:
        USAGE_MISSING.labels("false").inc()


def _log_decision(
    mode: str,
    requested_model: str,
    effective_model: str,
    decision: Decision,
    selected_tier: str,
    budget: BudgetResult,
    session_source: str,
    sticky_action: str,
) -> None:
    logger.info(
        json.dumps(
            {
                "event": "route_decision",
                "mode": mode,
                "requested_model": requested_model,
                "effective_model": effective_model,
                "proposed_tier": decision.proposed_tier,
                "selected_tier": selected_tier,
                "proposed_model": decision.proposed_model,
                "score": decision.score,
                "reasons": decision.reasons,
                "session_source": session_source,
                "sticky_action": sticky_action,
                "client_output_limit": budget.client_limit,
                "effective_output_limit": budget.effective_limit,
                "proposed_output_limit": budget.proposed_limit,
                "budget_enforced": budget.enforced,
            },
            separators=(",", ":"),
        )
    )
    if budget.effective_limit is not None:
        EFFECTIVE_OUTPUT.observe(budget.effective_limit)


def _record_request(
    endpoint: str,
    mode: str,
    request_kind: str,
    stream: bool,
    status: int,
    started: float,
) -> None:
    REQUESTS.labels(endpoint, mode, request_kind, str(stream).lower(), _status_class(status)).inc()
    DURATION.labels(mode, request_kind, str(stream).lower()).observe(time.monotonic() - started)


def _status_class(status: int) -> str:
    return f"{status // 100}xx"


async def _bounded_body(request: Request, limit: int) -> bytes:
    chunks: list[bytes] = []
    size = 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > limit:
            raise ValueError("request too large")
        chunks.append(chunk)
    return b"".join(chunks)


def _openai_error(message: str, code: str, status: int) -> JSONResponse:
    return JSONResponse(
        {"error": {"message": message, "type": "smart_router_error", "code": code}},
        status_code=status,
    )

