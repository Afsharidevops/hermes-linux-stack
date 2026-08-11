# v0.5.3 change summary — 9router

## User experience

- `./manage.sh` now opens a grouped interactive manager by default.
- Added dedicated Services, Smart Router, Hermes, n8n, Execution, Maintenance, and Security menu groups.
- Smart Router mode/policy/time-window/feature choices are shown as numbered choices instead of requiring memorized values.
- Direct v0.5.2 commands remain backward compatible for scripts and automation.

## Hermes Smart Router Flight Deck

- Redesigned `/dashboard` as the Hermes Flight Deck with access state, time-window and auto-refresh selectors, routing-flow explanation, telemetry quality, route mix, and explicit zero/pricing states.
- Redesigned `/control/` navigation into Observe, Routing, Access, Intelligence, and System groups.
- Added dropdown/select controls for common finite-value choices such as roles, budget scopes, ACL effects, agent profiles, team strategy, plugin kind/risk, and API-key tiers.
- Dashboard and Control Plane link to each other.

## Compatibility

- Runtime/package version is 0.5.3.
- Fresh installs pin `afsharidevops/hermes-smart-router:0.5.3`.
- Existing v0.5.2 Control Plane SQLite/schema naming is intentionally preserved for in-place data compatibility.
- Corrected the installer status message so it reports the selected Smart Router mode instead of always saying observation mode.
