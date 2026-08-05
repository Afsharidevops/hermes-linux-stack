from __future__ import annotations

from collections.abc import AsyncIterator

import httpx
from starlette.background import BackgroundTask
from starlette.responses import Response, StreamingResponse

STATIC_HOP_BY_HOP = {
    b"connection",
    b"keep-alive",
    b"proxy-authenticate",
    b"proxy-authorization",
    b"te",
    b"trailer",
    b"transfer-encoding",
    b"upgrade",
    b"host",
    b"content-length",
}
SINGLETON_CREDENTIALS = {b"authorization", b"x-api-key", b"x-goog-api-key"}
ROUTER_PRIVATE = {b"x-router-session", b"x-router-tier", b"x-router-reset", b"x-router-cache"}


def forward_headers(headers: list[tuple[bytes, bytes]]) -> list[tuple[bytes, bytes]]:
    excluded = _excluded_headers(headers)
    credential_counts: dict[bytes, int] = {}
    result: list[tuple[bytes, bytes]] = []
    for name, value in headers:
        lower = name.lower()
        if lower in SINGLETON_CREDENTIALS:
            credential_counts[lower] = credential_counts.get(lower, 0) + 1
            if credential_counts[lower] > 1:
                raise ValueError(f"duplicate credential header: {lower.decode()}")
        if lower not in excluded and lower not in ROUTER_PRIVATE:
            result.append((name, value))
    return result


def response_header_pairs(headers: httpx.Headers) -> list[tuple[bytes, bytes]]:
    raw = list(headers.raw)
    excluded = _excluded_headers(raw)
    return [(name, value) for name, value in raw if name.lower() not in excluded]


async def proxy_buffered(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    headers: list[tuple[bytes, bytes]],
    content: bytes | None = None,
) -> Response:
    request = client.build_request(method, url, headers=headers, content=content)
    upstream = await client.send(request, stream=True)
    try:
        if upstream.is_stream_consumed:
            body = upstream.content
        else:
            body = b"".join([chunk async for chunk in upstream.aiter_raw()])
        response = Response(body, status_code=upstream.status_code)
        response.raw_headers = response_header_pairs(upstream.headers)
        return response
    finally:
        await upstream.aclose()


async def proxy_streaming(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    headers: list[tuple[bytes, bytes]],
    content: bytes,
) -> StreamingResponse:
    request = client.build_request(method, url, headers=headers, content=content)
    upstream = await client.send(request, stream=True)

    async def chunks() -> AsyncIterator[bytes]:
        async for chunk in upstream.aiter_raw():
            yield chunk

    response = StreamingResponse(
        chunks(),
        status_code=upstream.status_code,
        media_type=None,
        background=BackgroundTask(upstream.aclose),
    )
    response.raw_headers = response_header_pairs(upstream.headers)
    return response


def _excluded_headers(headers: list[tuple[bytes, bytes]]) -> set[bytes]:
    excluded = set(STATIC_HOP_BY_HOP)
    for name, value in headers:
        if name.lower() == b"connection":
            excluded.update(
                token.strip().lower()
                for token in value.split(b",")
                if token.strip()
            )
    return excluded
