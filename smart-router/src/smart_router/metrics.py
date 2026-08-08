from prometheus_client import Counter, Histogram

REQUESTS = Counter("smart_router_requests_total", "Requests processed", ["mode", "tier", "policy", "status"])
CAPABILITY_UPGRADES = Counter("smart_router_capability_upgrades_total", "Requests upgraded by capability gates", ["from_tier", "to_tier"])
STICKY_ACTIONS = Counter("smart_router_sticky_actions_total", "Sticky session actions", ["action"])
UPSTREAM_SECONDS = Histogram("smart_router_upstream_seconds", "Upstream request latency seconds")
