# Hermes Linux Stack — Plan v0.5.9

**Planned release:** `0.5.9`
**Primary focus:** n8n-style drag-to-connect visual graph editing
**Target studios:** Workflow Studio, Agent Studio, Router Pipeline Studio, Knowledge Pipeline Studio
**Status:** Released — 2026-08-13; automated validation complete; remaining manual browser light/dark and mouse/trackpad gate explicitly waived by release owner

---

# 1. Goal

Hermes Linux Stack v0.5.9 should make the visual builders behave more like modern node-based workflow tools such as n8n.

The main UX change is:

> Users can connect blocks by dragging from an output connector on one block and dropping onto an input connector on another block.

This interaction should be consistent across all Hermes visual studios.

The intended result is a faster, more intuitive graph-building experience while preserving Hermes validation rules, persistence behavior, routing semantics, approval flow, and execution security boundaries.

---

# 2. Studios included

## Workflow Studio

Users should be able to connect blocks such as:

```text
Input
Agent
Team
Knowledge
Skill
Plugin
Approval
Condition
Branch
Parallel
Output
```

Example:

```text
Input
  ↓
Knowledge
  ↓
Agent
  ↓
Approval
  ↓
Output
```

Branching should support named outputs:

```text
                       ┌─────────────┐
                  YES ─▶ Strong Model│
                 /
┌───────────┐   /
│ Condition │──●
└───────────┘   \
                 \
                  NO ──▶ Fast Model
```

---

## Agent Studio

Support visual composition such as:

```text
Input
  ↓
Knowledge
  ↓
Agent
  ↓
Tools
  ↓
Answer
```

Typical valid relationships:

```text
Knowledge → Agent context
Skill → Agent tools
Plugin → Agent tools
Agent → Answer
```

Invalid direction or incompatible connections should be rejected.

---

## Router Pipeline Studio

Support drag-to-connect for routing stages such as:

```text
Classification
Condition
Capability Filter
Health Filter
Cost Scoring
Latency Scoring
Load Balancing
Route
Retry
Fallback
Approval
Output
```

Named outputs should be supported.

Example:

```text
                     healthy ───────▶ Route
                    /
Health Filter ─────●
                    \
                     unhealthy ─────▶ Fallback
```

Classifier example:

```text
Classifier
   ├── coding ──────▶ Coding Route
   ├── vision ──────▶ Vision Route
   └── default ─────▶ Standard Route
```

---

## Knowledge Pipeline Studio

Support managed ingestion graphs such as:

```text
Source
   ↓
Extract
   ↓
Transform
   ↓
Chunk
   ↓
Embedding
   ↓
Index
   ↓
Knowledge Base
```

The editor should enforce valid connection types.

Example invalid connection:

```text
Embedding → Source
```

The UI should reject invalid graph structure instead of silently saving it.

---

# 3. Core drag-to-connect interaction

The expected interaction should be:

```text
hover node
   ↓
connector handles appear
   ↓
drag from output handle
   ↓
live edge preview follows pointer
   ↓
compatible inputs highlight
   ↓
drop on valid input
   ↓
connection is created
```

Example:

```text
┌──────────────┐                ┌──────────────┐
│  Knowledge   │                │    Agent     │
│              │                │              │
│         ●────┼──── drag ─────▶●              │
└──────────────┘                └──────────────┘
       output                         input
```

---

# 4. Connector handles

Each node should expose input/output handles.

Handles should:

- appear clearly on hover;
- remain visible while a connection is being dragged;
- have a generous click/drag target;
- show hover/focus state;
- support labels where useful;
- expose compatibility information;
- support multiple named outputs when needed.

Example conceptual handle definition:

```json
{
  "inputs": [
    {
      "id": "context",
      "label": "Context",
      "type": "knowledge"
    }
  ],
  "outputs": [
    {
      "id": "result",
      "label": "Result",
      "type": "agent-output"
    }
  ]
}
```

---

# 5. Live connection preview

While dragging:

- render a smooth temporary curved line;
- keep the source handle visually active;
- highlight valid destinations;
- dim or reject invalid destinations;
- snap to a compatible target handle;
- cancel cleanly with `Esc`;
- remove the temporary edge if dropped on an invalid target.

---

# 6. Valid-target highlighting

Compatible targets should be visually obvious.

Suggested states:

```text
normal
valid target
invalid target
hovered target
selected connection
```

Invalid targets should not accept the connection.

If a connection is rejected, show a short reason, for example:

```text
This output cannot connect to that input.

This connection would create an unsupported cycle.

Knowledge Source must appear before Extract.

The target input already has a connection.
```

Avoid silent failures.

---

# 7. Edge selection and deletion

Users should be able to select a connection by clicking the line.

Selected edges should show stronger visual emphasis.

Delete behavior should support:

```text
click edge
press Delete / Backspace
```

Optionally:

```text
right click
→ Delete connection
```

Removing an edge must mark the graph as modified.

---

# 8. Reconnecting existing edges

Users should be able to drag an existing edge endpoint to another valid port.

Expected behavior:

```text
select edge endpoint
   ↓
drag endpoint
   ↓
hover compatible handle
   ↓
release
   ↓
validate
   ↓
update edge
```

Validation must run again before accepting the new destination.

---

# 9. Multi-output nodes

v0.5.9 should support nodes with multiple output handles.

Examples:

```text
Condition
  ├── true
  └── false

Health Filter
  ├── healthy
  └── unhealthy

Approval
  ├── approved
  ├── rejected
  └── timeout

Classifier
  ├── coding
  ├── vision
  └── default
```

The exact source output port must be persisted with the edge.

---

# 10. Connection validation

Every proposed edge should be validated before it changes the graph.

Validation should include:

## Direction

Reject:

```text
input → input
output → output
```

## Type compatibility

Allow only compatible source/target types.

Example:

```text
knowledge-output → agent-context-input
```

may be valid.

But:

```text
embedding-output → workflow-input
```

may not be.

## Duplicate edges

Prevent accidental duplicate connections unless explicitly supported.

## Self-connections

Normally reject:

```text
Node A → Node A
```

unless a specific node explicitly supports it.

## Cycles

Cycle rules should be studio-specific.

Examples:

```text
Knowledge Pipeline:
  arbitrary cycles should be invalid

Workflow Studio:
  loops should preferably use an explicit loop construct

Router Pipeline:
  retry/fallback behavior may require carefully modeled exceptions
```

---

# 11. n8n-style quick add

A key convenience should be:

```text
drag from empty output
        ↓
drop on empty canvas
        ↓
"Add next node" menu opens
        ↓
choose node type
        ↓
new node is created
        ↓
new node is automatically connected
```

This should be context-aware.

Workflow Studio examples:

```text
Agent
Knowledge
Approval
Condition
Parallel
Output
```

Router Pipeline Studio examples:

```text
Condition
Health Filter
Cost Scoring
Route
Retry
Fallback
```

Knowledge Pipeline Studio examples:

```text
Extract
Transform
Chunk
Embedding
Index
Knowledge Base
```

This is one of the highest-value productivity improvements in the release.

---

# 12. Shared graph component

The connection behavior should not be implemented separately four times.

Create one shared graph/connection layer used by:

```text
Workflow Studio
Agent Studio
Router Pipeline Studio
Knowledge Pipeline Studio
```

Later it can also support:

```text
Teams
other visual builders
future orchestration surfaces
```

The shared layer should provide:

- node rendering;
- input/output handles;
- named ports;
- edge rendering;
- drag-to-connect;
- live edge preview;
- reconnect edge;
- delete edge;
- edge labels;
- edge validation hooks;
- node compatibility hooks;
- graph serialization;
- graph deserialization;
- pan;
- zoom;
- fit-to-view;
- selection;
- keyboard behavior;
- pointer/touch support;
- dirty-state integration.

Each studio should supply its own:

```text
node types
port definitions
connection rules
validation rules
domain labels
icons
business semantics
```

---

# 13. Edge data model

Edges should persist exact endpoints.

Suggested model:

```json
{
  "id": "edge-123",
  "source_node": "agent-1",
  "source_port": "result",
  "target_node": "output-1",
  "target_port": "input",
  "label": null,
  "metadata": {}
}
```

For branching:

```json
{
  "source_node": "condition-1",
  "source_port": "true",
  "target_node": "agent-strong",
  "target_port": "input"
}
```

This allows routing and workflow semantics to remain explicit.

---

# 14. Backward compatibility

Existing v0.5.8 graphs must continue loading.

If old graph edges do not include explicit port IDs, v0.5.9 should normalize them to default handles.

Example:

```text
old:
source = node-A
target = node-B

normalized:
source = node-A
source_port = default
target = node-B
target_port = default
```

Do not require users to rebuild existing workflows manually.

---

# 15. Persistence and save state

Graph save operations should persist:

```text
nodes
node positions
edges
source ports
target ports
edge labels
node configuration
graph metadata
```

Any of these actions should mark the graph dirty:

```text
add node
move node
delete node
create edge
delete edge
reconnect edge
edit node configuration
change branch/port metadata
```

The UI should clearly show:

```text
Saved
Unsaved changes
Saving...
Save failed
```

Do not show a successful saved state if the backend write failed.

---

# 16. Undo and redo

Preferred v0.5.9 behavior:

```text
Ctrl/Cmd + Z
Ctrl/Cmd + Shift + Z
```

At minimum, history should support:

- create edge;
- delete edge;
- reconnect edge;
- move node;
- create node;
- delete node.

If full undo/redo is deferred, the internal graph actions should still be designed so history support can be added later without rewriting the editor.

---

# 17. Canvas behavior

The visual canvas should support:

```text
pan
zoom
fit-to-view
drag nodes
select nodes
select edges
live connection preview
snap-to-port
```

Important interaction rules:

- dragging a node must not accidentally start an edge;
- dragging an edge must not accidentally pan the canvas;
- connector hit targets should remain usable at common zoom levels.

---

# 18. Pointer and accessibility behavior

Prefer Pointer Events so the same interaction can support:

```text
mouse
trackpad
pen
touch
```

Mouse/desktop remains the primary v0.5.9 target.

Keyboard accessibility should include:

- visible focus states;
- connector handles focusable where practical;
- edge selection;
- Delete/Backspace for selected edge;
- `Esc` to cancel a connection;
- accessible labels for handles and node types.

---

# 19. Security boundary

Dragging a line changes graph structure only.

It must not itself:

- grant Docker execution;
- grant SSH execution;
- bypass approval;
- grant execution-user rights;
- expose secrets;
- mount Docker socket;
- expose SSH credentials;
- expose approval tokens;
- provide Smart Router with Execution Admin authority.

Approval, Docker, SSH, and other privileged actions must continue through the existing Hermes security architecture.

Core rule:

> Visual graph convenience must not collapse Hermes execution trust boundaries.

---

# 20. Approval nodes

An Approval connection defines workflow structure, not authorization itself.

Example:

```text
Agent
  ↓
Approval
  ↓ approved
Docker Action
```

The actual privileged operation must still require the configured Hermes approval and broker checks.

A visual edge must never substitute for a signed/validated approval.

---

# 21. Error handling

The graph editor should distinguish:

```text
invalid connection
save failure
API failure
schema validation failure
permission failure
runtime validation failure
```

Errors should be short and actionable.

Examples:

```text
Cannot connect these node types.

This edge would create an unsupported cycle.

Workflow saved locally but server update failed.

The selected node requires an Approval stage before execution.
```

---

# 22. Visual design

The connection system should work in both light and dark modes.

Important styling:

- visible handles;
- strong enough edge contrast;
- clear selected edge state;
- subtle connection animation;
- valid target highlight;
- invalid target indication;
- readable labels;
- no dark-only components in light mode.

The graph should look modern and clean without becoming visually noisy.

---

# 23. Suggested implementation phases

## Phase 1 — shared edge engine

Implement:

```text
handles
drag-to-connect
edge preview
edge creation
edge selection
edge deletion
basic validation
serialization
```

## Phase 2 — studio integration

Integrate with:

```text
Workflow Studio
Agent Studio
Router Pipeline Studio
Knowledge Pipeline Studio
```

## Phase 3 — advanced routing/branch ports

Implement:

```text
true/false
healthy/unhealthy
approved/rejected/timeout
classifier outputs
retry/fallback paths
```

## Phase 4 — productivity UX

Add:

```text
drop-on-empty quick add
reconnect edge
keyboard shortcuts
undo/redo
fit-to-view
better validation messages
```

## Phase 5 — regression and persistence

Validate:

```text
old graph loading
new edge persistence
restart persistence
branch compatibility
light mode
dark mode
API validation
security boundaries
```

---

# 24. Suggested tests

## Shared graph tests

Test:

- output handle starts connection;
- valid input completes connection;
- invalid target rejects connection;
- duplicate edge policy;
- self-edge rejection;
- cycle rejection;
- edge deletion;
- edge reconnection;
- named port persistence;
- default port migration;
- save/reload persistence.

## Workflow Studio tests

Test:

```text
Input → Agent
Knowledge → Agent
Agent → Approval
Approval.approved → Output
Condition.true / Condition.false
Parallel paths
```

## Agent Studio tests

Test:

```text
Input → Knowledge
Knowledge → Agent
Skill → Agent
Plugin → Agent
Agent → Answer
```

## Router Pipeline Studio tests

Test:

```text
Classifier outputs
Health healthy/unhealthy
Retry
Fallback
Approval
Route
```

## Knowledge Pipeline Studio tests

Test:

```text
Source → Extract
Extract → Transform
Transform → Chunk
Chunk → Embedding
Embedding → Index
Index → Knowledge Base
```

Reject invalid reversed connections.

---

# 25. Acceptance criteria

v0.5.9 is ready when all of the following are true:

Automated implementation checks are marked complete below. The release owner explicitly requested early finalization and waived the remaining light/dark rendering and real mouse/trackpad interaction checks. Those checks remain unperformed/waived rather than passed.

- [x] Users can drag from an output handle to an input handle.
- [x] A live connection preview is shown.
- [x] Valid targets are highlighted.
- [x] Invalid targets are rejected with a reason.
- [x] Connections can be selected and deleted.
- [x] Existing edges can be reconnected.
- [x] Named branch outputs work.
- [x] Workflow Studio uses the shared connection component.
- [x] Agent Studio uses the shared connection component.
- [x] Router Pipeline Studio uses the shared connection component.
- [x] Knowledge Pipeline Studio uses the shared connection component.
- [x] Drop-on-empty can open an Add Next Node menu.
- [x] New nodes created from quick-add are automatically connected.
- [x] Edges persist after save/reload.
- [x] Existing v0.5.8 graphs remain compatible.
- [x] Knowledge Pipeline invalid directions are blocked.
- [x] Router branch semantics persist correctly.
- [ ] Light mode is visually correct.
- [ ] Dark mode is visually correct.
- [ ] Mouse/trackpad interaction is reliable.
- [x] Execution security boundaries remain unchanged.
- [x] Graph connections alone cannot grant privileged execution.

---

# 26. Recommended release positioning

Suggested v0.5.9 release theme:

> **Hermes Linux Stack v0.5.9 — Visual Flow Connections**

Possible release summary:

> v0.5.9 upgrades Hermes visual studios with interactive drag-to-connect graph editing. Workflow, Agent, Router Pipeline, and Knowledge Pipeline builders gain connector handles, live edge previews, named branch outputs, connection validation, edge editing, and n8n-style quick node creation while preserving Hermes execution and approval security boundaries.

---

# 27. Future extensions after v0.5.9

The same shared graph layer can later support:

```text
Team orchestration
MCP workflow composition
advanced loops
sub-workflows
reusable graph components
copy/paste
multi-selection
auto-layout
execution-state animation
live node status
edge telemetry
runtime traces overlaid on graph
collaboration
graph templates
```

These should not block the core v0.5.9 drag-to-connect release.

---

# 28. Priority order

Recommended implementation order:

1. Shared graph connection engine.
2. Input/output connector handles.
3. Live drag preview.
4. Valid-target highlighting.
5. Edge creation/deletion.
6. Connection validation.
7. Named output ports.
8. Workflow Studio integration.
9. Agent Studio integration.
10. Router Pipeline Studio integration.
11. Knowledge Pipeline Studio integration.
12. Reconnect existing edges.
13. Drop-on-empty Add Next Node.
14. Persistence/backward compatibility.
15. Keyboard and pointer polish.
16. Light/dark visual polish.
17. Security regression tests.
18. Full v0.5.9 acceptance testing.

---

# 29. Non-negotiable design rule

The visual editing experience may become as convenient as n8n, but the security model must remain Hermes-specific.

> Dragging and connecting blocks defines orchestration. It does not grant authority.

Privileged execution must continue to be enforced independently by Hermes execution policy, approval, and broker boundaries.
