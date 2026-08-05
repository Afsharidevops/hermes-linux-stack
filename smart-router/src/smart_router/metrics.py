from prometheus_client import Counter, Gauge, Histogram

REQUESTS = Counter(
    "smart_router_requests_total",
    "Requests processed by the smart router",
    ("endpoint", "mode", "request_kind", "stream", "status_class"),
)
PROPOSED_TIERS = Counter(
    "smart_router_proposed_tier_total",
    "Proposed routing decisions; not realized savings",
    ("mode", "tier", "reason"),
)
PROPOSED_OUTPUT = Histogram(
    "smart_router_proposed_output_limit_tokens",
    "Proposed output limits; observation values are not enforced",
    buckets=(256, 512, 700, 1024, 1200, 2048, 2500, 4096, 6144, 8192),
)
EFFECTIVE_OUTPUT = Histogram(
    "smart_router_effective_output_limit_tokens",
    "Effective output limit sent upstream when known",
    buckets=(256, 512, 700, 1024, 1200, 2048, 2500, 4096, 6144, 8192),
)
BUDGET_ENFORCEMENTS = Counter(
    "smart_router_budget_enforcements_total",
    "Output budget changes enforced in route mode",
    ("tier", "field"),
)
TOKEN_ESTIMATES = Counter(
    "smart_router_input_tokens_estimated_total",
    "Approximate input tokens by component",
    ("component",),
)
UPSTREAM_INPUT_TOKENS = Counter(
    "smart_router_upstream_input_tokens_total",
    "Actual upstream input usage when reported",
)
UPSTREAM_CACHED_INPUT_TOKENS = Counter(
    "smart_router_upstream_cached_input_tokens_total",
    "Actual upstream cached-input usage when reported",
)
UPSTREAM_OUTPUT_TOKENS = Counter(
    "smart_router_upstream_output_tokens_total",
    "Actual upstream output usage when reported",
)
USAGE_MISSING = Counter(
    "smart_router_usage_missing_total",
    "Responses for which actual upstream usage was unavailable",
    ("stream",),
)
STICKY = Counter(
    "smart_router_sticky_routes_total",
    "Sticky-route outcomes",
    ("action", "source", "tier"),
)
UPSTREAM_ERRORS = Counter(
    "smart_router_upstream_errors_total",
    "Upstream errors by status class",
    ("status_class",),
)
FAIL_OPEN = Counter(
    "smart_router_fail_open_total",
    "Auto requests mapped to the configured fail-open model",
    ("reason",),
)
DURATION = Histogram(
    "smart_router_request_duration_seconds",
    "End-to-end request duration",
    ("mode", "request_kind", "stream"),
)
ACTIVE_STREAMS = Gauge(
    "smart_router_active_streams",
    "Currently active streaming responses",
)
READINESS = Gauge(
    "smart_router_readiness",
    "Readiness state by component",
    ("component",),
)
