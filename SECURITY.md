# Security notes for the calibrated router package

Keep `.env`, `data/hermes/.env`, gateway state, `data/smart-router/router.sqlite3`, observations, n8n credentials and execution secrets out of version control.

Smart Router v0.2 deliberately keeps capability gates deterministic. A calibrated score can propose a tier but cannot downgrade past declared tool/vision/context requirements. Session identifiers are HMAC-pseudonymized before persistence.

Observation JSONL is designed for derived metadata only. Treat it as operational telemetry anyway: protect it with the same host access controls as other stack state. If you create calibration datasets containing full request bodies, keep those offline and private; prefer derived `features`/`facts` records.

The router is internal-only in Compose. 9router dashboard/API and Open WebUI default to loopback bindings in `.env.example`. Do not publish them broadly without authentication, TLS/reverse proxy, firewall policy, and gateway-specific hardening.

The optional execution services in the retained Compose file are high-trust features and remain disabled unless their profiles are explicitly selected. Review the upstream security documentation (`SECURITY.upstream.md` when present) before enabling them.
