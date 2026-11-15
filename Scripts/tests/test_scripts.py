"""Tests for Scripts/signing-identity, Scripts/log-audit and Scripts/install.

Run: python3 -m unittest discover -s Scripts/tests
"""
import importlib.machinery
import json
import os
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


class ReplaceFailureTests(unittest.TestCase):
    def test_failed_move_in_restores_previous(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            installed = make_app(root / "Applications" / "Captalo.app", extra="old.txt")
            staged = make_app(root / "staged" / "Captalo.app")
            calls = []

            def move(src, dst):
                calls.append(dst)
                if len(calls) == 2:
                    raise OSError("disk full")
                return install.shutil.move(src, dst)

            with self.assertRaises(install.InstallError) as raised:
                install.replace(staged, installed, root / "prev", verify=ok, move=move)
            self.assertIn("restored", str(raised.exception))
            self.assertTrue((installed / "Contents" / "Resources" / "old.txt").exists())

    def test_check_install_target_runs_before_any_quit(self):
        with tempfile.TemporaryDirectory() as tmp:
            other = make_app(Path(tmp) / "Captalo.app", bundle="com.example.other")
            with self.assertRaises(install.InstallError):
                install.check_install_target(other)


collect = load("capture-matrix-collect")


class CaptureCollectTests(unittest.TestCase):
    def test_parses_probe_lines_only(self):
        line = "2026-11-15 10:00:01.000 I  Captalo[123:abc] [com.thecreativetoken.captalo:Events] probe result=pass layer=menuCopy expectedLength=300 capturedLength=300 clipboardIntact=true focusKept=true elapsedMs=120 changeDelta=2"
        event = collect.parse(line)
        self.assertEqual(event["event"], "probe")
        self.assertEqual(event["result"], "pass")
        self.assertEqual(event["changeDelta"], "2")
        self.assertEqual(collect.parse("x [com.thecreativetoken.captalo:Events] clipboardSnapshot items=2 bytes=40 elapsedMs=3")["bytes"], "40")
        self.assertIsNone(collect.parse("2026-11-15 10:00:01.000 I  Other[1:2] unrelated line"))


class SubsystemTests(unittest.TestCase):
    def test_collector_subsystem_matches_privacy_log(self):
        source = (SCRIPTS.parent / "Packages/CaptaloCore/Sources/CaptaloCore/Logging/PrivacyLog.swift").read_text()
        collector = (SCRIPTS / "capture-matrix-collect").read_text()
        self.assertIn('subsystem = "com.thecreativetoken.captalo"', source)
        self.assertIn('subsystem == "com.thecreativetoken.captalo"', collector)


class FetchModelsTests(unittest.TestCase):
    """fetchScriptRejectsBytesNotMatchingManifest, at the script level."""

    def test_bytes_not_matching_the_manifest_are_rejected_and_nothing_is_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            models = Path(tmp, "models")
            (models / "kokoro").mkdir(parents=True)
            (models / "kokoro" / "vocab.json").write_text("{\"a\": 1}")
            manifest = Path(tmp, "manifest.json")
            manifest.write_text(json.dumps({"files": [{"path": "kokoro/vocab.json", "size": 10,
                                                        "sha256": "0" * 64}], "generated": [], "voices": ["af_heart"]}))
            before = manifest.read_text()
            env = dict(os.environ, MODELS=str(models), MANIFEST=str(manifest))
            result = subprocess.run([str(SCRIPTS / "fetch-models"), "--verify-only"], env=env,
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertEqual(manifest.read_text(), before)


class DefaultsBackupTests(unittest.TestCase):
    """Round trip on a disposable defaults domain, removed afterwards."""

    def setUp(self):
        import uuid
        self.domain = f"com.thecreativetoken.captalo.scripttest-{uuid.uuid4().hex[:8]}"
        self.tmp = tempfile.TemporaryDirectory()
        self.env = dict(os.environ, CAPTALO_DEFAULTS_DOMAIN=self.domain, CAPTALO_DEFAULTS_DIR=self.tmp.name)

    def tearDown(self):
        subprocess.run(["defaults", "delete", self.domain], capture_output=True)
        self.tmp.cleanup()

    def run_script(self, name):
        return subprocess.run([str(SCRIPTS / name)], env=self.env, capture_output=True, text=True, check=False)

    def read(self, key):
        return subprocess.run(["defaults", "read", self.domain, key], capture_output=True, text=True).stdout.strip()

    def is_empty(self):
        out = subprocess.run(["defaults", "export", self.domain, "-"], capture_output=True).stdout
        return plistlib.loads(out) == {} if out else True

    def test_present_domain_is_exported_deleted_and_restored(self):
        subprocess.run(["defaults", "write", self.domain, "reading.voice", "af_bella"], check=True)
        backup = self.run_script("defaults-backup")
        self.assertEqual(backup.returncode, 0, backup.stderr)
        self.assertTrue(self.is_empty())
        # The check writes new keys (a recorded shortcut); restore must remove them.
        subprocess.run(["defaults", "write", self.domain, "KeyboardShortcuts_readSelection", "test"], check=True)
        self.assertNotEqual(self.run_script("defaults-backup").returncode, 0)  # one check at a time
        restore = self.run_script("defaults-restore")
        self.assertEqual(restore.returncode, 0, restore.stderr)
        self.assertEqual(self.read("reading.voice"), "af_bella")
        self.assertEqual(self.read("KeyboardShortcuts_readSelection"), "")
        self.assertEqual(self.run_script("defaults-restore").returncode, 0)  # idempotent

    def test_absent_domain_is_recorded_and_deleted_again(self):
        self.assertEqual(self.run_script("defaults-backup").returncode, 0)
        subprocess.run(["defaults", "write", self.domain, "reading.speed", "-float", "1.2"], check=True)
        self.assertEqual(self.run_script("defaults-restore").returncode, 0)
        self.assertTrue(self.is_empty())


class MakefileTests(unittest.TestCase):
    def test_failed_xcodebuild_fails_the_piped_recipe(self):
        result = subprocess.run(["make", "-s", "build-unsigned-debug", "XCODEBUILD=false"],
                                cwd=SCRIPTS.parent, capture_output=True, text=True, check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


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

    def test_other_logging_forms_are_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "C.swift").write_text('debugPrint(x)\ndump(y)\nprint ("z")\nlet l = Logger.init(subsystem: "a", category: "b")\nos_signpost(.begin, log: l, name: "n")\n')
            self.assertEqual(len(log_audit.audit([tmp])), 5)

    def test_missing_root_is_an_error(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(log_audit.main(["/nonexistent-captalo-root"]), 2)


if __name__ == "__main__":
    unittest.main()
