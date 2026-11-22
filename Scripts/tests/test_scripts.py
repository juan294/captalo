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
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
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
panel_render_check = load("panel-render-check")


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

    prefix = "com.thecreativetoken.captalo.scripttest-"

    def setUp(self):
        import uuid
        self.suffix = uuid.uuid4().hex[:8]
        self.domain = self.prefix + self.suffix
        self.tmp = tempfile.TemporaryDirectory()
        # The running-app guard watches a task-owned path, never the owner's installed app,
        # so these tests pass whether or not /Applications/Captalo.app is running.
        self.app = Path(self.tmp.name) / "app" / "Captalo"
        self.env = dict(os.environ, CAPTALO_DEFAULTS_DOMAIN=self.domain, CAPTALO_DEFAULTS_DIR=self.tmp.name,
                        CAPTALO_DEFAULTS_APP=str(self.app))

    def tearDown(self):
        subprocess.run(["defaults", "delete", self.domain], capture_output=True)
        # The delete leaves an empty plist; remove only the one this test's unique domain created.
        plist = Path.home() / "Library" / "Preferences" / f"{self.prefix}{self.suffix}.plist"
        plist.unlink(missing_ok=True)
        self.tmp.cleanup()
        self.assertFalse(plist.exists(), "disposable plist left behind")

    def run_script(self, name):
        return subprocess.run([str(SCRIPTS / name)], env=self.env, capture_output=True, text=True, check=False)

    def read(self, key):
        return subprocess.run(["defaults", "read", self.domain, key], capture_output=True, text=True).stdout.strip()

    def is_empty(self):
        out = subprocess.run(["defaults", "export", self.domain, "-"], capture_output=True).stdout
        return plistlib.loads(out) == {} if out else True

    def start_app(self):
        """A process whose command line starts with the guarded path (a copied
        system binary is killed at launch, so only argv[0] is renamed)."""
        running = subprocess.Popen(["/bin/bash", "-c", 'exec -a "$0" /bin/sleep 30', str(self.app)])
        self.addCleanup(running.wait)
        self.addCleanup(running.kill)
        for _ in range(50):
            if subprocess.run(["pgrep", "-f", f"^{self.app}( |$)"], capture_output=True).returncode == 0:
                return running
            time.sleep(0.02)
        self.fail("stand-in app process did not start")

    def test_running_app_blocks_backup(self):
        self.start_app()
        result = self.run_script("defaults-backup")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Cáptalo is running; quit it first.", result.stderr)
        self.assertEqual(list(Path(self.tmp.name).glob("defaults-*.state")), [], "nothing recorded while running")

    def test_running_app_blocks_restore(self):
        subprocess.run(["defaults", "write", self.domain, "reading.voice", "af_bella"], check=True)
        self.assertEqual(self.run_script("defaults-backup").returncode, 0)
        running = self.start_app()
        result = self.run_script("defaults-restore")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Cáptalo is running; quit it first.", result.stderr)
        running.kill()
        running.wait()
        self.assertEqual(self.run_script("defaults-restore").returncode, 0)
        self.assertEqual(self.read("reading.voice"), "af_bella")

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

    def test_absent_domain_with_values_left_after_delete_is_not_marked_restored(self):
        """VAL-11: a failed (or ineffective) delete must not mark the backup restored."""
        for status in (1, 0):
            with self.subTest(delete_exit=status):
                # Fresh start per case, even after a failed case.
                self.env["PATH"] = os.environ["PATH"]
                subprocess.run(["defaults", "delete", self.domain], capture_output=True)
                for marker in Path(self.tmp.name).glob("defaults-*"):
                    marker.unlink()
                self.assertEqual(self.run_script("defaults-backup").returncode, 0)
                subprocess.run(["defaults", "write", self.domain, "reading.speed", "-float", "1.2"], check=True)
                self.stub_failing("delete", status=status)
                restore = self.run_script("defaults-restore")
                self.assertNotEqual(restore.returncode, 0, restore.stdout)
                self.assertEqual(list(Path(self.tmp.name).glob("defaults-*.restored")), [])
                self.assertEqual(self.read("reading.speed"), "1.2")

    def stub(self, body):
        """A `defaults` on PATH running `body` (bash) first; verbs it does not handle are real."""
        stub = Path(self.tmp.name) / "bin"
        stub.mkdir(exist_ok=True)
        (stub / "defaults").write_text(f'#!/bin/bash\n{body}\nexec /usr/bin/defaults "$@"\n')
        (stub / "defaults").chmod(0o755)
        self.env["PATH"] = f"{stub}:{os.environ['PATH']}"

    def stub_failing(self, *verbs, status=1):
        """`verbs` exit with `status` without touching the domain; other verbs are real."""
        self.stub(f'case "$1" in {"|".join(verbs)}) echo "stub: $1 exits {status}" >&2; exit {status};; esac')

    def test_unreadable_domain_is_never_marked_restored(self):
        """VAL-11: an inspection failure is not proof of absence."""
        for has_values in (False, True):
            with self.subTest(has_values=has_values):
                self.env["PATH"] = os.environ["PATH"]
                subprocess.run(["defaults", "delete", self.domain], capture_output=True)
                for marker in Path(self.tmp.name).glob("defaults-*"):
                    marker.unlink()
                self.assertEqual(self.run_script("defaults-backup").returncode, 0)
                if has_values:
                    subprocess.run(["defaults", "write", self.domain, "reading.speed", "-float", "1.2"], check=True)
                self.stub_failing("export", "read", "delete")
                restore = self.run_script("defaults-restore")
                self.assertNotEqual(restore.returncode, 0, restore.stdout)
                self.assertIn("cannot read", restore.stderr)
                self.assertEqual(list(Path(self.tmp.name).glob("defaults-*.restored")), [])
                if has_values:
                    self.assertEqual(self.read("reading.speed"), "1.2")

    def test_backup_of_an_unreadable_domain_records_nothing(self):
        """VAL-11: backup never records `absent` from a failed inspection."""
        subprocess.run(["defaults", "write", self.domain, "reading.voice", "af_bella"], check=True)
        self.stub_failing("export", "read")
        backup = self.run_script("defaults-backup")
        self.assertNotEqual(backup.returncode, 0, backup.stdout)
        self.assertIn("cannot read", backup.stderr)
        self.assertNotIn("stub: export", backup.stderr)  # aborted before the backup export
        self.assertEqual(list(Path(self.tmp.name).glob("defaults-*")), [])
        self.assertEqual(self.read("reading.voice"), "af_bella")

    def test_unreadable_state_after_the_delete_aborts_restore(self):
        """The second inspection, after a delete, aborts restore too."""
        self.assertEqual(self.run_script("defaults-backup").returncode, 0)
        subprocess.run(["defaults", "write", self.domain, "reading.speed", "-float", "1.2"], check=True)
        flag = Path(self.tmp.name) / "deleted"
        self.stub(f'case "$1" in delete) /usr/bin/defaults "$@"; s=$?; touch "{flag}"; exit $s;; '
                  f'export) [ -e "{flag}" ] && exit 1;; esac')
        restore = self.run_script("defaults-restore")
        self.assertNotEqual(restore.returncode, 0, restore.stdout)
        self.assertTrue(flag.exists())
        self.assertIn("cannot read", restore.stderr)
        self.assertNotIn("still has values", restore.stderr)  # aborted at the inspection itself
        self.assertEqual(list(Path(self.tmp.name).glob("defaults-*.restored")), [])

    def prefs_file(self, content=None, mode=None):
        """This test's plist in a private preferences directory the scripts inspect (never the real one)."""
        prefs = Path(self.tmp.name) / "Preferences"
        prefs.mkdir(exist_ok=True)
        self.env["CAPTALO_DEFAULTS_PREFS"] = str(prefs)
        plist = prefs / f"{self.domain}.plist"
        if plist.exists():  # a previous case's file, possibly unreadable
            plist.chmod(0o600)
            plist.unlink()
        if content is not None:
            plist.write_bytes(content)
        if mode is not None:
            plist.chmod(mode)
            self.addCleanup(lambda: plist.exists() and plist.chmod(0o600))
        return plist

    def test_unreadable_or_inconsistent_plist_file_is_never_absent(self):
        """VAL-11: export can print <dict/> for an unreadable, corrupt or keyed plist; the file decides."""
        keyed = plistlib.dumps({"reading.voice": "af_bella"})
        cases = {
            "unreadable file": (keyed, 0o000),
            "corrupt file": (b"<?xml version='1.0'?><plist><dict><key>x", None),
            "file with keys while the export is empty": (keyed, None),
        }
        for name, (content, mode) in cases.items():
            with self.subTest(name):
                for marker in Path(self.tmp.name).glob("defaults-*"):
                    marker.unlink()
                self.prefs_file(content, mode)
                backup = self.run_script("defaults-backup")
                self.assertNotEqual(backup.returncode, 0, backup.stdout)
                self.assertIn("cannot read", backup.stderr)
                self.assertEqual(list(Path(self.tmp.name).glob("defaults-*")), [])
                Path(self.tmp.name, "defaults-20000101T000000Z.state").write_text("absent\n")
                restore = self.run_script("defaults-restore")
                self.assertNotEqual(restore.returncode, 0, restore.stdout)
                self.assertIn("cannot read", restore.stderr)
                self.assertEqual(list(Path(self.tmp.name).glob("defaults-*.restored")), [])

    def test_empty_dictionary_plist_counts_as_absent(self):
        """What `defaults delete` leaves behind: an empty-dictionary plist."""
        self.prefs_file(plistlib.dumps({}))
        backup = self.run_script("defaults-backup")
        self.assertEqual(backup.returncode, 0, backup.stderr)
        self.assertIn("domain absent", backup.stdout)

    def test_already_absent_domain_is_restored_without_a_delete(self):
        self.assertEqual(self.run_script("defaults-backup").returncode, 0)
        self.stub_failing("delete")  # nothing to delete, so a delete must not be needed
        restore = self.run_script("defaults-restore")
        self.assertEqual(restore.returncode, 0, restore.stderr)
        self.assertEqual(len(list(Path(self.tmp.name).glob("defaults-*.restored"))), 1)


completeness = load("completeness-test")


def unit_record(voice, unit=0, completed=True):
    return {"kind": "unit", "voice": voice, "unit": unit, "completed": completed, "phonemes": 5, "normalizedText": "text"}


def summary_record(voice, outcome="finished", queued=0.0):
    return {"kind": "summary", "voice": voice, "outcome": outcome, "units": 1, "expectedUnits": 1,
            "playedExactlyOnceInOrder": True, "textReassembles": True, "playedInOrder": True,
            "maxUnitSeconds": 10.0, "maxQueuedSeconds": queued, "maxRetained": 2, "firstAudioMs": 100,
            "totalMs": 900, "peakFootprintMB": 500.0, "oversizeSplits": 0}


class PanelRenderCheckTests(unittest.TestCase):
    """make panel-render: the check must fail for a missing, wrong-size or unreadable image."""

    @staticmethod
    def png(width, height):
        return b"\x89PNG\r\n\x1a\n" + (13).to_bytes(4, "big") + b"IHDR" + width.to_bytes(4, "big") + height.to_bytes(4, "big")

    def render(self, directory):
        for name in panel_render_check.expected_names():
            (Path(directory) / name).write_bytes(self.png(880, 1080))

    def run_script(self, directory):
        return subprocess.run([sys.executable, str(SCRIPTS / "panel-render-check"), str(directory)],
                              capture_output=True, text=True, check=False)

    def test_complete_set_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            self.render(directory)
            result = self.run_script(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("16 images at 880x1080", result.stdout)

    def test_missing_image_fails_and_is_named(self):
        with tempfile.TemporaryDirectory() as directory:
            self.render(directory)
            (Path(directory) / "voice-damaged-light.png").unlink()
            result = self.run_script(directory)
            self.assertEqual(result.returncode, 1)
            self.assertIn("missing voice-damaged-light.png", result.stderr)

    def test_wrong_size_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            self.render(directory)
            (Path(directory) / "read-ready-dark.png").write_bytes(self.png(440, 540))
            result = self.run_script(directory)
            self.assertEqual(result.returncode, 1)
            self.assertIn("read-ready-dark.png is 440x540, expected 880x1080", result.stderr)

    def test_file_that_is_not_a_png_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            self.render(directory)
            (Path(directory) / "setup-all-set-dark.png").write_bytes(b"not an image")
            result = self.run_script(directory)
            self.assertEqual(result.returncode, 1)
            self.assertIn("setup-all-set-dark.png is not a readable PNG", result.stderr)

    def test_unexpected_image_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            self.render(directory)
            (Path(directory) / "old-fixture-dark.png").write_bytes(self.png(880, 1080))
            result = self.run_script(directory)
            self.assertEqual(result.returncode, 1)
            self.assertIn("unexpected old-fixture-dark.png", result.stderr)

    def test_missing_directory_fails(self):
        result = self.run_script("/nonexistent/captalo-panel-render")
        self.assertEqual(result.returncode, 1)
        self.assertIn("is not a directory", result.stderr)


class CompletenessHarnessTests(unittest.TestCase):
    """VAL-06: the harness fails unless every required probe record is present.

    Synthetic probe records only: a stub probe copies prepared JSON lines to the
    `--out` path the harness gives it, so no model or real synthesis runs.
    """
    voices = ["af_one", "af_two"]

    def valid_runs(self):
        first = self.voices[0]
        return {
            "completeness": [r for v in self.voices for r in (unit_record(v), summary_record(v))],
            "long": [unit_record(first), summary_record(first)],
            "long-stop": [*(unit_record(first, i) for i in range(5)), unit_record(first, 5, completed=False),
                          {"kind": "stop", "voice": first, "afterUnits": 5, "stopToSilenceMs": 0, "stopToIdleMs": 40},
                          {**summary_record(first, outcome="stopped"), "units": 5, "expectedUnits": 10}],
            "long-device": [{"kind": "deviceChange", "voice": first, "afterUnits": 3, "replayedUnits": [3],
                             "replaySpanSeconds": 20.0},
                            unit_record(first), summary_record(first, queued=60.0)],
        }

    def run_harness(self, runs):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Models.manifest.json").write_text(json.dumps({"voices": self.voices}))
            records = root / "records"
            records.mkdir()
            for label, lines in runs.items():
                (records / f"{label}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in lines))
            probe = root / "probe"
            probe.write_text(f"#!{sys.executable}\n" + """import pathlib, sys
args = sys.argv[1:]
if args[0] == "verify":
    print("models verified, version test-manifest")
    sys.exit(0)
out = pathlib.Path(args[args.index("--out") + 1])
out.write_text((pathlib.Path(__file__).parent / "records" / (out.stem + ".jsonl")).read_text())
""")
            probe.chmod(0o755)
            saved = completeness.ROOT, completeness.probe_path, sys.argv
            completeness.ROOT, completeness.probe_path = root, lambda: str(probe)
            sys.argv = ["completeness-test", str(root / "Models")]
            try:
                with redirect_stdout(io.StringIO()):
                    status = completeness.main()
            finally:
                completeness.ROOT, completeness.probe_path, sys.argv = saved
            written = list((root / ".local" / "completeness").glob("*.json"))
            self.assertEqual(len(written), 1, "the harness wrote no evidence")
            evidence = json.loads(written[0].read_text())
            return status, evidence["failures"]

    def assert_fails(self, runs, expected):
        status, failures = self.run_harness(runs)
        self.assertNotEqual(status, 0, failures)
        self.assertTrue(any(expected in f for f in failures), failures)

    def test_complete_synthetic_evidence_passes(self):
        self.assertEqual(self.run_harness(self.valid_runs()), (0, []))

    def test_each_missing_required_record_fails(self):
        for label, kind in [("long", "summary"), ("long-stop", "stop"), ("long-device", "deviceChange"),
                            ("long-device", "summary")]:
            with self.subTest(label=label, kind=kind):
                runs = self.valid_runs()
                runs[label] = [r for r in runs[label] if r["kind"] != kind]
                self.assert_fails(runs, f"{label}: expected one {kind} record")

    def test_omitted_voice_fails(self):
        runs = self.valid_runs()
        runs["completeness"] = [r for r in runs["completeness"] if r["voice"] != "af_two"]
        self.assert_fails(runs, "af_two: no summary")

    def test_duplicated_voice_fails(self):
        runs = self.valid_runs()
        runs["completeness"].append(summary_record("af_one"))
        self.assert_fails(runs, "af_one: 2 summaries")

    def test_each_invalid_payload_fails(self):
        def edit(label, match, **fields):
            def mutate(runs):
                record = next(r for r in runs[label] if all(r.get(k) == v for k, v in match.items()))
                record.update(fields)
            return mutate

        def drop(label, match, field=None):
            def mutate(runs):
                targets = [r for r in runs[label] if all(r.get(k) == v for k, v in match.items())]
                if field is None:
                    runs[label] = [r for r in runs[label] if r not in targets]
                else:
                    for r in targets:
                        del r[field]
            return mutate

        def add(label, *records):
            return lambda runs: runs[label].extend(records)

        cases = {
            "stop silence null": (edit("long-stop", {"kind": "stop"}, stopToSilenceMs=None), "stop: stopToSilenceMs"),
            "stop idle null": (edit("long-stop", {"kind": "stop"}, stopToIdleMs=None), "stop: stopToIdleMs"),
            "stop summary missing": (drop("long-stop", {"kind": "summary"}), "long-stop: expected one summary record"),
            "stop summary finished": (edit("long-stop", {"kind": "summary"}, outcome="finished"), "stop: outcome"),
            "long without unit records": (drop("long", {"kind": "unit"}), "long fixture: every unit record completed"),
            "units short of expected": (edit("completeness", {"kind": "summary", "voice": "af_one"}, units=0, expectedUnits=5),
                                        "af_one: played every expected unit"),
            "flag as a string": (edit("completeness", {"kind": "summary", "voice": "af_one"}, playedExactlyOnceInOrder="false"),
                                 "af_one: every expected unit played exactly once"),
            "device unit for another voice": (edit("long-device", {"kind": "unit"}, voice="af_two"),
                                              "long-device: unit records for af_two"),
            "unit records for an unknown voice": (add("completeness", unit_record("af_extra")),
                                                  "completeness: unit records for af_extra"),
            "missing summary field": (drop("completeness", {"kind": "summary", "voice": "af_one"}, field="maxUnitSeconds"),
                                      "af_one: missing or malformed field"),
        }
        for name, (mutate, expected) in cases.items():
            with self.subTest(name):
                runs = self.valid_runs()
                mutate(runs)
                self.assert_fails(runs, expected)

    def with_units(self, runs, label, ids, expected, splits=0, voice="af_one"):
        """Replaces `voice`'s unit records in `label` with `ids` (one record per piece)."""
        runs[label] = [r for r in runs[label] if not (r["kind"] == "unit" and r["voice"] == voice)]
        runs[label] += [unit_record(voice, i) for i in ids]
        summary = next(r for r in runs[label] if r["kind"] == "summary" and r["voice"] == voice)
        summary.update(units=expected, expectedUnits=expected, oversizeSplits=splits)
        return runs

    def test_split_unit_pieces_pass(self):
        """A runtime split records one piece per half, under the same unit ID."""
        runs = self.with_units(self.valid_runs(), "completeness", [0, 0, 1], expected=2, splits=1)
        self.assertEqual(self.run_harness(runs), (0, []))

    def test_unit_inventory_mismatches_fail(self):
        """VAL-06: unit records must cover IDs 0..expectedUnits-1, each once (split pieces adjacent)."""
        cases = {
            "one unit dropped, summary intact": ("completeness", [0], 2, 0),
            "unit duplicated": ("completeness", [0, 1, 0], 2, 0),
            "adjacent duplicate without a split": ("completeness", [0, 0, 1], 2, 0),
            "ID outside the inventory": ("completeness", [0, 1, 5], 2, 0),
            "long run missing a unit": ("long", [1], 2, 0),
            "device run missing a unit": ("long-device", [0, 2], 3, 0),
        }
        for name, (label, ids, expected, splits) in cases.items():
            with self.subTest(name):
                runs = self.with_units(self.valid_runs(), label, ids, expected, splits)
                self.assert_fails(runs, "unit records cover")

    def stopped(self, units, played=5, splits=0):
        """The stopped run with unit records `units` as (ID, completed) and `played` units in the summary."""
        runs = self.valid_runs()
        runs["long-stop"] = [r for r in runs["long-stop"] if r["kind"] != "unit"]
        runs["long-stop"] += [unit_record("af_one", i, done) for i, done in units]
        next(r for r in runs["long-stop"] if r["kind"] == "summary").update(units=played, oversizeSplits=splits)
        return runs

    def test_stopped_run_with_a_split_unit_passes(self):
        units = [(0, True), (1, True), (1, True), (2, True), (3, True), (4, True), (5, False)]
        self.assertEqual(self.run_harness(self.stopped(units, splits=1)), (0, []))

    def test_stopped_run_units_must_cover_the_played_units(self):
        """VAL-06: the stopped run's records cover exactly the units it played, as an in-order prefix."""
        cases = {
            "not a prefix": [(1, True)],
            "no unit records": [],
            "two records after five played units": [(0, True), (1, True)],
            "adjacent duplicate without a split": [(0, True), (0, True), (1, True), (2, True), (3, True), (4, True)],
            "an unplayed unit marked completed": [(i, True) for i in range(7)],
        }
        for name, units in cases.items():
            with self.subTest(name):
                self.assert_fails(self.stopped(units), "stop: unit records")

    def test_stop_before_the_requested_units_fails(self):
        units = [(0, True), (1, True), (2, False)]
        self.assert_fails(self.stopped(units, played=2), "stop: unit records")

    def test_voice_outside_the_manifest_fails(self):
        runs = self.valid_runs()
        runs["completeness"] += [unit_record("af_extra"), summary_record("af_extra")]
        self.assert_fails(runs, "af_extra: not in the manifest")


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
