# Hermes Linux Stack v0.5.5

## Operations Center runtime controls, agent lifecycle, skills, groups, and built-in docs

v0.5.5 is an operator-control and usability release built on v0.5.4. It preserves the existing Smart Router data directory and the default `control-v0.5.2.sqlite3` compatibility filename while upgrading the Operations Center schema in place to `0.5.5`.

### Smart Router / Operations Center

- Live UI editing for `router_mode`: `observe` or `route`.
- Live UI editing for `router_policy`: `heuristic`, `calibrated`, or `learned`.
- UI control for HA mode with a guard that requires Redis before HA can be enabled.
- Runtime UI settings persist in the Operations database and override startup environment values until **Reset to environment** is used.
- System page now reports the schema version and explains why the default DB filename can remain `control-v0.5.2.sqlite3`.
- OIDC login button corrected to the actual `/api/auth/oidc/start` route.
- ACL UI corrected to use backend subject type `virtual_key`; `group` subjects are now exposed.

### Agents

- Create Agent errors are shown instead of failing silently.
- Agent names and referenced Knowledge/Plugin/Skill IDs are validated.
- Agents can be edited in the UI.
- Agents can be disabled reversibly or permanently deleted.
- Agent forms use existing Knowledge, Skill, and Plugin records instead of requiring blind CSV IDs.

### Skills and plugins

- New reusable Skill registry with curated suggestions for Linux, Docker, networking, MikroTik, automation safety, and incident response.
- Skills can be installed from the built-in catalog or registered manually, including commercial/license metadata without storing license secrets.
- Skills assigned to an agent are injected into that agent's system context during runs.
- Suggested Plugin catalog can install safe registry templates for GitHub MCP, read-only PostgreSQL, Kubernetes observation, and MikroTik observation.
- Plugin catalog installation does not download or execute arbitrary code and installs suggested entries disabled by default.

### Access groups

- New Access → Groups menu.
- Groups contain Operations Center usernames.
- ACL rules with `subject_type=group` now resolve real group membership.

### Help and documentation

- New built-in **Docs** menu covers routing, system controls, users/keys/groups/ACLs, Knowledge, Memory, Agents, Skills, Plugins, Teams, upgrades, backups, and troubleshooting examples.
- Memory page now explains scope behavior and warns against using memory as a secret store.

### Database compatibility

The default filename remains:

```text
sqlite:////data/control-v0.5.2.sqlite3
```

This is intentional. v0.5.5 creates its new tables in the same database and updates the `schema_versions` marker to `0.5.5`, preserving v0.5.1/v0.5.2-era users, routes, keys, policies, budgets, knowledge, memory, agents, teams, plugins, ACLs, audit, and outcome records.

New v0.5.5 tables include:

```text
v55_runtime_settings
v55_access_groups
v55_skills
v55_agent_skills
```

Back up the persistent Smart Router database before any production upgrade.
