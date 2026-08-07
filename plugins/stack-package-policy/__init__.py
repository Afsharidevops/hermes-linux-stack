"""Hermes package broker for persistent, unprivileged Python/npm installs."""

from __future__ import annotations

import json
import os
import re
import secrets
import shlex
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_PLUGIN_DIR = Path(__file__).resolve().parent
# npm 10.11+ refuses to load one path as both "user" and "global" config, so the
# two neutralising files must be distinct. They ship read-only with the plugin.
_NPM_USER_CONFIG = _PLUGIN_DIR / "npm-user.npmrc"
_NPM_GLOBAL_CONFIG = _PLUGIN_DIR / "npm-global.npmrc"

_PYTHON_TARGET = Path(os.environ.get("HERMES_LAZY_INSTALL_TARGET", "/opt/data/lazy-packages"))
_NPM_PREFIX = Path(os.environ.get("NPM_CONFIG_PREFIX", "/opt/data/npm-packages"))
_PYTHON_REGISTRY = "https://pypi.org/simple"
_NPM_REGISTRY = "https://registry.npmjs.org/"
_PENDING_TTL_SECONDS = 300
_INSTALL_TIMEOUT_SECONDS = 300
_MAX_OUTPUT_CHARS = 12_000

_PYTHON_SPEC_RE = re.compile(
    r"^(?P<name>[A-Za-z0-9][A-Za-z0-9._-]{0,127})=="
    r"(?P<version>(?:[0-9]+!)?[0-9]+(?:\.[0-9]+)*"
    r"(?:[A-Za-z]+[0-9.]*)?(?:\.post[0-9]+)?(?:\.dev[0-9]+)?"
    r"(?:\+[A-Za-z0-9.-]+)?)$"
)
_NPM_SPEC_RE = re.compile(
    r"^(?P<name>(?:@[a-z0-9][a-z0-9._-]{0,127}/)?"
    r"[a-z0-9][a-z0-9._-]{0,127})@"
    r"(?P<version>v?[0-9]+\.[0-9]+\.[0-9]+"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)$"
)
_FORBIDDEN_TEXT_RE = re.compile(r"[\n\r\t;&|`$<>\\]|://|(?:^|\s)-(?:e|r|f|-)")

# Interpreter-injection variables must not reach an installer subprocess.
_STRIPPED_ENV = frozenset({
    "NODE_OPTIONS",
    "NODE_PATH",
    "NPM_TOKEN",
    "PYTHONPATH",
    "PYTHONHOME",
    "PYTHONSTARTUP",
})

_PACKAGE_COMMAND_RE = re.compile(
    r"(?ix)"
    r"(?:^|[\s;&|`()])(?:"
    r"(?:/[^\s;&|()]+/)?(?:pip|pip3|pipx|npm|npx|yarn|pnpm|corepack|uv)"
    r"|(?:/[^\s;&|()]+/)?(?:apt|apt-get|apk|dnf|yum|zypper|pacman|sudo|su)"
    r"|(?:/[^\s;&|()]+/)?python(?:3(?:\.\d+)?)?\s+-m\s+(?:pip|ensurepip)"
    r"|hermes\s+skills\s+install"
    r")(?:$|[\s;&|()])"
)
_MANAGED_TARGET_RE = re.compile(
    r"(?x)(?:/opt/data/(?:lazy-packages|npm-packages))(?:/|\b)"
)
_CODE_INSTALL_RE = re.compile(
    r"(?ix)(?:subprocess\.|os\.system|os\.popen|exec\s*\().{0,240}"
    r"(?:pip|npm|npx|yarn|pnpm|corepack|uv\s+pip|apt|apk|dnf|yum)"
)


@dataclass
class _Operation:
    operation_id: str
    ecosystem: str
    package: str
    version: str
    spec: str
    registry: str
    destination: str
    argv: tuple[str, ...]
    session_key: str
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


def _cron_context() -> bool:
    try:
        from gateway.session_context import get_session_env
        from tools.approval import is_truthy_value

        return is_truthy_value(get_session_env("HERMES_CRON_SESSION", ""))
    except Exception:
        return os.environ.get("HERMES_CRON_SESSION", "").lower() in {
            "1", "true", "yes", "on",
        }


def _approval_bypass_active(session_key: str) -> bool:
    try:
        from tools.approval import is_approval_bypass_active_for_session

        return bool(is_approval_bypass_active_for_session(session_key))
    except Exception:
        # Package installation must fail closed if Hermes's approval API changes.
        return True


def _manual_approval_mode() -> bool:
    try:
        from tools.approval import _get_approval_mode

        return _get_approval_mode() == "manual"
    except Exception:
        # Smart approval is model-mediated, and unknown future modes are unsafe.
        return False


def _cleanup_expired_locked(now: float) -> None:
    expired = [
        operation_id
        for operation_id, operation in _operations.items()
        if now - operation.created_at > _PENDING_TTL_SECONDS
    ]
    for operation_id in expired:
        _operations.pop(operation_id, None)


def _normalized_command(argv: tuple[str, ...]) -> str:
    return shlex.join(argv)


def _prepare_operation(
    *, ecosystem: str, package: str, version: str, spec: str,
    registry: str, destination: Path, argv: tuple[str, ...],
) -> str:
    session_key = _current_session_key()
    if not session_key:
        return _error("Package preparation requires an interactive Hermes session.")
    if _cron_context():
        return _error("Package installation is disabled for cron and background sessions.")
    if _session_platform() != "telegram":
        return _error("Package installation approval is available only through Telegram.")
    if _approval_bypass_active(session_key) or not _manual_approval_mode():
        return _error(
            "Package installation requires approvals.mode=manual with YOLO disabled. "
            "Set manual approval mode and prepare a new operation."
        )

    operation_id = secrets.token_urlsafe(24)
    operation = _Operation(
        operation_id=operation_id,
        ecosystem=ecosystem,
        package=package,
        version=version,
        spec=spec,
        registry=registry,
        destination=str(destination),
        argv=argv,
        session_key=session_key,
        created_at=time.monotonic(),
    )
    with _operations_lock:
        _cleanup_expired_locked(operation.created_at)
        _operations[operation_id] = operation

    return _tool_result({
        "status": "prepared",
        "pending_id": operation_id,
        "ecosystem": ecosystem,
        "package": package,
        "version": version,
        "registry": registry,
        "destination": str(destination),
        "command": _normalized_command(argv),
        "next_tool": f"stack_install_{ecosystem}_package",
        "notice": "A fresh Telegram approval is required. This pending ID is single-use.",
    })


def _prepare_python(args: dict[str, Any], **_: Any) -> str:
    spec = args.get("spec")
    if not isinstance(spec, str) or _FORBIDDEN_TEXT_RE.search(spec):
        return _error("Use one exact PyPI spec in the form package==version.")
    match = _PYTHON_SPEC_RE.fullmatch(spec)
    if match is None or "*" in spec:
        return _error("Use one exact PyPI spec in the form package==version; ranges, URLs, paths, extras, and flags are not allowed.")

    argv = (
        "/usr/local/bin/uv", "pip", "install",
        "--no-config", "--default-index", _PYTHON_REGISTRY,
        "--target", str(_PYTHON_TARGET), "--only-binary=:all:", spec,
    )
    return _prepare_operation(
        ecosystem="python",
        package=match.group("name"),
        version=match.group("version"),
        spec=spec,
        registry=_PYTHON_REGISTRY,
        destination=_PYTHON_TARGET,
        argv=argv,
    )


def _prepare_npm(args: dict[str, Any], **_: Any) -> str:
    spec = args.get("spec")
    if not isinstance(spec, str) or _FORBIDDEN_TEXT_RE.search(spec):
        return _error("Use one exact npm registry spec in the form package@version.")
    match = _NPM_SPEC_RE.fullmatch(spec)
    if match is None:
        return _error("Use one exact npm registry spec in the form package@version; tags, ranges, aliases, URLs, paths, and flags are not allowed.")

    argv = (
        "/usr/local/bin/npm", "install", "--global",
        "--prefix", str(_NPM_PREFIX), "--registry", _NPM_REGISTRY,
        "--ignore-scripts", "--no-audit", "--no-fund", spec,
    )
    return _prepare_operation(
        ecosystem="npm",
        package=match.group("name"),
        version=match.group("version"),
        spec=spec,
        registry=_NPM_REGISTRY,
        destination=_NPM_PREFIX,
        argv=argv,
    )


def _install(args: dict[str, Any], *, ecosystem: str) -> str:
    operation_id = args.get("pending_id")
    if not isinstance(operation_id, str) or not operation_id:
        return _error("A valid prepared pending_id is required.")

    session_key = _current_session_key()
    with _operations_lock:
        _cleanup_expired_locked(time.monotonic())
        operation = _operations.pop(operation_id, None)

    if operation is None:
        return _error("This package operation is unknown, expired, already consumed, or was not approved.")
    if operation.ecosystem != ecosystem or operation.session_key != session_key:
        return _error("The pending package operation does not match this tool or Telegram session.")
    if not operation.awaiting_approval:
        return _error("The package operation did not pass the one-time approval gate.")
    if (
        _cron_context()
        or _session_platform() != "telegram"
        or _approval_bypass_active(session_key)
        or not _manual_approval_mode()
    ):
        return _error("The package operation is blocked because its approval context is no longer safe.")

    Path(operation.destination).mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key in list(env):
        upper = key.upper()
        if upper.startswith(("PIP_", "UV_", "NPM_CONFIG_")) or upper in _STRIPPED_ENV:
            env.pop(key, None)
    env.update({
        "PIP_CONFIG_FILE": os.devnull,
        "UV_NO_CONFIG": "1",
        "NPM_CONFIG_USERCONFIG": str(_NPM_USER_CONFIG),
        "NPM_CONFIG_GLOBALCONFIG": str(_NPM_GLOBAL_CONFIG),
        "NPM_CONFIG_IGNORE_SCRIPTS": "true",
        "NPM_CONFIG_AUDIT": "false",
        "NPM_CONFIG_FUND": "false",
    })

    try:
        completed = subprocess.run(
            list(operation.argv),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=_INSTALL_TIMEOUT_SECONDS,
            env=env,
            shell=False,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return _error(f"Package installation failed: {type(exc).__name__}.")

    stdout = (completed.stdout or "")[-_MAX_OUTPUT_CHARS:]
    stderr = (completed.stderr or "")[-_MAX_OUTPUT_CHARS:]
    return _tool_result({
        "status": "installed" if completed.returncode == 0 else "failed",
        "ecosystem": operation.ecosystem,
        "package": operation.package,
        "version": operation.version,
        "destination": operation.destination,
        "command": _normalized_command(operation.argv),
        "returncode": completed.returncode,
        "stdout": stdout,
        "stderr": stderr,
    })


def _install_python(args: dict[str, Any], **_: Any) -> str:
    return _install(args, ecosystem="python")


def _install_npm(args: dict[str, Any], **_: Any) -> str:
    return _install(args, ecosystem="npm")


def _all_string_values(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return "\n".join(_all_string_values(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return "\n".join(_all_string_values(item) for item in value)
    return ""


def _raw_install_block(tool_name: str, args: dict[str, Any]) -> str | None:
    if tool_name == "terminal":
        text = str(args.get("command") or "")
    elif tool_name in {"execute_code", "python", "computer"}:
        text = _all_string_values(args)
    elif tool_name in {"write_file", "patch"}:
        text = str(args.get("path") or args.get("file_path") or "")
    else:
        return None

    if _MANAGED_TARGET_RE.search(text):
        return "BLOCKED: Direct writes to managed package targets are forbidden. Use the stack package broker."
    if _PACKAGE_COMMAND_RE.search(text) or _CODE_INSTALL_RE.search(text):
        return "BLOCKED: Raw package-manager and OS/global installation commands are forbidden. Use the stack package broker."
    return None


def _pre_tool_call(tool_name: str, args: dict[str, Any], **_: Any) -> dict[str, str] | None:
    raw_block = _raw_install_block(tool_name, args)
    if raw_block:
        return {"action": "block", "message": raw_block}

    expected_ecosystem = {
        "stack_install_python_package": "python",
        "stack_install_npm_package": "npm",
    }.get(tool_name)
    if expected_ecosystem is None:
        return None

    operation_id = args.get("pending_id") if isinstance(args, dict) else None
    if not isinstance(operation_id, str) or not operation_id:
        return {"action": "block", "message": "BLOCKED: A valid prepared pending_id is required."}

    session_key = _current_session_key()
    if _cron_context():
        return {"action": "block", "message": "BLOCKED: Package installation is disabled for cron and background sessions."}
    if _session_platform() != "telegram":
        return {"action": "block", "message": "BLOCKED: Package installation approval is available only through Telegram."}
    if _approval_bypass_active(session_key) or not _manual_approval_mode():
        return {
            "action": "block",
            "message": "BLOCKED: Disable YOLO mode and set approvals.mode to manual before preparing a new package operation.",
        }

    with _operations_lock:
        _cleanup_expired_locked(time.monotonic())
        operation = _operations.get(operation_id)
        if operation is None:
            return {"action": "block", "message": "BLOCKED: Package operation is unknown, expired, or already consumed."}
        if operation.awaiting_approval:
            return {"action": "block", "message": "BLOCKED: Package operation is already awaiting approval or execution."}
        if operation.ecosystem != expected_ecosystem or operation.session_key != session_key:
            _operations.pop(operation_id, None)
            return {"action": "block", "message": "BLOCKED: Package operation does not match this tool or Telegram session."}
        operation.awaiting_approval = True

    reason = (
        "Install one reviewed user-space package.\n"
        f"Source: {operation.registry}\n"
        f"Package: {operation.package}\n"
        f"Version: {operation.version}\n"
        f"Destination: {operation.destination}\n"
        f"Command: {_normalized_command(operation.argv)}\n"
        "This approval applies only to this single sealed operation."
    )
    return {
        "action": "approve",
        "message": reason,
        "rule_key": f"stack-package-install:{operation.operation_id}",
    }


def _post_approval_response(
    pattern_key: str = "", choice: str = "", **_: Any,
) -> None:
    prefix = "plugin_rule:stack-package-install:"
    if not pattern_key.startswith(prefix):
        return
    if choice in {"once", "session", "always"}:
        return
    operation_id = pattern_key[len(prefix):]
    with _operations_lock:
        _operations.pop(operation_id, None)


_PREPARE_SCHEMA = {
    "type": "object",
    "properties": {
        "spec": {
            "type": "string",
            "description": "One exact registry package spec with a pinned version.",
        },
    },
    "required": ["spec"],
    "additionalProperties": False,
}
_INSTALL_SCHEMA = {
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


def _schema(name: str, description: str, parameters: dict[str, Any]) -> dict[str, Any]:
    return {"name": name, "description": description, "parameters": parameters}


def register(ctx) -> None:
    tools = (
        (
            "stack_prepare_python_package",
            "Validate and seal one exact package==version PyPI wheel installation. Does not install anything.",
            _PREPARE_SCHEMA,
            _prepare_python,
        ),
        (
            "stack_install_python_package",
            "Request fresh Telegram approval and execute one sealed Python package installation.",
            _INSTALL_SCHEMA,
            _install_python,
        ),
        (
            "stack_prepare_npm_package",
            "Validate and seal one exact package@version npm registry installation. Does not install anything.",
            _PREPARE_SCHEMA,
            _prepare_npm,
        ),
        (
            "stack_install_npm_package",
            "Request fresh Telegram approval and execute one sealed npm package installation with lifecycle scripts disabled.",
            _INSTALL_SCHEMA,
            _install_npm,
        ),
    )
    for name, description, parameters, handler in tools:
        ctx.register_tool(
            name=name,
            toolset="stack_packages",
            schema=_schema(name, description, parameters),
            handler=handler,
            description=description,
            emoji="📦",
        )
    ctx.register_hook("pre_tool_call", _pre_tool_call)
    ctx.register_hook("post_approval_response", _post_approval_response)
