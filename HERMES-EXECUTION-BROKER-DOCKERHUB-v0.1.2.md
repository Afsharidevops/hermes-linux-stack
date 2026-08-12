# Hermes Execution Broker 0.1.2

Hermes Execution Broker is the isolated execution security boundary used by Hermes Linux Stack.

## Image

```text
afsharidevops/hermes-execution-broker:0.1.2
```

Publish for:

```text
linux/amd64
linux/arm64
```

## Modes

- `docker` — local sandbox + structured Docker operations, with Docker socket isolated to this mode.
- `ssh` — structured SSH operations using locally managed profiles.
- `approver` — independent Telegram approval bot and Ed25519 signing authority.
- `admin` — v0.1.2 configuration boundary used by Hermes Operations Center v0.5.7.

The `admin` mode can update live execution feature policy, numeric approver users, the write-only dedicated approval-bot token and broker control secret. It intentionally does **not** mount the approval signing key, Docker socket, or SSH private credentials.

Use the broker through the Hermes Linux Stack Compose/managers rather than as an unrestricted remote shell/API.
