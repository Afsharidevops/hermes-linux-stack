"""Fail-closed Hermes execution policy plugin.

The model can only *prepare* structured operations.  Execution requires an exact,
one-time approval rule and the operation is bound to the current numeric Telegram
user + session.  Docker/SSH authority remains in the isolated brokers.
"""
from __future__ import annotations

import json
import os
import secrets
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

_FEATURES_FILE = Path(os.getenv("EXECUTION_FEATURES_FILE", "/run/secrets/execution-features"))
_FEATURES_FALLBACK = os.getenv("EXECUTION_FEATURES", "")

def _features() -> frozenset[str]:
    try:
        raw = _FEATURES_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        raw = _FEATURES_FALLBACK
    return frozenset(x.strip() for x in raw.split(",") if x.strip())

_CONTROL_SECRET_FILE = Path(os.getenv("EXECUTION_CONTROL_SECRET_FILE", "/run/secrets/execution-control"))
_DOCKER_BROKER = os.getenv("EXECUTION_DOCKER_BROKER_URL", "http://hermes-execution-docker-broker:8750")
_SSH_BROKER = os.getenv("EXECUTION_SSH_BROKER_URL", "http://hermes-execution-ssh-broker:8750")
_USERS_FILE = Path(os.getenv("EXECUTION_USERS_FILE", "/run/secrets/execution-users"))
_runtime_context: Any = None
_pending: dict[str, dict[str, Any]] = {}


def _json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _error(message: str) -> str:
    return _json({"error": message})


def _ctx_value(*names: str, default: Any = None) -> Any:
    ctx = _runtime_context
    if ctx is None:
        return default
    for name in names:
        value = getattr(ctx, name, None)
        if callable(value):
            try:
                return value()
            except TypeError:
                continue
        if value is not None:
            return value
    return default


def _current_session_key() -> str:
    return str(_ctx_value("current_session_key", "session_key", default=os.getenv("HERMES_SESSION_KEY", "")) or "")


def _session_platform() -> str:
    value = _ctx_value("session_platform", "platform")
    if value:
        return str(value)
    key = _current_session_key()
    return key.split(":", 1)[0] if ":" in key else ""


def _session_user_id() -> str:
    value = _ctx_value("session_user_id", "user_id")
    if value is not None:
        return str(value)
    key = _current_session_key()
    return key.rsplit(":", 1)[-1] if ":" in key else ""


def _execution_users() -> frozenset[str]:
    value = _ctx_value("execution_users")
    if value is not None:
        try:
            return frozenset(str(x) for x in value)
        except TypeError:
            return frozenset()
    try:
        return frozenset(x.strip() for x in _USERS_FILE.read_text(encoding="utf-8").replace(",", "\n").splitlines() if x.strip().isdigit())
    except OSError:
        return frozenset()


def _cron_context() -> bool:
    return bool(_ctx_value("cron_context", "is_cron", default=False))


def _approval_bypass_active() -> bool:
    return bool(_ctx_value("approval_bypass_active", "approval_bypass", default=False))


def _manual_approval_mode() -> bool:
    # Fail closed if the host runtime does not explicitly expose manual approval.
    return bool(_ctx_value("manual_approval_mode", "is_manual_approval", default=False))


def _read_secret() -> str:
    try:
        return _CONTROL_SECRET_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _broker_url(feature: str) -> str:
    return _SSH_BROKER if feature == "ssh" else _DOCKER_BROKER


def _broker_call(feature: str, endpoint: str, payload: dict[str, Any], timeout: int = 20) -> dict[str, Any]:
    secret = _read_secret()
    if not secret:
        return {"error": "Execution broker control secret is unavailable."}
    req = urllib.request.Request(
        _broker_url(feature) + endpoint,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", "X-Broker-Secret": secret},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read())
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        return {"error": f"Execution broker is unavailable: {type(exc).__name__}."}


def _context_problem(feature: str) -> str | None:
    if feature not in _features():
        return f"Execution feature '{feature}' is disabled."
    if _session_platform() != "telegram":
        return "Execution is allowed only from an interactive Telegram session."
    if _cron_context() or _approval_bypass_active() or not _manual_approval_mode():
        return "Execution requires the normal interactive manual-approval path."
    user = _session_user_id()
    session = _current_session_key()
    if not user.isdigit() or not session:
        return "Execution requires a numeric Telegram user and session."
    if user not in _execution_users():
        return "This Telegram user is not authorized for execution."
    return None


def _prepare(feature: str, request: dict[str, Any]) -> str:
    if problem := _context_problem(feature):
        return _error(problem)
    user = _session_user_id(); session = _current_session_key()
    result = _broker_call(feature, "/prepare", {"feature": feature, "request": request, "user_id": user, "session": session}, 30)
    if result.get("error"):
        return _json(result)
    capability = str(result.get("capability", "")); digest = str(result.get("digest", ""))
    if not capability or not digest:
        return _error("Broker returned an incomplete prepared operation.")
    pending_id = secrets.token_urlsafe(24)
    _pending[pending_id] = {
        "feature": feature, "capability": capability, "digest": digest,
        "session": session, "user_id": user, "state": "prepared",
    }
    return _json({"status": "prepared", "pending_id": pending_id, "summary": result.get("summary", ""), "digest": digest})


def _execute(feature: str, payload: dict[str, Any]) -> str:
    pending_id = str(payload.get("pending_id", ""))
    item = _pending.get(pending_id)
    if not item or item.get("feature") != feature:
        return _error("Unknown, expired, or mismatched pending execution operation.")
    if item.get("state") != "approved_once":
        if item.get("state") == "cancelled":
            return _error("The execution operation was cancelled.")
        return _error("The execution operation does not have a one-time approval.")
    if _current_session_key() != item["session"] or _session_user_id() != item["user_id"]:
        item["state"] = "cancelled"
        _broker_call(feature, "/cancel", {"capability": item["capability"]}, 10)
        return _error("The approved operation belongs to another session or user.")
    if problem := _context_problem(feature):
        item["state"] = "cancelled"
        _broker_call(feature, "/cancel", {"capability": item["capability"]}, 10)
        return _error(problem)
    # Consume locally *before* the broker call; replay fails even if the broker errors.
    item["state"] = "consumed"
    result = _broker_call(feature, "/execute", {
        "feature": feature, "capability": item["capability"], "digest": item["digest"],
        "user_id": item["user_id"], "session": item["session"],
    }, 330)
    _pending.pop(pending_id, None)
    return _json(result)


def _prepare_local(payload: dict[str, Any]) -> str: return _prepare("local", payload)
def _execute_local(payload: dict[str, Any]) -> str: return _execute("local", payload)
def _prepare_ssh(payload: dict[str, Any]) -> str: return _prepare("ssh", payload)
def _execute_ssh(payload: dict[str, Any]) -> str: return _execute("ssh", payload)
def _prepare_docker(payload: dict[str, Any]) -> str: return _prepare("docker", payload)
def _execute_docker(payload: dict[str, Any]) -> str: return _execute("docker", payload)


def _discover(feature: str, kind: str) -> str:
    if problem := _context_problem(feature): return _error(problem)
    return _json(_broker_call(feature, "/discover", {"kind": kind}, 30))


def _list_ssh_profiles(payload: dict[str, Any] | None = None) -> str: return _discover("ssh", "ssh_profiles")
def _list_docker_containers(payload: dict[str, Any] | None = None) -> str: return _discover("docker", "docker_containers")


def _pre_tool_call(tool_name: str, arguments: dict[str, Any] | None = None):
    arguments = arguments or {}
    mapping = {
        "stack_execute_local_command": "local",
        "stack_execute_ssh_command": "ssh",
        "stack_execute_docker_operation": "docker",
    }
    feature = mapping.get(tool_name)
    if not feature:
        return None
    pending_id = str(arguments.get("pending_id", "")); item = _pending.get(pending_id)
    if not item or item.get("feature") != feature or item.get("state") != "prepared":
        return {"action": "block", "reason": "Execution requires a matching prepared one-time operation."}
    if item["session"] != _current_session_key() or item["user_id"] != _session_user_id():
        return {"action": "block", "reason": "Prepared execution belongs to another session."}
    # Mark approval as requested so the same pending operation cannot create two approval prompts.
    item["state"] = "approval_pending"
    rule_key = f"stack-execution:{feature}:{pending_id}"
    item["rule_key"] = rule_key
    return {"action": "approve", "rule_key": rule_key, "description": "Approve the exact sealed execution operation once."}


def _post_approval_response(pattern_key: str, choice: str, **_: Any):
    key = str(pattern_key).removeprefix("plugin_rule:")
    for pending_id, item in list(_pending.items()):
        if item.get("rule_key") != key or item.get("state") != "approval_pending":
            continue
        if choice == "once":
            item["state"] = "approved_once"
        else:
            item["state"] = "cancelled"
            _broker_call(item["feature"], "/cancel", {"capability": item["capability"]}, 10)
        return


def _tool(name: str, description: str, handler, properties: dict[str, Any], required: list[str]):
    return dict(name=name, description=description, handler=handler, schema={"parameters": {"type": "object", "properties": properties, "required": required, "additionalProperties": False}})


def register(context):
    global _runtime_context
    _runtime_context = context
    definitions = [
        _tool("stack_prepare_local_command", "Prepare a sealed local sandbox command for approval.", _prepare_local, {"command": {"type": "string"}, "workdir": {"type": "string"}, "timeout": {"type": "integer"}, "network": {"type": "string"}, "net_raw": {"type": "boolean"}}, ["command"]),
        _tool("stack_execute_local_command", "Execute a previously prepared and one-time-approved local command.", _execute_local, {"pending_id": {"type": "string"}}, ["pending_id"]),
        _tool("stack_prepare_ssh_command", "Prepare a sealed SSH profile command for approval.", _prepare_ssh, {"profile": {"type": "string"}, "command": {"type": "string"}, "timeout": {"type": "integer"}}, ["profile", "command"]),
        _tool("stack_execute_ssh_command", "Execute a previously prepared and one-time-approved SSH command.", _execute_ssh, {"pending_id": {"type": "string"}}, ["pending_id"]),
        _tool("stack_list_ssh_profiles", "List broker-approved SSH profile metadata.", _list_ssh_profiles, {}, []),
        _tool("stack_prepare_docker_operation", "Prepare a structured Docker operation for approval.", _prepare_docker, {"action": {"type": "string"}, "image": {"type": "string"}, "container": {"type": "string"}}, ["action"]),
        _tool("stack_execute_docker_operation", "Execute a previously prepared and one-time-approved Docker operation.", _execute_docker, {"pending_id": {"type": "string"}}, ["pending_id"]),
        _tool("stack_list_docker_containers", "List broker-visible Docker container metadata.", _list_docker_containers, {}, []),
    ]
    for definition in definitions:
        context.register_tool(**definition)
    context.register_hook("pre_tool_call", _pre_tool_call)
    context.register_hook("post_approval_response", _post_approval_response)
