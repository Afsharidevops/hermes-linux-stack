# Hermes Stack Execution Broker

Security boundary image for the optional execution tools in [Hermes Linux Stack](https://github.com/Afsharidevops/hermes-linux-stack). It is not a general remote shell or Docker API proxy.

## Purpose and security model

The image runs one of three narrowly scoped modes. Hermes can prepare structured operations through an authenticated broker, but cannot independently approve or execute them. A separate approver recomputes the canonical digest and exact human-readable summary, sends that summary through a dedicated Telegram bot to an authorized numeric user, and signs a one-time decision. Brokers persist the exact grant and atomically consume it once. The independent signed Telegram decision is the broker's trust root; Hermes's native manual prompt is defense in depth and is not treated as an independent security boundary.

Authority is separated by Compose mounts:

- Hermes receives only the broker control secret and execution-user policy.
- Docker mode alone receives the Docker socket and the approver public verification key.
- SSH mode alone receives read-only SSH profiles and the approver public verification key.
- Approver mode alone receives the Telegram approval-bot token and private signing key.

The shared request-authentication secret lets brokers submit sealed requests to the approver. It cannot forge a signed approval. Broker ports are not published.

## Modes

- `docker`: local sandbox and structured Docker operations. Local execution uses a digest-pinned image, sealed workspace generation, non-root identity, read-only root, dropped capabilities, and no network by default.
- `ssh`: commands through locally managed profiles with sealed host, user, authority, private-key digest/public fingerprint, and known-hosts digest/fingerprint.
- `approver`: Telegram long polling, persistent one-time inline approval/denial, and Ed25519 decision signing. It has no Docker socket, SSH profiles, or broker capability database.

All modes use Python standard-library HTTP. The image also contains OpenSSH client for SSH mode and OpenSSL for approval signing/verification.

## Use through the stack

Use this image through the repository's `docker-compose.yml` and `manage.sh`; do not start it as a standalone privileged container. The stack creates mode-`0700` state directories and mode-`0600` secret files, keeps execution disabled until approval configuration is complete, and applies read-only filesystems, dropped capabilities, `no-new-privileges`, bounded PIDs, private control networking, and mode-specific egress.

Configure the approval bot without placing its token in argv:

```text
./manage.sh set-execution-approval-bot-token
```

Then configure execution users and explicitly enable only required features. See the stack README and SECURITY policy for the complete lifecycle.

## Required configuration

Compose supplies these mode-specific settings. Paths are descriptive; secret values must never be put in image arguments, environment examples, logs, or public Compose files.

| Mode | Required environment | Required read-only authority mounts | Writable state |
|---|---|---|---|
| docker | `BROKER_MODE=docker`, feature/policy/workspace settings, approver and callback URLs | control secret, approval-request secret, approval public key, Docker socket | capability state |
| ssh | `BROKER_MODE=ssh`, feature/policy settings, approver and callback URLs | control secret, approval-request secret, approval public key, SSH profiles | capability state |
| approver | `BROKER_MODE=approver`, policy generation, bot/users paths, broker callback URLs | approval-request secret, approval private key, approval bot token, numeric users policy | approval state |

Do not mount the private signing key or approval bot token into Hermes or either broker. Do not mount the Docker socket outside Docker mode or SSH profiles outside SSH mode. Do not publish broker/approver ports or attach brokers to the general stack network.

There are deliberately no safe standalone defaults for execution authority: empty/missing secrets, keys, users, token, image seal, workspace seal, or feature policy make readiness and operations fail closed.

## Tags and platforms

Use the versioned tag `afsharidevops/hermes-execution-broker:0.1.1` or its immutable manifest digest. `latest` is unsuitable for a security boundary because it is mutable. Version `0.1.1` is published for Linux `amd64`; it removes stale Telegram webhooks before long polling and waits for the exact independent decision within the sealed request's TTL. Confirm the tag's manifest before deployment. Source, Compose wiring, operational commands, and security documentation live in the Hermes Linux Stack repository linked above.
