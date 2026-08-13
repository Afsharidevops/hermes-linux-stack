from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryLayoutTest(unittest.TestCase):
    def test_single_canonical_root_changelog(self):
        self.assertTrue((ROOT / "CHANGELOG.md").is_file())
        self.assertEqual([], sorted(p.name for p in ROOT.glob("CHANGELOG-v*.md")))

    def test_release_command_history_is_archived(self):
        self.assertEqual([], sorted(p.name for p in ROOT.glob("RELEASE-COMMANDS-v*.md")))
        archived = ROOT / "docs" / "archive" / "release-commands"
        for version in ("0.5.3", "0.5.4", "0.5.5", "0.5.6", "0.5.7", "0.5.8"):
            self.assertTrue((archived / f"RELEASE-COMMANDS-v{version}.md").is_file())

    def test_current_docs_remain_easy_to_find(self):
        self.assertTrue((ROOT / "docs" / "HERMES-OPERATIONS-CENTER-USER-GUIDE-v0.5.9.md").is_file())
        self.assertTrue((ROOT / "docs" / "HERMES-LINUX-STACK-v0.5.9-PLAN.md").is_file())
        self.assertTrue((ROOT / "docs" / "RELEASE-PROCESS.md").is_file())

    def test_superseded_operations_guides_are_archived(self):
        archive = ROOT / "docs" / "archive" / "user-guides"
        for version in ("0.5.5", "0.5.6", "0.5.7", "0.5.8"):
            name = f"HERMES-OPERATIONS-CENTER-USER-GUIDE-v{version}.md"
            self.assertFalse((ROOT / "docs" / name).exists())
            self.assertTrue((archive / name).is_file())

    def test_release_version_is_current(self):
        self.assertEqual("v0.5.9", (ROOT / "VERSION").read_text(encoding="utf-8").strip())


if __name__ == "__main__":
    unittest.main()
