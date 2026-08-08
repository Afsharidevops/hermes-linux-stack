import uvicorn

from .asgi import create_app


if __name__ == "__main__":
    uvicorn.run(create_app(), host="0.0.0.0", port=8080, log_level="info", access_log=False)
