"""Remote execution against locally configured, host-key-pinned profiles."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import time
from pathlib import Path
from typing import Any

from .schema import MAX_OUTPUT_CHARS

PROFILE_ROOT = Path("/profiles")
_HOST_RE = re.compile(r"^[A-Za-z0-9._:-]{1,253}$")
_USER_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
_FINGERPRINT_RE = re.compile(r"^SHA256:[A-Za-z0-9+/]{20,}={0,2}$")

FIXED_OPTIONS = (
    "BatchMode=yes",
    "IdentitiesOnly=yes",
    "StrictHostKeyChecking=yes",
    "PasswordAuthentication=no",
    "KbdInteractiveAuthentication=no",
    "PubkeyAuthentication=yes",
    "ForwardAgent=no",
    "ForwardX11=no",
    "ForwardX11Trusted=no",
    "PermitLocalCommand=no",
    "ClearAllForwardings=yes",
    "ControlMaster=no",
    "ControlPath=none",
    "RequestTTY=no",
    "GSSAPIAuthentication=no",
    "AddKeysToAgent=no",
    "LogLevel=ERROR",
)


class ProfileError(ValueError):
    """A profile that is missing, unsafe, or incompletely configured."""


def _file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _identity_fingerprint(path: Path) -> str:
    try:
        completed = subprocess.run(
            ["ssh-keygen", "-y", "-f", str(path)], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
            text=True, encoding="utf-8", timeout=10,
        )
        public = subprocess.run(
            ["ssh-keygen", "-lf", "-", "-E", "sha256"], input=completed.stdout,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
            text=True, encoding="utf-8", timeout=10,
        )
        return public.stdout.split()[1]
    except (OSError, subprocess.SubprocessError, IndexError) as exc:
        raise ProfileError("The SSH identity key is invalid or unreadable.") from exc


def load_profile(name: str, root: Path = PROFILE_ROOT) -> dict[str, Any]:
    directory = root / name
    if directory.is_symlink() or not directory.is_dir():
        raise ProfileError(f"SSH profile '{name}' is not configured.")
    meta_path = directory / "profile.json"
    identity = directory / "identity"
    known_hosts = directory / "known_hosts"
    for path in (meta_path, identity, known_hosts):
        if path.is_symlink() or not path.is_file():
            raise ProfileError(f"SSH profile '{name}' is incomplete or unsafe.")
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ProfileError(f"SSH profile '{name}' metadata is invalid.") from exc
    if not isinstance(meta, dict) or set(meta) != {
        "host", "port", "user", "authority", "fingerprint"
    }:
        raise ProfileError(f"SSH profile '{name}' has unsupported or missing metadata.")
    if not isinstance(meta["host"], str) or not _HOST_RE.fullmatch(meta["host"]):
        raise ProfileError(f"SSH profile '{name}' has an invalid host.")
    if (isinstance(meta["port"], bool) or not isinstance(meta["port"], int)
            or not 1 <= meta["port"] <= 65535):
        raise ProfileError(f"SSH profile '{name}' has an invalid port.")
    if not isinstance(meta["user"], str) or not _USER_RE.fullmatch(meta["user"]):
        raise ProfileError(f"SSH profile '{name}' has an invalid user.")
    if meta["authority"] not in ("user", "root", "sudo-nopasswd"):
        raise ProfileError(f"SSH profile '{name}' has an invalid authority label.")
    if (not isinstance(meta["fingerprint"], str)
            or not _FINGERPRINT_RE.fullmatch(meta["fingerprint"])):
        raise ProfileError(f"SSH profile '{name}' has an invalid pinned host fingerprint.")

    meta["identity"] = str(identity)
    meta["known_hosts"] = str(known_hosts)
    meta["identity_fingerprint"] = _identity_fingerprint(identity)
    meta["known_hosts_sha256"] = _file_sha256(known_hosts)
    meta["identity_sha256"] = _file_sha256(identity)
    return meta


def seal_profile(profile: dict[str, Any]) -> dict[str, Any]:
    return {
        "host": profile["host"],
        "port": profile["port"],
        "user": profile["user"],
        "authority": profile["authority"],
        "fingerprint": profile["fingerprint"],
        "identity_fingerprint": profile["identity_fingerprint"],
        "known_hosts_sha256": profile["known_hosts_sha256"],
        "identity_sha256": profile["identity_sha256"],
    }


def profile_matches(profile: dict[str, Any], sealed: dict[str, Any]) -> bool:
    return seal_profile(profile) == sealed


def list_profiles(root: Path = PROFILE_ROOT) -> list[dict[str, Any]]:
    if not root.is_dir():
        return []
    profiles = []
    for entry in sorted(root.iterdir()):
        if entry.is_symlink() or not entry.is_dir():
            continue
        try:
            meta = load_profile(entry.name, root)
        except ProfileError:
            continue
        profiles.append({
            "name": entry.name,
            "host": meta["host"],
            "port": meta["port"],
            "user": meta["user"],
            "authority": meta["authority"],
            "host_fingerprint": meta["fingerprint"],
            "identity_fingerprint": meta["identity_fingerprint"],
        })
    return profiles


def build_argv(profile: dict[str, Any], command: str) -> list[str]:
    argv = ["ssh", "-n", "-T"]
    for option in FIXED_OPTIONS:
        argv += ["-o", option]
    argv += ["-o", f"UserKnownHostsFile={profile['known_hosts']}"]
    argv += ["-i", profile["identity"]]
    argv += ["-p", str(profile["port"])]
    argv += [f"{profile['user']}@{profile['host']}"]
    argv += ["--", command]
    return argv


def run_ssh(request: dict[str, Any], profile: dict[str, Any]) -> dict[str, Any]:
    argv = build_argv(profile, request["command"])
    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
            timeout=request["timeout"], shell=False, check=False,
        )
        returncode = completed.returncode
        output = completed.stdout or ""
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        returncode = 124
        output = (exc.output or "") if isinstance(exc.output, str) else ""
    except OSError as exc:
        returncode = -1
        output = f"SSH failed to start: {type(exc).__name__}"

    return {
        "returncode": returncode,
        "output": output[-MAX_OUTPUT_CHARS:],
        "truncated": len(output) > MAX_OUTPUT_CHARS,
        "timed_out": timed_out,
        "duration": round(time.monotonic() - started, 3),
    }
