from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Iterable


GRAPH_SCHEMA_VERSION = 2


@dataclass(frozen=True)
class Port:
    id: str
    data_type: str


@dataclass(frozen=True)
class NodePorts:
    inputs: tuple[Port, ...] = ()
    outputs: tuple[Port, ...] = ()


WORKFLOW_PORTS: dict[str, NodePorts] = {
    "input": NodePorts(outputs=(Port("default", "flow"),)),
    "output": NodePorts(inputs=(Port("default", "flow"), Port("answer", "answer"))),
    "agent": NodePorts(
        inputs=(Port("default", "flow"), Port("context", "knowledge"), Port("tools", "tool")),
        outputs=(Port("default", "flow"), Port("result", "answer")),
    ),
    "team": NodePorts(inputs=(Port("default", "flow"),), outputs=(Port("default", "flow"), Port("result", "answer"))),
    "knowledge": NodePorts(outputs=(Port("context", "knowledge"),)),
    "skill": NodePorts(outputs=(Port("tools", "tool"),)),
    "plugin": NodePorts(outputs=(Port("tools", "tool"),)),
    "approval": NodePorts(
        inputs=(Port("default", "flow"),),
        outputs=(
            Port("default", "flow"),
            Port("approved", "flow"),
            Port("rejected", "flow"),
            Port("timeout", "flow"),
        ),
    ),
    "branch": NodePorts(
        inputs=(Port("default", "flow"),),
        outputs=(Port("default", "flow"), Port("true", "flow"), Port("false", "flow")),
    ),
    "parallel": NodePorts(inputs=(Port("default", "flow"),), outputs=(Port("default", "flow"),)),
}


KNOWLEDGE_PORTS: dict[str, NodePorts] = {
    "data_source": NodePorts(outputs=(Port("default", "raw"),)),
    "extract": NodePorts(inputs=(Port("default", "raw"),), outputs=(Port("default", "text"),)),
    "transform": NodePorts(inputs=(Port("default", "text"),), outputs=(Port("default", "text"),)),
    # v0.5.8 accepted direct source -> chunk graphs, so raw remains accepted here.
    "chunk": NodePorts(inputs=(Port("default", "text_or_raw"),), outputs=(Port("default", "chunks"),)),
    "embed": NodePorts(inputs=(Port("default", "chunks_or_text"),), outputs=(Port("default", "embeddings"),)),
    "index": NodePorts(inputs=(Port("default", "embeddings"),), outputs=(Port("default", "index"),)),
    # v0.5.8 accepted chunk -> knowledge_base; retain that migration path.
    "knowledge_base": NodePorts(inputs=(Port("default", "knowledge_sink"),), outputs=(Port("default", "knowledge"),)),
    "qa": NodePorts(inputs=(Port("default", "knowledge"),), outputs=(Port("default", "answer"),)),
    "output": NodePorts(inputs=(Port("default", "answer_or_knowledge"),)),
}


_COMPATIBILITY: dict[str, set[str]] = {
    "flow": {"flow"},
    "answer": {"answer", "flow"},
    "knowledge": {"knowledge", "answer_or_knowledge"},
    "tool": {"tool"},
    "raw": {"raw", "text_or_raw", "chunks_or_text", "knowledge_sink"},
    "text": {"text", "text_or_raw", "chunks_or_text", "knowledge_sink"},
    "chunks": {"chunks_or_text", "knowledge_sink"},
    "embeddings": {"embeddings", "knowledge_sink"},
    "index": {"index", "knowledge_sink"},
    "answer": {"answer", "flow", "answer_or_knowledge"},
}


def ports_for(studio: str, node_type: str) -> NodePorts:
    table = WORKFLOW_PORTS if studio == "workflow" else KNOWLEDGE_PORTS if studio == "knowledge" else None
    if table is None:
        raise ValueError(f"unsupported graph studio: {studio}")
    try:
        return table[node_type]
    except KeyError as exc:
        raise ValueError(f"unsupported {studio} node type: {node_type}") from exc


def port_definitions(studio: str, node_type: str) -> dict[str, list[dict[str, str]]]:
    p = ports_for(studio, node_type)
    return {
        "inputs": [{"id": x.id, "type": x.data_type} for x in p.inputs],
        "outputs": [{"id": x.id, "type": x.data_type} for x in p.outputs],
    }


def _compatible(source_type: str, target_type: str) -> bool:
    return target_type in _COMPATIBILITY.get(source_type, {source_type})


def _find_port(ports: Iterable[Port], port_id: str) -> Port | None:
    return next((p for p in ports if p.id == port_id), None)


def _resolve_ports(studio: str, source_type: str, target_type: str, source_port: str | None, target_port: str | None) -> tuple[Port, Port]:
    source = ports_for(studio, source_type)
    target = ports_for(studio, target_type)
    if not source.outputs:
        raise ValueError(f"{source_type} has no output port")
    if not target.inputs:
        raise ValueError(f"{target_type} has no input port")

    if source_port:
        sp = _find_port(source.outputs, source_port)
        if sp is None:
            raise ValueError(f"unknown output port {source_port!r} on {source_type}")
        source_candidates = (sp,)
    else:
        source_candidates = source.outputs

    if target_port:
        tp = _find_port(target.inputs, target_port)
        if tp is None:
            raise ValueError(f"unknown input port {target_port!r} on {target_type}")
        target_candidates = (tp,)
    else:
        target_candidates = target.inputs

    # Prefer default/default for migrated v0.5.8 edges when compatible.
    ordered_sources = sorted(source_candidates, key=lambda p: p.id != "default")
    ordered_targets = sorted(target_candidates, key=lambda p: p.id != "default")
    for sp in ordered_sources:
        for tp in ordered_targets:
            if _compatible(sp.data_type, tp.data_type):
                return sp, tp
    raise ValueError(f"{source_type} output cannot connect to {target_type} input")


def _edge_id(source_node: str, source_port: str, target_node: str, target_port: str) -> str:
    raw = f"{source_node}\0{source_port}\0{target_node}\0{target_port}".encode()
    return "edge-" + hashlib.sha1(raw).hexdigest()[:16]


def _has_cycle(nodes: set[str], edges: list[tuple[str, str]]) -> bool:
    adjacency: dict[str, list[str]] = {node: [] for node in nodes}
    for source, target in edges:
        adjacency[source].append(target)
    state: dict[str, int] = {node: 0 for node in nodes}

    def visit(node: str) -> bool:
        if state[node] == 1:
            return True
        if state[node] == 2:
            return False
        state[node] = 1
        for nxt in adjacency[node]:
            if visit(nxt):
                return True
        state[node] = 2
        return False

    return any(visit(node) for node in nodes if state[node] == 0)


def normalize_graph(
    value: Any,
    *,
    studio: str,
    max_nodes: int,
    max_edges: int,
    numeric_ref_id: bool = False,
) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{studio} graph must be an object")
    nodes = value.get("nodes", [])
    edges = value.get("edges", [])
    if not isinstance(nodes, list) or not isinstance(edges, list):
        raise ValueError(f"{studio} nodes and edges must be lists")
    if len(nodes) > max_nodes or len(edges) > max_edges:
        raise ValueError(f"{studio} graph is too large")

    clean_nodes: list[dict[str, Any]] = []
    node_map: dict[str, dict[str, Any]] = {}
    for raw in nodes:
        if not isinstance(raw, dict):
            raise ValueError(f"{studio} node must be an object")
        node_id = str(raw.get("id", "")).strip()[:80]
        node_type = str(raw.get("type", "")).strip()
        if not node_id or node_id in node_map:
            raise ValueError(f"{studio} node IDs must be unique")
        ports_for(studio, node_type)  # validates type
        ref_id = raw.get("ref_id")
        if numeric_ref_id and ref_id is not None:
            try:
                ref_id = int(ref_id)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{studio} ref_id must be numeric when provided") from exc
        config = raw.get("config") if isinstance(raw.get("config"), dict) else {}
        clean = {
            "id": node_id,
            "type": node_type,
            "label": str(raw.get("label", node_id))[:160],
            "ref_id": ref_id,
            "config": config,
            "ports": port_definitions(studio, node_type),
        }
        clean_nodes.append(clean)
        node_map[node_id] = clean

    clean_edges: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str, str]] = set()
    topology: list[tuple[str, str]] = []
    for raw in edges:
        if not isinstance(raw, dict):
            raise ValueError(f"{studio} edge must be an object")
        source_node = str(raw.get("source_node", raw.get("from", ""))).strip()
        target_node = str(raw.get("target_node", raw.get("to", ""))).strip()
        if source_node not in node_map or target_node not in node_map:
            raise ValueError(f"{studio} edge references an unknown node")
        if source_node == target_node:
            raise ValueError(f"{studio} self-connections are not supported")
        source_port_value = str(raw.get("source_port", "")).strip() or None
        target_port_value = str(raw.get("target_port", "")).strip() or None
        sp, tp = _resolve_ports(
            studio,
            node_map[source_node]["type"],
            node_map[target_node]["type"],
            source_port_value,
            target_port_value,
        )
        key = (source_node, sp.id, target_node, tp.id)
        if key in seen:
            raise ValueError(f"{studio} duplicate connection is not supported")
        seen.add(key)
        topology.append((source_node, target_node))
        condition = str(raw.get("condition", ""))[:500]
        label_value = raw.get("label")
        label = str(label_value)[:160] if label_value is not None else (condition[:160] or None)
        metadata = raw.get("metadata") if isinstance(raw.get("metadata"), dict) else {}
        clean_edges.append(
            {
                "id": str(raw.get("id", "")).strip()[:120] or _edge_id(source_node, sp.id, target_node, tp.id),
                "source_node": source_node,
                "source_port": sp.id,
                "target_node": target_node,
                "target_port": tp.id,
                # Legacy aliases remain during the v0.5.8 -> v0.5.9 migration window.
                "from": source_node,
                "to": target_node,
                "condition": condition,
                "label": label,
                "metadata": metadata,
            }
        )

    if _has_cycle(set(node_map), topology):
        raise ValueError(f"{studio} graph contains an unsupported cycle")

    return {"nodes": clean_nodes, "edges": clean_edges, "version": GRAPH_SCHEMA_VERSION}
