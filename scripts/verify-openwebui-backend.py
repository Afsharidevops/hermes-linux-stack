import json
import os
import time
import urllib.request

base_url = os.environ["OPENAI_API_BASE_URL"].rstrip("/")
api_key = os.environ["OPENAI_API_KEY"]
last_error = None
for _ in range(20):
    try:
        request = urllib.request.Request(
            f"{base_url}/models",
            headers={"Authorization": f"Bearer {api_key}"},
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.load(response)
        models = payload.get("data")
        if not isinstance(models, list):
            raise RuntimeError("OmniRoute /models response has no data array")
        print(f"Open WebUI backend verified: OmniRoute returned {len(models)} model entries")
        break
    except Exception as error:
        last_error = error
        time.sleep(2)
else:
    raise SystemExit(f"Open WebUI backend verification failed: {last_error}")
