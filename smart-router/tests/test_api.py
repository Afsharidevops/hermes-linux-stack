from __future__ import annotations

import json
from dataclasses import replace

import httpx
import pytest
import pytest_asyncio

from smart_router.main import create_app


class MockSSEStream(httpx.AsyncByteStream):
    async def __aiter__(self):
        yield b'data: {"id":"one"}\n\n'
        yield b'data: [DONE]\n\n'


class Capture:
    def __init__(self):
        self.requests: list[httpx.Request] = []

    async def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if request.url.path == "/api/health":
            return httpx.Response(200, json={"ok": True})
        if request.url.path == "/v1/models":
            return httpx.Response(
                200,
                json={"object": "list", "data": [{"id": "ai", "object": "model"}]},
            )
        body = json.loads(request.content)
        if body.get("stream"):
            return httpx.Response(
                200,
                headers={"content-type": "text/event-stream"},
                stream=MockSSEStream(),
            )
        return httpx.Response(
            200,
            json={
                "model": body["model"],
                "echo": body,
                "auth": request.headers.get("authorization"),
                "usage": {
                    "prompt_tokens": 10,
                    "completion_tokens": 2,
                    "prompt_tokens_details": {"cached_tokens": 4},
                },
            },
        )


@pytest_asyncio.fixture
async def observe_client(settings):
    capture = Capture()
    app = create_app(settings, httpx.MockTransport(capture.handler))
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://router"
        ) as client:
            yield client, capture


@pytest.mark.asyncio
async def test_observe_explicit_is_byte_transparent(observe_client):
    client, capture = observe_client
    raw = b'{ "model" : "ai", "max_tokens" : 6000, "messages" : [ ] }'
    response = await client.post(
        "/v1/chat/completions",
        content=raw,
        headers={"content-type": "application/json", "authorization": "Bearer key"},
    )
    assert response.status_code == 200
    assert capture.requests[-1].content == raw
    assert capture.requests[-1].headers["authorization"] == "Bearer key"


@pytest.mark.asyncio
async def test_observe_auto_changes_only_model_and_not_budget(observe_client):
    client, capture = observe_client
    original = {
        "model": "auto",
        "max_tokens": 6000,
        "messages": [{"role": "user", "content": "architecture review"}],
    }
    response = await client.post("/v1/chat/completions", json=original)
    assert response.status_code == 200
    forwarded = json.loads(capture.requests[-1].content)
    assert forwarded["model"] == "ai"
    assert forwarded["max_tokens"] == 6000
    assert {k: v for k, v in forwarded.items() if k != "model"} == {
        k: v for k, v in original.items() if k != "model"
    }


@pytest.mark.asyncio
async def test_route_explicit_is_unchanged(settings):
    capture = Capture()
    app = create_app(replace(settings, mode="route"), httpx.MockTransport(capture.handler))
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://router") as client:
            raw = b'{"model":"OpenCode-Free","max_tokens":9000,"messages":[]}'
            await client.post("/v1/chat/completions", content=raw)
            assert capture.requests[-1].content == raw


@pytest.mark.asyncio
async def test_route_auto_rewrites_and_clamps(settings):
    capture = Capture()
    app = create_app(replace(settings, mode="route"), httpx.MockTransport(capture.handler))
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://router") as client:
            response = await client.post(
                "/v1/chat/completions",
                json={
                    "model": "auto-standard",
                    "max_tokens": 9000,
                    "messages": [{"role": "user", "content": "hello"}],
                },
            )
            assert response.status_code == 200
            forwarded = json.loads(capture.requests[-1].content)
            assert forwarded["model"] == "combo-standard"
            assert forwarded["max_tokens"] == 4096


@pytest.mark.asyncio
async def test_models_include_auto_aliases(observe_client):
    client, _ = observe_client
    response = await client.get("/v1/models", headers={"Authorization": "Bearer key"})
    ids = {model["id"] for model in response.json()["data"]}
    assert {"ai", "auto", "auto-fast", "auto-standard", "auto-strong"} <= ids


@pytest.mark.asyncio
async def test_sse_bytes_are_preserved(observe_client):
    client, _ = observe_client
    response = await client.post(
        "/v1/chat/completions",
        json={"model": "ai", "stream": True, "messages": []},
    )
    assert response.content == b'data: {"id":"one"}\n\ndata: [DONE]\n\n'
