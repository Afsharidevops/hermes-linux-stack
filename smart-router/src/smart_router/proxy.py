from __future__ import annotations

import httpx
from starlette.responses import Response, StreamingResponse

HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length"}


def forwarded_headers(headers: dict[str, str], upstream_api_key: str | None) -> dict[str, str]:
    out = {k: v for k, v in headers.items() if k.lower() not in HOP_BY_HOP}
    if upstream_api_key:
        out["authorization"] = f"Bearer {upstream_api_key}"
    return out


async def proxy_json(client: httpx.AsyncClient, method: str, url: str, headers: dict[str, str], body: bytes | None = None) -> Response:
    response = await client.request(method, url, headers=headers, content=body)
    clean = {k: v for k, v in response.headers.items() if k.lower() not in HOP_BY_HOP}
    return Response(response.content, status_code=response.status_code, headers=clean, media_type=response.headers.get("content-type"))


async def proxy_stream(client: httpx.AsyncClient, method: str, url: str, headers: dict[str, str], body: bytes) -> StreamingResponse:
    request = client.build_request(method, url, headers=headers, content=body)
    response = await client.send(request, stream=True)
    clean = {k: v for k, v in response.headers.items() if k.lower() not in HOP_BY_HOP}

    async def iterator():
        try:
            async for chunk in response.aiter_raw():
                yield chunk
        finally:
            await response.aclose()

    return StreamingResponse(iterator(), status_code=response.status_code, headers=clean, media_type=response.headers.get("content-type"))
