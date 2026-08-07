import importlib.util
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "plugins" / "stack-execution-policy" / "__init__.py"


def load_plugin(features="local,ssh,docker"):
    name = f"stack_execution_policy_test_{os.urandom(4).hex()}"
    with mock.patch.dict(os.environ, {"EXECUTION_FEATURES": features}):
        spec = importlib.util.spec_from_file_location(name, PLUGIN)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    return module


class ExecutionPolicyTest(unittest.TestCase):
    def setUp(self):
        self.plugin = load_plugin()
        patches = (
            mock.patch.object(self.plugin, "_current_session_key", return_value="telegram:123"),
            mock.patch.object(self.plugin, "_session_platform", return_value="telegram"),
            mock.patch.object(self.plugin, "_session_user_id", return_value="123"),
            mock.patch.object(self.plugin, "_execution_users", return_value=frozenset({"123"})),
            mock.patch.object(self.plugin, "_cron_context", return_value=False),
            mock.patch.object(self.plugin, "_approval_bypass_active", return_value=False),
            mock.patch.object(self.plugin, "_manual_approval_mode", return_value=True),
        )
        for patch in patches:
            patch.start()
        self.addCleanup(mock.patch.stopall)

    def broker(self, feature, endpoint, payload, timeout):
        if endpoint == "/prepare":
            return {"capability": "opaque", "digest": "d" * 64, "summary": "exact summary"}
        if endpoint == "/execute":
            return {"status": "executed", "returncode": 0, "output": "ok"}
        return {"status": "cancelled"}

    def parse(self, value):
        return json.loads(value)

    def test_prepare_once_execute_replay(self):
        with mock.patch.object(self.plugin, "_broker_call", side_effect=self.broker) as broker:
            prepared = self.parse(self.plugin._prepare_local({"command": "id"}))
            directive = self.plugin._pre_tool_call(
                "stack_execute_local_command", {"pending_id": prepared["pending_id"]}
            )
            self.assertEqual(directive["action"], "approve")
            self.plugin._post_approval_response(
                pattern_key=f"plugin_rule:{directive['rule_key']}", choice="once"
            )
            result = self.parse(self.plugin._execute_local({"pending_id": prepared["pending_id"]}))
            self.assertEqual(result["status"], "executed")
            execute = next(call for call in broker.call_args_list if call.args[1] == "/execute")
            self.assertEqual(execute.args[2]["digest"], "d" * 64)
            self.assertEqual(execute.args[2]["session"], "telegram:123")
            self.assertIn("error", self.parse(
                self.plugin._execute_local({"pending_id": prepared["pending_id"]})
            ))

    def test_reusable_approval_cancels(self):
        with mock.patch.object(self.plugin, "_broker_call", side_effect=self.broker) as broker:
            prepared = self.parse(self.plugin._prepare_local({"command": "id"}))
            directive = self.plugin._pre_tool_call(
                "stack_execute_local_command", {"pending_id": prepared["pending_id"]}
            )
            self.plugin._post_approval_response(
                pattern_key=f"plugin_rule:{directive['rule_key']}", choice="session"
            )
            self.assertIn("error", self.parse(
                self.plugin._execute_local({"pending_id": prepared["pending_id"]})
            ))
            self.assertTrue(any(call.args[1] == "/cancel" for call in broker.call_args_list))

    def test_context_fails_closed(self):
        cases = [
            ("_session_platform", "api"), ("_cron_context", True),
            ("_approval_bypass_active", True), ("_manual_approval_mode", False),
            ("_session_user_id", "not-numeric"), ("_execution_users", frozenset()),
        ]
        for name, value in cases:
            with self.subTest(name=name):
                with mock.patch.object(self.plugin, name, return_value=value):
                    self.assertIn("error", self.parse(self.plugin._prepare_local({"command": "id"})))

    def test_cross_feature_and_session_blocked(self):
        with mock.patch.object(self.plugin, "_broker_call", side_effect=self.broker):
            prepared = self.parse(self.plugin._prepare_local({"command": "id"}))
            result = self.plugin._pre_tool_call(
                "stack_execute_ssh_command", {"pending_id": prepared["pending_id"]}
            )
            self.assertEqual(result["action"], "block")

    def test_enabled_registration(self):
        class Context:
            def __init__(self): self.tools, self.hooks = [], []
            def register_tool(self, **kwargs): self.tools.append(kwargs)
            def register_hook(self, name, handler): self.hooks.append(name)
        context = Context()
        self.plugin.register(context)
        names = {tool["name"] for tool in context.tools}
        self.assertEqual(len(names), 8)
        self.assertIn("pre_tool_call", context.hooks)
        self.assertIn("post_approval_response", context.hooks)


if __name__ == "__main__":
    unittest.main()
