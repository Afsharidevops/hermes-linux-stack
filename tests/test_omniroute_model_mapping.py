from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    "SMART_ROUTER_OBSERVE_MODEL": "auto/best-chat",
    "SMART_ROUTER_FAST_MODEL": "auto/best-fast",
    "SMART_ROUTER_STANDARD_MODEL": "auto/best-chat",
    "SMART_ROUTER_STRONG_MODEL": "auto/best-reasoning",
    "SMART_ROUTER_CODING_MODEL": "auto/best-coding",
    "SMART_ROUTER_VISION_MODEL": "auto/best-vision",
}


class OmniRouteModelMappingTest(unittest.TestCase):
    def test_env_example_uses_omniroute_virtual_models(self):
        text = (ROOT / ".env.example").read_text(encoding="utf-8")
        for key, value in EXPECTED.items():
            self.assertIn(f"{key}={value}", text)

    def test_compose_defaults_use_omniroute_virtual_models(self):
        text = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        for key, value in EXPECTED.items():
            self.assertIn(f"${{{key}:-{value}}}", text)

    def test_installer_defaults_use_omniroute_virtual_models(self):
        text = (ROOT / "install.sh").read_text(encoding="utf-8")
        expected_values = {
            "smart_router_observe_model": "auto/best-chat",
            "smart_router_fast_model": "auto/best-fast",
            "smart_router_standard_model": "auto/best-chat",
            "smart_router_strong_model": "auto/best-reasoning",
            "smart_router_coding_model": "auto/best-coding",
            "smart_router_vision_model": "auto/best-vision",
        }
        for variable, value in expected_values.items():
            self.assertIn(
                f'{variable}="${{{variable}:-{value}}}"',
                text,
            )

    def test_n8n_smart_router_path_keeps_hermes_auto_trigger(self):
        text = (ROOT / "manage.sh").read_text(encoding="utf-8")
        self.assertIn(
            'router_base_url="http://smart-router:8080/v1"\n'
            '    router_model="auto"',
            text,
        )

    def test_direct_n8n_omniroute_path_uses_advertised_chat_route(self):
        text = (ROOT / "manage.sh").read_text(encoding="utf-8")
        self.assertIn(
            'router_base_url="http://omniroute:20129/v1"\n'
            '    router_model="auto/best-chat"',
            text,
        )

    def test_client_key_hotfix_remains_before_hermes_use(self):
        text = (ROOT / "install.sh").read_text(encoding="utf-8")
        assignment = text.find(
            'client_key="$(existing_env_value SMART_ROUTER_CLIENT_API_KEY)"'
        )
        use = text.find('provider_key="$client_key"')
        persistence = text.find(
            'replace_env_value "$tmp_env" SMART_ROUTER_CLIENT_API_KEY "$client_key"'
        )
        self.assertGreaterEqual(assignment, 0)
        self.assertGreater(use, assignment)
        self.assertGreater(persistence, assignment)

    def test_n8n_provisioning_hotfix_remains_present(self):
        text = (ROOT / "manage.sh").read_text(encoding="utf-8")
        self.assertIn("create_omniroute_n8n_router_key", text)
        self.assertIn(
            "HERMES_N8N_SERVICE_KEY_NAME=n8n (hermes-linux-stack)",
            text,
        )


if __name__ == "__main__":
    unittest.main()
