# Smart Router integration

This release keeps the existing Hermes Smart Router as an optional component and changes only its upstream to OmniRoute:

- Smart Router listens inside the stack at `http://smart-router:8080/v1`.
- Its upstream is `http://omniroute:20129/v1`.
- Default observe/fail-open/tier model names are `auto`, so a fresh OmniRoute installation can work without recreating legacy combo names.
- Operators can replace `SMART_ROUTER_*_MODEL` values in `.env` with explicit OmniRoute model, endpoint, or combo names after configuring OmniRoute.

The Compose stack consumes the existing published `afsharidevops/hermes-smart-router` image. No Smart Router protocol change was required because both routers expose OpenAI-compatible HTTP.
