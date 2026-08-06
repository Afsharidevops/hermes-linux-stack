import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


PLUGIN_PATH = (
    Path(__file__).resolve().parents[1]
    / "plugins"
    / "stack-package-policy"
    / "__init__.py"
)


def load_plugin():
    name = f"stack_package_policy_test_{os.urandom(4).hex()}"
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PackagePolicyTest(unittest.TestCase):
    def setUp(self):
        self.plugin = load_plugin()
        self.session = mock.patch.object(self.plugin, "_current_session_key", return_value="telegram:1")
        self.platform = mock.patch.object(self.plugin, "_session_platform", return_value="telegram")
        self.cron = mock.patch.object(self.plugin, "_cron_context", return_value=False)
        self.bypass = mock.patch.object(self.plugin, "_approval_bypass_active", return_value=False)
        self.manual = mock.patch.object(self.plugin, "_manual_approval_mode", return_value=True)
        self.session.start()
        self.platform.start()
        self.cron.start()
        self.bypass.start()
        self.manual.start()
        self.addCleanup(mock.patch.stopall)

    def parse(self, value):
        return json.loads(value)

    def prepare_python(self, spec="requests==2.32.5"):
        return self.parse(self.plugin._prepare_python({"spec": spec}))

    def prepare_npm(self, spec="is-number@7.0.0"):
        return self.parse(self.plugin._prepare_npm({"spec": spec}))

    def test_python_exact_spec_and_normalized_argv(self):
        result = self.prepare_python()
        self.assertEqual(result["status"], "prepared")
        self.assertEqual(result["package"], "requests")
        self.assertEqual(result["version"], "2.32.5")
        self.assertIn("--only-binary=:all:", result["command"])
        self.assertIn("/opt/data/lazy-packages", result["destination"])
        self.assertNotIn("shell", result)

    def test_npm_exact_spec_and_lifecycle_scripts_disabled(self):
        result = self.prepare_npm("@scope/pkg@1.2.3")
        self.assertEqual(result["package"], "@scope/pkg")
        self.assertEqual(result["version"], "1.2.3")
        self.assertIn("--ignore-scripts", result["command"])
        self.assertIn("/opt/data/npm-packages", result["destination"])

    def test_rejects_unpinned_and_untrusted_specs(self):
        bad_python = [
            "requests", "requests>=2", "requests==latest", "requests[security]==2.0.0",
            "-e .", "./pkg==1", "https://example.com/pkg.whl", "pkg==1;id", "pkg @ git+https://x",
        ]
        bad_npm = [
            "lodash", "lodash@latest", "lodash@^4.0.0", "lodash@1", "file:pkg@1.0.0",
            "https://example.com/pkg.tgz", "pkg@1.0.0 --registry=x", "pkg@1.0.0;id",
        ]
        for value in bad_python:
            with self.subTest(value=value):
                self.assertIn("error", self.parse(self.plugin._prepare_python({"spec": value})))
        for value in bad_npm:
            with self.subTest(value=value):
                self.assertIn("error", self.parse(self.plugin._prepare_npm({"spec": value})))

    def test_each_operation_has_unique_one_time_rule_key(self):
        one = self.prepare_python()
        two = self.prepare_python()
        self.assertNotEqual(one["pending_id"], two["pending_id"])
        directive = self.plugin._pre_tool_call(
            "stack_install_python_package", {"pending_id": one["pending_id"]}
        )
        self.assertEqual(directive["action"], "approve")
        self.assertEqual(
            directive["rule_key"], f"stack-package-install:{one['pending_id']}"
        )
        replay = self.plugin._pre_tool_call(
            "stack_install_python_package", {"pending_id": one["pending_id"]}
        )
        self.assertEqual(replay["action"], "block")

    def test_install_consumes_operation_before_execution(self):
        with tempfile.TemporaryDirectory() as target:
            original_target = self.plugin._PYTHON_TARGET
            self.plugin._PYTHON_TARGET = Path(target)
            try:
                prepared = self.prepare_python()
            finally:
                self.plugin._PYTHON_TARGET = original_target
            pending_id = prepared["pending_id"]
            self.plugin._pre_tool_call("stack_install_python_package", {"pending_id": pending_id})
            completed = types.SimpleNamespace(returncode=0, stdout="ok", stderr="")
            with mock.patch("subprocess.run", return_value=completed) as run:
                result = self.parse(self.plugin._install_python({"pending_id": pending_id}))
        self.assertEqual(result["status"], "installed")
        self.assertFalse(run.call_args.kwargs["shell"])
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        replay = self.parse(self.plugin._install_python({"pending_id": pending_id}))
        self.assertIn("error", replay)

    def test_denial_timeout_or_restart_invalidates_operation(self):
        prepared = self.prepare_python()
        pending_id = prepared["pending_id"]
        directive = self.plugin._pre_tool_call(
            "stack_install_python_package", {"pending_id": pending_id}
        )
        self.plugin._post_approval_response(
            pattern_key=f"plugin_rule:{directive['rule_key']}", choice="deny"
        )
        self.assertIn("error", self.parse(self.plugin._install_python({"pending_id": pending_id})))
        self.assertEqual(load_plugin()._operations, {})

    def test_install_rechecks_manual_approval_mode(self):
        with tempfile.TemporaryDirectory() as target:
            original_target = self.plugin._PYTHON_TARGET
            self.plugin._PYTHON_TARGET = Path(target)
            try:
                prepared = self.prepare_python()
            finally:
                self.plugin._PYTHON_TARGET = original_target
        pending_id = prepared["pending_id"]
        self.plugin._pre_tool_call("stack_install_python_package", {"pending_id": pending_id})
        with mock.patch.object(self.plugin, "_manual_approval_mode", return_value=False):
            result = self.parse(self.plugin._install_python({"pending_id": pending_id}))
        self.assertIn("error", result)

    def test_cron_non_telegram_and_bypass_fail_closed(self):
        with mock.patch.object(self.plugin, "_cron_context", return_value=True):
            self.assertIn("error", self.prepare_python())
        with mock.patch.object(self.plugin, "_session_platform", return_value="api"):
            self.assertIn("error", self.prepare_python())
        with mock.patch.object(self.plugin, "_approval_bypass_active", return_value=True):
            self.assertIn("error", self.prepare_python())
        with mock.patch.object(self.plugin, "_manual_approval_mode", return_value=False):
            self.assertIn("error", self.prepare_python())

    def test_blocks_raw_managers_and_managed_target_writes(self):
        blocked = [
            "pip install x", "python -m pip install x", "uv pip install x", "npm install x",
            "npx tool", "yarn add x", "pnpm add x", "corepack enable", "apt-get install x",
            "sudo apt install x", "hermes skills install https://example.com/SKILL.md",
            "echo ok && npm install x", "(pip install x)",
        ]
        for command in blocked:
            with self.subTest(command=command):
                directive = self.plugin._pre_tool_call("terminal", {"command": command})
                self.assertEqual(directive["action"], "block")
        self.assertEqual(
            self.plugin._pre_tool_call(
                "write_file", {"path": "/opt/data/lazy-packages/evil.py"}
            )["action"],
            "block",
        )
        self.assertIsNone(self.plugin._pre_tool_call("terminal", {"command": "ls -la"}))

    def test_registration_exposes_no_generic_command_argument(self):
        class Context:
            def __init__(self):
                self.tools = []
                self.hooks = []

            def register_tool(self, **kwargs):
                self.tools.append(kwargs)

            def register_hook(self, name, handler):
                self.hooks.append((name, handler))

        context = Context()
        self.plugin.register(context)
        self.assertEqual(len(context.tools), 4)
        self.assertIn("pre_tool_call", [name for name, _ in context.hooks])
        self.assertIn("post_approval_response", [name for name, _ in context.hooks])
        for tool in context.tools:
            properties = tool["schema"]["parameters"]["properties"]
            self.assertNotIn("command", properties)
            self.assertNotIn("destination", properties)


if __name__ == "__main__":
    unittest.main()
