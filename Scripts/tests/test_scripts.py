"""Tests for Scripts/signing-identity, Scripts/log-audit and Scripts/install.

Run: python3 -m unittest discover -s Scripts/tests
"""
import importlib.machinery
import importlib.util
import io
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(SCRIPTS / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


signing = load("signing-identity")
install = load("install")
log_audit = load("log-audit")


class SigningIdentityTests(unittest.TestCase):
    def run_script(self, fixture):
        return subprocess.run(
            [sys.executable, str(SCRIPTS / "signing-identity"), "--input", str(FIXTURES / fixture)],
            capture_output=True, text=True, check=False,
        )

    def test_no_identity_exits_2_with_message(self):
        result = self.run_script("find-identity-none.txt")
        self.assertEqual(result.returncode, 2)
        self.assertIn("No Apple Development identity", result.stderr)
        self.assertIn("Xcode > Settings > Accounts", result.stderr)
        self.assertIn("make signing-setup", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_one_identity_returns_it(self):
        result = self.run_script("find-identity-one.txt")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "0123456789ABCDEF0123456789ABCDEF01234567")

    def test_other_identity_kinds_are_ignored(self):
        self.assertEqual(self.run_script("find-identity-other.txt").returncode, 2)


def make_app(path, bundle="com.thecreativetoken.captalo", extra=None):
    contents = Path(path) / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    with open(contents / "Info.plist", "wb") as handle:
        plistlib.dump({"CFBundleIdentifier": bundle, "CFBundleVersion": "1"}, handle)
    (contents / "MacOS" / "Captalo").write_text("binary")
    if extra:
        (contents / "Resources" / extra).write_text("extra")
    return Path(path)


def ok(_):
    return True, ""


class ReplaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.installed = self.root / "Applications" / "Captalo.app"
        self.installed.parent.mkdir()
        self.previous = self.root / "install-previous"

    def tearDown(self):
        self.tmp.cleanup()

    def test_replace_never_merges(self):
        make_app(self.installed, extra="stale.txt")
        staged = make_app(self.root / "staged" / "Captalo.app")
        install.replace(staged, self.installed, self.previous, verify=ok)
        self.assertFalse((self.installed / "Contents" / "Resources" / "stale.txt").exists())
        self.assertTrue((self.previous / "Captalo.app" / "Contents" / "Resources" / "stale.txt").exists())

    def test_other_bundle_id_touches_nothing(self):
        make_app(self.installed, bundle="com.example.other")
        staged = make_app(self.root / "staged" / "Captalo.app")
        with self.assertRaises(install.InstallError):
            install.replace(staged, self.installed, self.previous, verify=ok)
        self.assertEqual(install.bundle_id(self.installed), "com.example.other")
        self.assertTrue(staged.exists())
        self.assertFalse(self.previous.exists())

    def test_installed_verification_failure_rolls_back(self):
        make_app(self.installed, extra="old.txt")
        staged = make_app(self.root / "staged" / "Captalo.app", extra="new.txt")
        calls = []

        def verify(app):
            calls.append(app)
            return (len(calls) > 1), "bad signature"

        with self.assertRaises(install.InstallError) as raised:
            install.replace(staged, self.installed, self.previous, verify=verify)
        self.assertIn("restored and verified", str(raised.exception))
        self.assertTrue((self.installed / "Contents" / "Resources" / "old.txt").exists())
        self.assertFalse((self.installed / "Contents" / "Resources" / "new.txt").exists())

    def test_older_rollback_copy_is_replaced(self):
        make_app(self.previous / "Captalo.app", extra="oldest.txt")
        make_app(self.installed, extra="old.txt")
        install.replace(make_app(self.root / "s" / "Captalo.app"), self.installed, self.previous, verify=ok)
        rollback = self.previous / "Captalo.app" / "Contents" / "Resources"
        self.assertTrue((rollback / "old.txt").exists())
        self.assertFalse((rollback / "oldest.txt").exists())

    def test_staged_verification_failure_leaves_install_untouched(self):
        make_app(self.installed, extra="old.txt")
        built = make_app(self.root / "built" / "Captalo.app", extra="new.txt")
        with self.assertRaises(install.InstallError):
            install.stage(built, self.root / "install-staging", verify=lambda _: (False, "unsigned"))
        self.assertTrue((self.installed / "Contents" / "Resources" / "old.txt").exists())


class QuitRecordedTests(unittest.TestCase):
    exe = "/Applications/Captalo.app/Contents/MacOS/Captalo"

    def test_unrecorded_process_is_a_stop_and_nothing_is_killed(self):
        killed = []
        with self.assertRaises(install.InstallError):
            install.quit_recorded({"pid": 10}, self.exe, pids_fn=lambda _: [10, 11],
                                  kill=lambda pid, sig: killed.append(pid))
        self.assertEqual(killed, [])

    def test_no_record_and_a_running_process_is_a_stop(self):
        with self.assertRaises(install.InstallError):
            install.quit_recorded(None, self.exe, pids_fn=lambda _: [12], kill=lambda *a: None)

    def test_recorded_process_is_quit(self):
        alive = [20]
        install.quit_recorded({"pid": 20}, self.exe, pids_fn=lambda _: list(alive),
                              kill=lambda pid, sig: alive.remove(pid))
        self.assertEqual(alive, [])

    def test_nothing_running_is_fine(self):
        install.quit_recorded({"pid": 30}, self.exe, pids_fn=lambda _: [], kill=lambda *a: self.fail("kill"))


class LogAuditTests(unittest.TestCase):
    def test_direct_logging_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "A.swift").write_text('let l = Logger(subsystem: "x", category: "y")\nprint("hi")\n// print("comment")\n')
            Path(tmp, "B.swift").write_text("PrivacyLog.record(.voicePrewarmed(accelerator: .neuralEngine))\n")
            hits = log_audit.audit([tmp])
        self.assertEqual(len(hits), 2)

    def test_missing_root_is_an_error(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(log_audit.main(["/nonexistent-captalo-root"]), 2)


if __name__ == "__main__":
    unittest.main()
