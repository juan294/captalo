"""Scripts/shell-audit: the network entitlement stays out of the app."""
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class NetworkEntitlement(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for folder in ("Scripts", "Captalo/Services/OCR", "Captalo.xcodeproj", "Packages/CaptaloOCR/Sources/CaptaloOCR"):
            (self.root / folder).mkdir(parents=True)
        shutil.copy(ROOT / "Scripts" / "shell-audit", self.root / "Scripts" / "shell-audit")
        contents = self.root / ".local/build/DerivedData/Build/Products/Debug/Captalo.app/Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"LSUIElement": True}))

    def audit(self, setting):
        (self.root / "Captalo.xcodeproj" / "project.pbxproj").write_text(f"\t\t\t\t{setting}\n")
        return subprocess.run([str(self.root / "Scripts" / "shell-audit")], capture_output=True, text=True)

    def test_no_is_accepted(self):
        for setting in ("ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO;", 'ENABLE_OUTGOING_NETWORK_CONNECTIONS = "NO";'):
            result = self.audit(setting)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_any_other_value_or_spelling_is_refused(self):
        for setting in (
                "ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;", 'ENABLE_OUTGOING_NETWORK_CONNECTIONS = "YES";',
                '"ENABLE_OUTGOING_NETWORK_CONNECTIONS[sdk=macosx*]" = YES;',
                "ENABLE_INCOMING_NETWORK_CONNECTIONS = YES;", "ENABLE_OUTGOING_NETWORK_CONNECTIONS = 1;",
                'ENABLE_OUTGOING_NETWORK_CONNECTIONS = "$(NETWORK)";'):
            with self.subTest(setting=setting):
                result = self.audit(setting)
                self.assertEqual(result.returncode, 1)
                self.assertIn("NETWORK_CONNECTIONS", result.stderr)

    def test_entitlements_file_is_refused(self):
        (self.root / "Captalo" / "Captalo.entitlements").write_text("<key>com.apple.security.network.client</key>")
        result = self.audit("")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Captalo.entitlements", result.stderr)


if __name__ == "__main__":
    unittest.main()
