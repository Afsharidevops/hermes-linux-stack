"""Stack-owned execution tools: local sandbox, pinned SSH, and host Docker.

These sit alongside upstream `terminal` and `code_execution`, which the local
operator has enabled. Those run as the gateway uid inside the Hermes container,
so an approved command there can read /opt/data/.env; their approval is also
pattern-based, and a `session` or `always` choice keeps authorising later
commands the operator never sees.

The tools here are the isolated path, and stay useful precisely because they
are not that: each operation is prepared, sealed, rendered in full, approved
exactly once in Telegram, and executed by a broker that holds the authority.
Hermes never holds the Docker socket or an SSH private key, and a sandbox
command cannot reach stack secrets even when approved.
"""

from __future__ import annotations

import json
import os
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_PENDING_TTL_SECONDS = 300
_BROKER_TIMEOUT_SECONDS = 950
_MAX_SUMMARY_CHARS = 3_500

_DOCKER_BROKER_URL = os.environ.get(
    "EXECUTION_DOCKER_BROKER_URL", "http://execution-docker-broker:8750"
)
_SSH_BROKER_URL = os.environ.get(
    "EXECUTION_SSH_BROKER_URL", "http://execution-ssh-broker:8750"
)
_SECRET_FILE = Path(os.environ.get("EXECUTION_CONTROL_SECRET_FILE",
                                   "/run/secrets/execution-control"))
_ENABLED_FEATURES = tuple(
    item for item in os.environ.get("EXECUTION_FEATURES", "").split(",") if item
)
_EXECUTION_USERS_FILE = Path(os.environ.get(
    "EXECUTION_USERS_FILE", "/run/secrets/execution-users"
))

_FEATURE_BROKER = {
    "local": _DOCKER_BROKER_URL,
    "docker": _DOCKER_BROKER_URL,
    "ssh": _SSH_BROKER_URL,
}


@dataclass
class _Operation:
    operation_id: str
    feature: str
    capability: str
    digest: str
    summary: str
    session_key: str
    user_id: str
    created_at: float
    awaiting_approval: bool = False


_operations: dict[str, _Operation] = {}
_operations_lock = threading.Lock()


def _tool_result(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True)


def _error(message: str) -> str:
    return _tool_result({"error": message})


def _current_session_key() -> str:
    try:
        from tools.approval import get_current_session_key

        return get_current_session_key(default="")
    except Exception:
        return os.environ.get("HERMES_SESSION_KEY", "")


def _session_platform() -> str:
    try:
        from gateway.session_context import get_session_env

        return (get_session_env("HERMES_SESSION_PLATFORM", "") or "").lower()
    except Exception:
        return os.environ.get("HERMES_SESSION_PLATFORM", "").lower()


def _session_user_id() -> str:
    try:
        from gateway.session_context import get_session_env

        return (get_session_env("HERMES_SESSION_USER_ID", "") or "").strip()
    except Exception:
        return os.environ.get("HERMES_SESSION_USER_ID", "").strip()


def _cron_context() -> bool:
    try:
        from gateway.session_context import get_session_env
        from tools.approval import is_truthy_value

        return is_truthy_value(get_session_env("HERMES_CRON_SESSION", ""))
    except Exception:
        return os.environ.get("HERMES_CRON_SESSION", "").lower() in {"1", "true", "yes", "on"}


def _approval_bypass_active(session_key: str) -> bool:
    try:
        from tools.approval import is_approval_bypass_active_for_session

        return bool(is_approval_bypass_active_for_session(session_key))
    except Exception:
        # Execution must fail closed if Hermes's approval API changes.
        return True


def _manual_approval_mode() -> bool:
    try:
        from tools.approval import _get_approval_mode

        return _get_approval_mode() == "manual"
    except Exception:
        # Smart approval is model-mediated, and unknown future modes are unsafe.
        return False


def _context_error(feature: str) -> str | None:
    """Every check that must hold before an operation can even be prepared."""
    if feature not in _ENABLED_FEATURES:
        return (
            f"The '{feature}' execution feature is disabled. A local operator enables it with "
            f"./manage.sh enable-execution {feature}."
        )
    if _cron_context():
        return "Execution is disabled for cron and background sessions."
    if _session_platform() != "telegram":
        return "Execution approval is available only through Telegram."
    session_key = _current_session_key()
    if not session_key:
        return "Execution requires an identified interactive session."
    if _approval_bypass_active(session_key) or not _manual_approval_mode():
        return "Disable YOLO mode and set approvals.mode to manual before preparing an operation."
    user_id = _session_user_id()
    if not user_id.isdigit():
        return "Execution requires a numeric Telegram user identity."
    if user_id not in _execution_users():
        return (
            "This Telegram user is not on the execution operator list. A local operator "
            "grants access with ./manage.sh add-execution-user."
        )
    return None


def _execution_users() -> frozenset[str]:
    try:
        value = _EXECUTION_USERS_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return frozenset()
    users = value.split(",") if value else []
    if any(not item.isdigit() for item in users):
        return frozenset()
    return frozenset(users)


def _control_secret() -> str:
    try:
        return _SECRET_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _broker_call(feature: str, endpoint: str, payload: dict[str, Any],
                 timeout: float) -> dict[str, Any]:
    base = _FEATURE_BROKER.get(feature)
    if not base:
        return {"error": f"Unsupported execution feature: {feature}."}
    secret = _control_secret()
    if not secret:
        return {"error": "The execution control secret is unavailable; execution is not configured."}
    request = urllib.request.Request(
        f"{base}{endpoint}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Broker-Secret": secret},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            return json.loads(exc.read().decode("utf-8"))
        except Exception:
            return {"error": f"The execution broker rejected the request (HTTP {exc.code})."}
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        return {"error": f"The execution broker is unreachable: {type(exc).__name__}."}


def _cleanup_expired_locked(now: float) -> None:
    expired = [
        operation_id
        for operation_id, operation in _operations.items()
        if now - operation.created_at > _PENDING_TTL_SECONDS
    ]
    for operation_id in expired:
        _operations.pop(operation_id, None)


def _prepare(feature: str, request: dict[str, Any]) -> str:
    problem = _context_error(feature)
    if problem:
        return _error(problem)

    session_key = _current_session_key()
    user_id = _session_user_id()
    response = _broker_call(feature, "/prepare", {
        "feature": feature,
        "request": request,
        "user_id": user_id,
        "session": session_key,
    }, timeout=90)
    if "error" in response:
        return _error(response["error"])

    capability = response.get("capability", "")
    summary = response.get("summary", "")
    if not capability or not summary or len(summary) > _MAX_SUMMARY_CHARS:
        return _error("The execution broker returned an unusable preparation.")

    operation_id = f"{feature}-{os.urandom(12).hex()}"
    with _operations_lock:
        _cleanup_expired_locked(time.monotonic())
        _operations[operation_id] = _Operation(
            operation_id=operation_id,
            feature=feature,
            capability=capability,
            digest=response.get("digest", ""),
            summary=summary,
            session_key=session_key,
            user_id=user_id,
            created_at=time.monotonic(),
        )
    return _tool_result({
        "status": "prepared",
        "feature": feature,
        "pending_id": operation_id,
        "digest": response.get("digest", ""),
        "summary": summary,
        "expires_in_seconds": _PENDING_TTL_SECONDS,
        "note": "Nothing has run. Call the matching execute tool to request one-time approval.",
    })


def _execute(feature: str, args: dict[str, Any]) -> str:
    operation_id = args.get("pending_id") if isinstance(args, dict) else None
    if not isinstance(operation_id, str) or not operation_id:
        return _error("A valid prepared pending_id is required.")

    session_key = _current_session_key()
    with _operations_lock:
        _cleanup_expired_locked(time.monotonic())
        operation = _operations.pop(operation_id, None)

    if operation is None:
        return _error("This operation is unknown, expired, already consumed, or was not approved.")
    if operation.feature != feature or operation.session_key != session_key:
        return _error("The pending operation does not match this tool or Telegram session.")
    if not operation.awaiting_approval:
        return _error("The operation did not pass the one-time approval gate.")
    problem = _context_error(feature)
    if problem:
        return _error(f"The operation is blocked because its approval context is no longer safe. {problem}")
    if _session_user_id() != operation.user_id:
        return _error("The operation was approved for a different Telegram user.")

    response = _broker_call(feature, "/execute", {
        "feature": feature,
        "capability": operation.capability,
        "user_id": operation.user_id,
        "session": operation.session_key,
        "digest": operation.digest,
    }, timeout=_BROKER_TIMEOUT_SECONDS)
    if "error" in response:
        return _error(response["error"])
    response["feature"] = feature
    response["digest"] = operation.digest
    return _tool_result(response)


def _cancel(operation: _Operation) -> None:
    _broker_call(operation.feature, "/cancel", {
        "feature": operation.feature, "capability": operation.capability,
    }, timeout=30)


def _prepare_local(args: dict[str, Any], **_: Any) -> str:
    return _prepare("local", {
        "command": args.get("command"),
        "workdir": args.get("workdir", "/workspace"),
        "timeout": args.get("timeout"),
        "network": args.get("network", "none"),
        "net_raw": args.get("net_raw", False),
    })


def _prepare_ssh(args: dict[str, Any], **_: Any) -> str:
    return _prepare("ssh", {
        "profile": args.get("profile"),
        "command": args.get("command"),
        "timeout": args.get("timeout"),
    })


def _prepare_docker(args: dict[str, Any], **_: Any) -> str:
    operation = args.get("operation")
    if not isinstance(operation, dict):
        return _error("A structured docker operation object is required.")
    return _prepare("docker", operation)


def _execute_local(args: dict[str, Any], **_: Any) -> str:
    return _execute("local", args)


def _execute_ssh(args: dict[str, Any], **_: Any) -> str:
    return _execute("ssh", args)


def _execute_docker(args: dict[str, Any], **_: Any) -> str:
    return _execute("docker", args)


def _list_ssh_profiles(_args: dict[str, Any], **_: Any) -> str:
    problem = _context_error("ssh")
    if problem:
        return _error(problem)
    return _tool_result(_broker_call("ssh", "/discover", {"kind": "ssh_profiles"}, timeout=30))


def _list_docker_containers(_args: dict[str, Any], **_: Any) -> str:
    problem = _context_error("docker")
    if problem:
        return _error(problem)
    return _tool_result(
        _broker_call("docker", "/discover", {"kind": "docker_containers"}, timeout=30)
    )


_EXECUTE_TOOLS = {
    "stack_execute_local_command": "local",
    "stack_execute_ssh_command": "ssh",
    "stack_execute_docker_operation": "docker",
}


def _pre_tool_call(tool_name: str, args: dict[str, Any], **_: Any) -> dict[str, str] | None:
    feature = _EXECUTE_TOOLS.get(tool_name)
    if feature is None:
        return None

    operation_id = args.get("pending_id") if isinstance(args, dict) else None
    if not isinstance(operation_id, str) or not operation_id:
        return {"action": "block", "message": "BLOCKED: A valid prepared pending_id is required."}

    problem = _context_error(feature)
    if problem:
        return {"action": "block", "message": f"BLOCKED: {problem}"}

    session_key = _current_session_key()
    user_id = _session_user_id()
    with _operations_lock:
        _cleanup_expired_locked(time.monotonic())
        operation = _operations.get(operation_id)
        if operation is None:
            return {"action": "block",
                    "message": "BLOCKED: Operation is unknown, expired, or already consumed."}
        if operation.awaiting_approval:
            return {"action": "block",
                    "message": "BLOCKED: Operation is already awaiting approval or execution."}
        if (operation.feature != feature or operation.session_key != session_key
                or operation.user_id != user_id):
            _operations.pop(operation_id, None)
            return {"action": "block",
                    "message": "BLOCKED: Operation does not match this tool, user, or session."}
        operation.awaiting_approval = True

    return {
        "action": "approve",
        "message": (
            f"{operation.summary}\n\n"
            "This approval authorises this single sealed operation only. Approving it does "
            "not make its effects reversible."
        ),
        "rule_key": f"stack-execution:{operation.operation_id}",
    }


def _post_approval_response(pattern_key: str = "", choice: str = "", **_: Any) -> None:
    prefix = "plugin_rule:stack-execution:"
    if not pattern_key.startswith(prefix):
        return
    operation_id = pattern_key[len(prefix):]
    if choice == "once":
        return
    # Denial, timeout, and every reusable choice cancel the capability: a
    # "session" or "always" approval would authorise later, unseen operations.
    with _operations_lock:
        operation = _operations.pop(operation_id, None)
    if operation is not None:
        _cancel(operation)


_TIMEOUT_SCHEMA = {
    "type": "integer",
    "minimum": 1,
    "maximum": 900,
    "description": "Seconds before the operation is killed. Defaults to 120.",
}
_PENDING_SCHEMA = {
    "type": "object",
    "properties": {
        "pending_id": {
            "type": "string",
            "description": "Single-use ID returned by the matching prepare tool.",
        },
    },
    "required": ["pending_id"],
    "additionalProperties": False,
}
_EMPTY_SCHEMA = {"type": "object", "properties": {}, "additionalProperties": False}

_LOCAL_PREPARE_SCHEMA = {
    "type": "object",
    "properties": {
        "command": {
            "type": "string",
            "description": "Exact shell command to run in a throwaway non-root sandbox container.",
        },
        "workdir": {
            "type": "string",
            "description": "Absolute path inside /workspace. Defaults to /workspace.",
        },
        "timeout": _TIMEOUT_SCHEMA,
        "network": {
            "type": "string",
            "enum": ["none", "egress"],
            "description": "Outbound network access. Defaults to none.",
        },
        "net_raw": {
            "type": "boolean",
            "description": "Grant NET_RAW for raw sockets (ping, traceroute). Defaults to false.",
        },
    },
    "required": ["command"],
    "additionalProperties": False,
}
_SSH_PREPARE_SCHEMA = {
    "type": "object",
    "properties": {
        "profile": {
            "type": "string",
            "description": "Name of a locally configured SSH profile. Host, user, port, key, and "
                           "host-key pin are fixed by the local operator.",
        },
        "command": {"type": "string", "description": "Exact remote shell command."},
        "timeout": _TIMEOUT_SCHEMA,
    },
    "required": ["profile", "command"],
    "additionalProperties": False,
}
_DOCKER_PREPARE_SCHEMA = {
    "type": "object",
    "properties": {
        "operation": {
            "type": "object",
            "description": (
                "Structured Docker operation. action is one of pull, run, start, stop, restart, "
                "remove, logs, inspect, list. run requires a digest-pinned image "
                "(repository@sha256:...) or a local image ID, and accepts entrypoint, command, "
                "user, workdir, environment, mounts, ports, network, capabilities_add, "
                "capabilities_drop, devices, security_opt, sysctls, privileged, pid_mode, "
                "ipc_mode, uts_mode, userns_mode, read_only_rootfs, detach, auto_remove, "
                "restart_policy, memory_mb, cpus, pids_limit, and timeout. Raw CLI strings and "
                "HostConfig are rejected."
            ),
        },
    },
    "required": ["operation"],
    "additionalProperties": False,
}


def _schema(name: str, description: str, parameters: dict[str, Any]) -> dict[str, Any]:
    return {"name": name, "description": description, "parameters": parameters}


def register(ctx) -> None:
    tools = (
        (
            "stack_prepare_local_command",
            "Seal one sandbox command for approval. Runs nothing.",
            _LOCAL_PREPARE_SCHEMA, _prepare_local, "local",
        ),
        (
            "stack_execute_local_command",
            "Request fresh Telegram approval and run one sealed sandbox command.",
            _PENDING_SCHEMA, _execute_local, "local",
        ),
        (
            "stack_prepare_ssh_command",
            "Seal one remote command for a configured SSH profile. Runs nothing.",
            _SSH_PREPARE_SCHEMA, _prepare_ssh, "ssh",
        ),
        (
            "stack_execute_ssh_command",
            "Request fresh Telegram approval and run one sealed remote SSH command.",
            _PENDING_SCHEMA, _execute_ssh, "ssh",
        ),
        (
            "stack_list_ssh_profiles",
            "List configured SSH profile names and their authority labels.",
            _EMPTY_SCHEMA, _list_ssh_profiles, "ssh",
        ),
        (
            "stack_prepare_docker_operation",
            "Seal one structured Docker operation on the host daemon for approval. Runs nothing.",
            _DOCKER_PREPARE_SCHEMA, _prepare_docker, "docker",
        ),
        (
            "stack_execute_docker_operation",
            "Request fresh Telegram approval and run one sealed Docker operation.",
            _PENDING_SCHEMA, _execute_docker, "docker",
        ),
        (
            "stack_list_docker_containers",
            "List containers on the host Docker daemon.",
            _EMPTY_SCHEMA, _list_docker_containers, "docker",
        ),
    )
    for name, description, parameters, handler, feature in tools:
        if feature not in _ENABLED_FEATURES:
            continue
        ctx.register_tool(
            name=name,
            toolset="stack_execution",
            schema=_schema(name, description, parameters),
            handler=handler,
            description=description,
            emoji="🛠️",
        )
    ctx.register_hook("pre_tool_call", _pre_tool_call)
    ctx.register_hook("post_approval_response", _post_approval_response)
