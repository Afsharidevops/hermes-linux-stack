from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


class OmniRouteN8nProvisioningTest(unittest.TestCase):
    def test_compose_keeps_management_bootstrap_key_only_on_omniroute(self):
        compose = yaml.safe_load((ROOT / "docker-compose.yml").read_text(encoding="utf-8"))
        services = compose["services"]
        self.assertEqual(
            "${OMNIROUTE_MANAGEMENT_API_KEY}",
            services["omniroute"]["environment"]["OMNIROUTE_API_KEY"],
        )
        for name, service in services.items():
            if name == "omniroute":
                continue
            environment = service.get("environment") or {}
            self.assertNotIn("OMNIROUTE_MANAGEMENT_API_KEY", str(environment))
            self.assertNotEqual(
                "${OMNIROUTE_MANAGEMENT_API_KEY}",
                environment.get("OMNIROUTE_API_KEY"),
            )

    def test_installer_initializes_client_key_before_hermes_uses_it(self):
        text = (ROOT / "install.sh").read_text(encoding="utf-8")
        assignment = text.find('client_key="$(existing_env_value SMART_ROUTER_CLIENT_API_KEY)"')
        use = text.find('provider_key="$client_key"')
        persistence = text.find(
            'replace_env_value "$tmp_env" SMART_ROUTER_CLIENT_API_KEY "$client_key"'
        )
        self.assertGreaterEqual(assignment, 0)
        self.assertGreater(use, assignment)
        self.assertGreater(persistence, assignment)

    def test_installer_generates_management_bootstrap_key(self):
        env_example = (ROOT / ".env.example").read_text(encoding="utf-8")
        installer = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn("OMNIROUTE_MANAGEMENT_API_KEY=CHANGE_ME", env_example)
        self.assertIn("'OMNIROUTE_MANAGEMENT_API_KEY'", installer)

    def test_direct_n8n_path_auto_provisions_omniroute_key_and_uses_auto_model(self):
        text = (ROOT / "manage.sh").read_text(encoding="utf-8")
        self.assertIn("HERMES_N8N_SERVICE_KEY_NAME=n8n (hermes-linux-stack)", text)
        self.assertIn('fetch("http://127.0.0.1:20128/api/keys"', text)
        self.assertIn('router_base_url="http://omniroute:20129/v1"', text)
        self.assertIn('router_model="auto"', text)
        self.assertIn("omniroute-n8n-router.env", text)


if __name__ == "__main__":
    unittest.main()
