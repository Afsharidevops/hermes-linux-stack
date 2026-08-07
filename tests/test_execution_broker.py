import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "execution-broker" / "src"))
from broker import approval, schema, ssh
from broker.approver import ApprovalRequestStore, ApproverError, validate_submission
from broker.sandbox import build_sandbox_body
from broker.store import CapabilityError, CapabilityStore


class BrokerPolicyTest(unittest.TestCase):
    def test_local_defaults_and_bounds(self):
        request = schema.validate_local({"command": "id"})
        self.assertEqual(request["network"], "none")
        self.assertFalse(request["net_raw"])
        with self.assertRaises(schema.RequestError):
            schema.validate_local({"command": "id", "unknown": True})
        with self.assertRaises(schema.RequestError):
            schema.validate_local({"command": "id", "workdir": "/etc"})

    def test_docker_requires_pinned_image_and_complete_warning(self):
        with self.assertRaises(schema.RequestError):
            schema.validate_docker({"action": "run", "image": "alpine:latest"})
        request = schema.validate_docker({
            "action": "run", "image": "sha256:" + "a" * 64,
            "privileged": True,
            "mounts": [{"type": "bind", "source": "/tmp", "target": "/host", "read_only": False}],
            "pid_mode": "host",
        })
        rendered = approval.render_summary("docker", request)
        self.assertIn("PRIVILEGED", rendered)
        self.assertIn("Host PID namespace", rendered)
        self.assertIn("bind-mounted READ-WRITE", rendered)
        self.assertIn("cap_drop:", rendered)

    def test_floor_blocks_authority_paths_networks_and_protected_containers(self):
        image = "sha256:" + "b" * 64
        for source in ("/", "/run", "/run/secrets", "/run/secrets/child",
                       "/var/run", "/var/run/docker.sock"):
            with self.subTest(source=source):
                request = schema.validate_docker({
                    "action": "run", "image": image,
                    "mounts": [{"type": "bind", "source": source,
                                "target": "/host", "read_only": True}],
                })
                with self.assertRaises(approval.DeniedError):
                    approval.check_floor("docker", request)
        with self.assertRaises(approval.DeniedError):
            approval.check_floor("docker", schema.validate_docker({
                "action": "run", "image": image,
                "network": "hermes-execution-control",
            }))
        approval.set_protected_network_ids({"network-id"})
        with self.assertRaises(approval.DeniedError):
            request = schema.validate_docker({"action": "run", "image": image})
            request["resolved_network_id"] = "network-id"
            approval.check_floor("docker", request)
        with self.assertRaises(approval.DeniedError):
            approval.check_floor("docker", {"action": "remove", "container": "hermes-agent"})
        approval.set_protected_container_ids({"f" * 64})
        for action in ("inspect", "logs", "remove"):
            with self.subTest(action=action), self.assertRaises(approval.DeniedError):
                approval.check_floor("docker", {
                    "action": action, "container": "f" * 12,
                    "resolved_name": "renamed-service",
                })

    def test_secret_ref_is_rejected(self):
        with self.assertRaises(schema.RequestError):
            schema.validate_docker({
                "action": "run", "image": "sha256:" + "c" * 64,
                "environment": [{"name": "TOKEN", "secret_ref": "anything"}],
            })

    def test_approver_revalidates_exact_operation_and_resolves_once(self):
        request = schema.validate_local({"command": "id"})
        request.update(resolved_image_id="sha256:" + "d" * 64,
                       workspace_generation="7")
        payload = {
            "target": "docker", "feature": "local", "capability": "n" * 43,
            "digest": approval.canonical_digest("local", request), "request": request,
            "summary": approval.render_summary("local", request), "user_id": "123",
            "session": "telegram:123", "generation": "7",
        }
        self.assertIs(validate_submission(payload, generation="7"), payload)
        for field, value in (("summary", "changed"), ("digest", "0" * 64),
                             ("generation", "8")):
            changed = dict(payload)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(ApproverError):
                validate_submission(changed, generation="7")
        with tempfile.TemporaryDirectory() as directory:
            store = ApprovalRequestStore(Path(directory) / "approvals.sqlite3")
            token = store.create(payload, ttl_seconds=300)
            with self.assertRaises(ApproverError):
                store.resolve(token, "approved", "123")
            store.mark_delivered(payload["capability"])
            with self.assertRaises(ApproverError):
                store.resolve(token, "approved", "999")
            grant = store.resolve(token, "approved", "123")
            self.assertEqual(grant["digest"], payload["digest"])
            with self.assertRaises(ApproverError):
                store.resolve(token, "approved", "123")
            self.assertEqual(store.unresolved_decisions()[0]["decision"], "approved")
            store.mark_granted(payload["capability"], "approved")
            self.assertEqual(store.unresolved_decisions(), [])

    def test_capability_atomic_consumption_and_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            store = CapabilityStore(Path(directory) / "state.sqlite3")
            nonce = store.issue(feature="local", digest="d", request="{}", user_id="1", session="s", generation="1")
            with self.assertRaises(CapabilityError):
                store.consume(nonce=nonce, feature="local", digest="d", user_id="1", session="s", generation="1")
            store.approve(nonce=nonce, feature="local", digest="d", user_id="1", session="s", generation="1")
            with self.assertRaises(CapabilityError):
                store.consume(nonce=nonce, feature="local", digest="bad", user_id="1", session="s", generation="1")
            result = store.consume(nonce=nonce, feature="local", digest="d", user_id="1", session="s", generation="1")
            self.assertEqual(result["digest"], "d")
            with self.assertRaises(CapabilityError):
                store.consume(nonce=nonce, feature="local", digest="d", user_id="1", session="s", generation="1")
            revoked = store.issue(feature="local", digest="e", request="{}", user_id="1", session="s", generation="1")
            store.cancel_generation("2")
            with self.assertRaises(CapabilityError):
                store.consume(nonce=revoked, feature="local", digest="e", user_id="1", session="s", generation="2")

    def test_capability_waits_for_independent_approval(self):
        with tempfile.TemporaryDirectory() as directory:
            store = CapabilityStore(Path(directory) / "state.sqlite3")
            nonce = store.issue(feature="local", digest="d", request="{}", user_id="1",
                                session="s", generation="1")

            def approve_later():
                time.sleep(0.05)
                store.approve(nonce=nonce, feature="local", digest="d", user_id="1",
                              session="s", generation="1")

            thread = threading.Thread(target=approve_later)
            thread.start()
            result = store.consume(nonce=nonce, feature="local", digest="d", user_id="1",
                                   session="s", generation="1", wait_seconds=1)
            thread.join()
            self.assertEqual(result["digest"], "d")
            with self.assertRaises(CapabilityError):
                store.consume(nonce=nonce, feature="local", digest="d", user_id="1",
                              session="s", generation="1", wait_seconds=0.01)

    def test_capability_wait_stops_on_denial(self):
        with tempfile.TemporaryDirectory() as directory:
            store = CapabilityStore(Path(directory) / "state.sqlite3")
            nonce = store.issue(feature="local", digest="d", request="{}", user_id="1",
                                session="s", generation="1")

            def deny_later():
                time.sleep(0.05)
                store.cancel_bound(nonce=nonce, feature="local", digest="d", user_id="1",
                                   session="s", generation="1")

            thread = threading.Thread(target=deny_later)
            thread.start()
            started = time.monotonic()
            with self.assertRaises(CapabilityError):
                store.consume(nonce=nonce, feature="local", digest="d", user_id="1",
                              session="s", generation="1", wait_seconds=1)
            thread.join()
            self.assertLess(time.monotonic() - started, 0.75)

    def test_sandbox_has_no_stack_network_or_host_authority(self):
        request = schema.validate_local({"command": "id"})
        body = build_sandbox_body(request, image="sha256:x", workspace_source="/workspace", egress_network="egress")
        host = body["HostConfig"]
        self.assertEqual(body["User"], "10002:10002")
        self.assertEqual(host["NetworkMode"], "none")
        self.assertEqual(host["CapDrop"], ["ALL"])
        self.assertTrue(host["ReadonlyRootfs"])
        self.assertEqual(host["Binds"], ["/workspace:/workspace:rw"])

    def test_ssh_options_are_pinned(self):
        options = " ".join(ssh.FIXED_OPTIONS)
        for expected in ("StrictHostKeyChecking=yes", "ForwardAgent=no", "ForwardX11=no", "ControlMaster=no", "RequestTTY=no"):
            self.assertIn(expected, options)


if __name__ == "__main__":
    unittest.main()
