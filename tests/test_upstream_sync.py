"""Use real temporary Git histories to check preservation and conflict handling."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "merge-upstream.py"


class UpstreamSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-b", "original")
        self.git("config", "user.name", "Sync test")
        self.git("config", "user.email", "sync@example.test")
        self.git("config", "core.autocrlf", "false")
        main = '#!/bin/bash\n# Version: 4.6.2\nset -e\nSCRIPT_VERSION="4.6.2"\n'
        main += "\n# stable context\n" * 6 + 'echo original\n' + "\n# stable context\n" * 6
        self.write("remnanode.sh", main)
        self.write("remnanode-xray-update.sh", "#!/bin/bash\n# Version: 1.0.0\necho updater\n")
        self.git("add", ".")
        self.git("commit", "-m", "Original")
        self.git("checkout", "-b", "fork")
        self.write("remnanode.sh", main.replace("4.6.2", "4.6.2-jm.1") + "OUR_FEATURE=preserved\n")
        self.write("remnanode-xray-update.sh", "#!/bin/bash\n# Version: 1.0.0-jm.1\necho updater\n")
        self.git("commit", "-am", "Our features")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True,
                              text=True, capture_output=True).stdout.strip()

    def write(self, path, text):
        (self.root / path).write_text(text, encoding="utf-8", newline="\n")

    def update_original(self, version="4.6.2", output="updated"):
        self.git("checkout", "original")
        path = self.root / "remnanode.sh"
        self.write(path.name, path.read_text().replace("4.6.2", version).replace("echo original", f"echo {output}"))
        self.git("commit", "-am", "Upstream update")
        self.git("checkout", "fork")

    def sync(self):
        return subprocess.run([sys.executable, str(SCRIPT), "original"], cwd=self.root,
                              text=True, capture_output=True)

    def test_preserves_features_and_increments_revision(self):
        self.update_original()
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        text = (self.root / "remnanode.sh").read_text()
        self.assertIn("OUR_FEATURE=preserved", text)
        self.assertIn("echo updated", text)
        self.assertIn('SCRIPT_VERSION="4.6.2-jm.2"', text)
        self.assertEqual(self.git("status", "--porcelain"), "")
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(self.sync().returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)

    def test_resolves_only_version_conflicts(self):
        self.update_original("4.6.3")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        text = (self.root / "remnanode.sh").read_text()
        self.assertIn('SCRIPT_VERSION="4.6.3-jm.1"', text)
        self.assertIn("OUR_FEATURE=preserved", text)

    def test_code_conflicts_need_manual_review(self):
        path = self.root / "remnanode.sh"
        self.write(path.name, path.read_text().replace("echo original", "echo ours"))
        self.git("commit", "-am", "Feature in the same function")
        head = self.git("rev-parse", "HEAD")
        self.update_original(output="theirs")
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Resolve these conflicts", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertIn("remnanode.sh", self.git("diff", "--name-only", "--diff-filter=U"))

    def test_dirty_checkout_is_untouched(self):
        self.update_original()
        self.write("local-note", "keep me")
        self.assertNotEqual(self.sync().returncode, 0)
        self.assertEqual((self.root / "local-note").read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()
