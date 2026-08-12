# Hermes Operations Center v0.5.5 — User and Administrator Guide

This guide mirrors the built-in **Docs** page in Hermes Operations Center and adds operational detail for server administrators.

## Routing mode

`model=auto` is the normal automatic-routing entry point. Explicit upstream model names pass through unchanged.

- `observe`: evaluate and record the automatic decision but dispatch using `SMART_ROUTER_OBSERVE_MODEL`.
- `route`: apply the selected automatic route/profile.

Use **System → System** to change the live mode. UI changes are persisted to the Operations database. Use **Reset to environment** to remove those persisted overrides.

## Routing policy

- `heuristic`: deterministic built-in policy and safest first choice.
- `calibrated`: uses the calibrated policy artifact.
- `learned`: uses learned routing artifacts with configured fallback.

## HA mode

HA mode can be enabled from the UI only when Redis is configured. This prevents an operator from selecting HA while still using only local process state. Configure `SMART_ROUTER_REDIS_URL`, recreate Smart Router, verify Redis health, then enable HA.

## Operations database upgrades

The default DSN may remain:

```text
sqlite:////data/control-v0.5.2.sqlite3
```

The filename is a compatibility decision. The runtime and schema are independently versioned. v0.5.5 upgrades the `schema_versions` record to `0.5.5` and creates new v0.5.5 tables in the same database.

Before an upgrade:

```bash
cd ~/hermes-linux-stack
mkdir -p backups/manual
cp -a data/smart-router/control-v0.5.2.sqlite3 \
  "backups/manual/control-v0.5.2.sqlite3.$(date +%Y%m%d-%H%M%S).bak"
```

## Users, keys, Groups, and ACLs

Users are Operations Center identities. Virtual API keys are client credentials with independent limits. Groups are reusable collections of usernames for ACL evaluation.

Example:

```text
Group: network-operators
Members: alice, bob

ACL:
subject_type = group
subject_value = network-operators
resource_type = knowledge
resource_id = 1
permission = knowledge.read
effect = allow
```

Deny rules take precedence when matching ACL rules conflict.

## Knowledge

Create a knowledge base, ingest content, and attach the existing knowledge base ID to an agent. v0.5.5 validates agent references, so a nonexistent Knowledge ID returns an actionable `422` error. The built-in retriever remains lexical.

Request metadata example:

```json
{
  "model": "auto",
  "metadata": {
    "hermes": {
      "knowledge_bases": [1],
      "rag_limit": 4
    }
  }
}
```

## Memory

Memory is persistent structured context. Use it for durable facts such as project namespaces, environment conventions, team preferences, or agent-specific context.

Scopes include `user`, `team`, `agent`, `project`, and `organization`. Do not store passwords, API keys, tokens, or other secrets in Memory.

## Agents

An agent combines:

- name and description,
- system prompt,
- tier/profile preference,
- Knowledge bases,
- Skills,
- Plugin/tool registry references,
- active/disabled state.

The v0.5.5 UI supports create, edit, run, disable, and permanent delete. Create/update failures stay visible in the modal.

### Selen example

```text
Name: Selen
Tier: auto
Profile: auto
System prompt:
Your name is Selen.
You are my Telegram infrastructure and network engineering assistant.
You assist with Linux, MikroTik, Docker, networking, automation and Hermes Linux Stack.
```

For the first create test, leave Knowledge empty. Then create or identify the real Knowledge Base and assign it from the selector.

## Skills

Skills are reusable instruction packs that can be attached to agents. Built-in suggestions include Linux Operations, Docker Operations, Network Engineering, MikroTik Engineering, Automation Safety, and Infrastructure Incident Response.

Installed enabled Skill instructions are included in the agent's system context when the agent runs. Skills do not execute software by themselves.

Manual/commercial Skills can include a source/license note. Store only non-secret entitlement/reference information.

## Plugins

Plugins describe MCP/HTTP/webhook tool integrations. Suggested catalog installation copies a registry template and leaves it disabled by default. It does not fetch or execute arbitrary software. Configure trusted endpoints and authentication separately.

Suggested templates include GitHub MCP, read-only PostgreSQL, Kubernetes observer, and MikroTik observer.

## Teams

Teams coordinate multiple agents in sequential or parallel strategies and may synthesize with a chosen tier. Validate agents independently before adding them to a production team.

## Troubleshooting

```bash
docker logs --tail 100 hermes-smart-router
./manage.sh router-status
./manage.sh router-system
```

Common errors:

- `409 agent name already exists`: edit the existing agent or choose another name.
- `422 invalid_agent_knowledge`: select an existing Knowledge Base.
- `422 invalid_agent_skills`: select an installed Skill.
- `422 ha_requires_redis`: configure Redis before enabling HA.
