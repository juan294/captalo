"""Scripts/release-evidence: the release evidence gate (release playbook, step 6)."""
import copy
import datetime
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "release-evidence"


def load():
    loader = importlib.machinery.SourceFileLoader("release_evidence", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


# Git sets GIT_DIR and others in hooks; an inherited value would aim these tests at another repository.
for name in [name for name in os.environ if name.startswith("GIT_")]:
    del os.environ[name]
gate = load()
OTHER = "b" * 40
BUILT = "2026-11-25T08:00:00Z"
RAN = "2026-11-25T10:00:00+01:00"
NOW = datetime.datetime(2026, 11, 26, tzinfo=datetime.timezone.utc)
CHECKS = [{"name": "core", "argv": ["make", "core"]}, {"name": "ocr", "argv": ["make", "ocr"]}]


def git(repo, *arguments, date="2026-11-24T12:00:00Z"):
    return subprocess.run(
        ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
         *arguments], cwd=repo, check=True, capture_output=True, text=True,
        env={**os.environ, "GIT_COMMITTER_DATE": date, "GIT_AUTHOR_DATE": date}).stdout.strip()


class GateCase(unittest.TestCase):
    """A complete, valid candidate on disk; each test breaks one thing."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.dir = Path(temp.name)
        self.repo = self.dir / "repo"
        (self.repo / ".rpi").mkdir(parents=True)
        git(self.repo, "init", "-q")
        (self.repo / "source.txt").write_text("with the crash")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "earlier build", date="2026-11-20T12:00:00Z")
        self.earlier = git(self.repo, "rev-parse", "HEAD")
        (self.repo / "source.txt").write_text("repaired")
        self.commit_policy(CHECKS)
        self.app = self.dir / "Captalo.app"
        resources = self.app / "Contents" / "Resources"
        resources.mkdir(parents=True)
        (self.app / "Contents" / "MacOS").mkdir()
        (self.app / "Contents" / "MacOS" / "Captalo").write_bytes(b"binary")
        self.build_info = resources / "build-info.json"
        self.write_build_info()
        self.receipt = {
            "status": "complete", "passed": True, "suite": "ci-equivalent",
            "identity": gate.source_identity(self.repo), "identity_after": gate.source_identity(self.repo),
            "identity_unchanged": True,
            "checks": [{**check, "exit_code": 0} for check in CHECKS],
        }
        digest = gate.bundle_digest(self.app)
        self.evidence = {
            "schema_version": 1,
            "candidate": {"commit": self.commit, "bundle_digest": digest},
            "probes": [self.probe(name, digest) for name in gate.REQUIRED_PROBES],
            "charter": {
                "commit": self.commit, "bundle_digest": digest, "time": RAN,
                "author": "fresh-context reviewer", "independent": True,
                "environment": "M5 Ultra, macOS 27.2.1", "procedure": "one round over the eight maneuvers",
                "maneuvers": [{"id": m, "status": "pass", "outcome": "as expected"} for m in gate.MANEUVERS],
                "findings": [],
                "cleanup": {"status": "done"},
            },
        }

    def commit_policy(self, checks):
        (self.repo / ".rpi" / "policy.json").write_text(json.dumps({"verification_checks": checks}))
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "policy")
        self.commit = git(self.repo, "rev-parse", "HEAD")

    def probe(self, name, digest):
        return {
            "id": name, "status": "pass", "commit": self.commit, "bundle_digest": digest,
            "environment": "M5 Ultra, macOS 27.2.1", "time": RAN,
            "procedure": "synthetic fixture", "outcome": "read in full", "cleanup": {"status": "done"},
        }

    def write_build_info(self, **changes):
        info = {"commit": self.commit, "dirty": False, "configuration": "Release", "built_at": BUILT}
        info.update(changes)
        self.build_info.write_text(json.dumps(info))

    def problems(self):
        return gate.analyze(self.evidence, self.receipt, self.repo, self.app, NOW)

    def named(self, name):
        return next(p for p in self.evidence["probes"] if p["id"] == name)

    def assert_only(self, expected):
        """Exactly one problem, and it is the expected one."""
        found = self.problems()
        self.assertEqual(len(found), 1, found)
        self.assertIn(expected, found[0])


class CompleteEvidence(GateCase):
    def test_complete_evidence_has_no_problem(self):
        self.assertEqual(self.problems(), [])

    def test_required_probes_cover_the_playbook(self):
        # Removing a probe from the list would silently shrink the gate.
        self.assertEqual(sorted(gate.REQUIRED_PROBES), sorted([
            "selection-rex", "selection-safari", "selection-chrome", "selection-preview", "selection-textedit",
            "selection-word", "selection-empty", "selection-failed", "clipboard-preserved", "focus-preserved", "stop-reading",
            "read-again", "long-passage-complete", "accessibility-denied-then-granted",
            "screen-recording-denied-then-granted", "first-install", "offline-selection", "offline-region",
            "region-capture", "region-scanned-pdf", "region-reading-order", "region-escape-focus",
            "region-full-screen", "second-display", "output-change-recovery", "voice-accepted", "minimum-macos",
        ]))
        self.assertEqual(gate.MAY_BE_NA, ("second-display",))

    def test_maneuvers_cover_the_playbook(self):
        self.assertEqual(gate.MANEUVERS, (
            "repeated-actions", "errors-and-recovery", "interruption", "second-app-or-session",
            "locale-or-device-change", "copy-versus-result", "downstream-state", "should-it-exist"))
        self.assertEqual(gate.MANEUVERS_MAY_BE_NA, ("downstream-state",))


class Bundle(GateCase):
    def test_changed_bundle_is_rejected(self):
        (self.app / "Contents" / "MacOS" / "Captalo").write_bytes(b"other")
        self.assert_only("candidate digest")

    def test_digest_sees_name_mode_and_link_changes(self):
        base = gate.bundle_digest(self.app)
        binary = self.app / "Contents" / "MacOS" / "Captalo"
        os.chmod(binary, 0o700)
        executable = gate.bundle_digest(self.app)
        binary.rename(binary.with_name("Renamed"))
        renamed = gate.bundle_digest(self.app)
        (self.app / "Contents" / "link").symlink_to("MacOS")
        linked = gate.bundle_digest(self.app)
        self.assertEqual(len({base, executable, renamed, linked}), 4)

    def test_digest_sees_a_moved_file_a_new_directory_and_a_new_link_target(self):
        contents = self.app / "Contents"
        (contents / "a").mkdir()
        (contents / "b").mkdir()
        (contents / "a" / "f").write_text("x")
        link = contents / "link"
        link.symlink_to("a")
        first = gate.bundle_digest(self.app)
        link.unlink()
        link.symlink_to("b")
        relinked = gate.bundle_digest(self.app)
        (contents / "a" / "f").rename(contents / "b" / "f")
        moved = gate.bundle_digest(self.app)
        (contents / "empty").mkdir()
        self.assertEqual(len({first, relinked, moved, gate.bundle_digest(self.app)}), 4)

    def test_digest_covers_the_whole_path(self):
        # The same names, in another place: a/b/f against a and b/f.
        digests = set()
        for number, nested in enumerate(("a/b", "b")):
            bundle = self.dir / f"{number}.app"
            (bundle / nested).mkdir(parents=True)
            (bundle / "a").mkdir(exist_ok=True)
            (bundle / nested / "f").write_text("x")
            digests.add(gate.bundle_digest(bundle))
        self.assertEqual(len(digests), 2)

    def test_digest_order_does_not_depend_on_the_directory_order(self):
        for name in ("a", "b", "c"):
            (self.app / "Contents" / name).write_text(name)
        expected = gate.bundle_digest(self.app)
        walk = os.walk

        def reversed_walk(top, **options):
            return [(folder, folders[::-1], files[::-1]) for folder, folders, files in walk(top, **options)][::-1]

        with mock.patch.object(gate.os, "walk", reversed_walk):
            self.assertEqual(gate.bundle_digest(self.app), expected)

    def test_link_out_of_the_bundle_is_an_error(self):
        for target in ("/etc/hosts", "../../outside"):
            with self.subTest(target=target):
                link = self.app / "Contents" / "link"
                link.symlink_to(target)
                with self.assertRaisesRegex(gate.EvidenceError, "leaves the bundle"):
                    gate.bundle_digest(self.app)
                link.unlink()

    def test_special_file_is_an_error(self):
        os.mkfifo(self.app / "Contents" / "pipe")
        with self.assertRaisesRegex(gate.EvidenceError, "neither a file"):
            gate.bundle_digest(self.app)

    def test_unreadable_directory_is_an_error(self):
        hidden = self.app / "Contents" / "hidden"
        hidden.mkdir()
        (hidden / "f").write_text("x")
        os.chmod(hidden, 0)
        self.addCleanup(os.chmod, hidden, 0o755)
        with self.assertRaises(OSError):
            gate.bundle_digest(self.app)

    def test_digest_is_the_same_for_a_copy(self):
        copied = self.dir / "Copy.app"
        subprocess.run(["/bin/cp", "-R", str(self.app), str(copied)], check=True)
        self.assertEqual(gate.bundle_digest(copied), gate.bundle_digest(self.app))

    def test_empty_bundle_is_an_error(self):
        empty = self.dir / "Empty.app"
        empty.mkdir()
        with self.assertRaisesRegex(gate.EvidenceError, "no files"):
            gate.bundle_digest(empty)

    def rebind(self):
        digest = gate.bundle_digest(self.app)
        self.evidence["candidate"]["bundle_digest"] = digest
        self.evidence["charter"]["bundle_digest"] = digest
        for probe in self.evidence["probes"]:
            probe["bundle_digest"] = digest

    def test_bundle_from_another_commit_is_rejected(self):
        self.write_build_info(commit=OTHER)
        self.rebind()
        self.assert_only("build-info commit")

    def test_dirty_or_unknown_bundle_is_rejected(self):
        for dirty in (True, None, "false"):
            with self.subTest(dirty=dirty):
                self.write_build_info(dirty=dirty)
                self.rebind()
                self.assert_only("not from a clean tree")

    def test_debug_bundle_is_rejected(self):
        self.write_build_info(configuration="Debug")
        self.rebind()
        self.assert_only("not a Release build")

    def test_bundle_without_a_build_time_is_rejected(self):
        self.write_build_info(built_at="yesterday")
        self.rebind()
        self.assert_only("build-info has no build time")

    def test_abbreviated_or_padded_candidate_commit_is_rejected(self):
        for commit in (self.commit[:7], self.commit + "0"):
            with self.subTest(commit=commit):
                self.evidence["candidate"]["commit"] = commit
                self.assertIn("candidate commit is not a full 40-character commit", self.problems())


class Receipt(GateCase):
    def test_failed_suite_is_rejected(self):
        for key, value in (("passed", False), ("passed", 1), ("status", "failed")):
            with self.subTest(key=key, value=value):
                original = self.receipt[key]
                self.receipt[key] = value
                self.assert_only("did not pass")
                self.receipt[key] = original

    def test_custom_suite_is_rejected(self):
        self.receipt["suite"] = "custom"
        self.assert_only("not the full suite")

    def test_check_that_ran_another_command_is_rejected(self):
        self.receipt["checks"][1]["argv"] = ["true"]
        self.assert_only("check ocr: ran another command")

    def test_suite_for_another_tree_is_rejected(self):
        for field, value in (("commit", OTHER), ("sha256", "d" * 64), ("file_count", 9)):
            with self.subTest(field=field):
                original = self.receipt["identity"][field]
                for key in ("identity", "identity_after"):
                    self.receipt[key][field] = value
                self.assert_only("another source tree")
                for key in ("identity", "identity_after"):
                    self.receipt[key][field] = original

    def test_identity_without_a_tree_digest_is_rejected(self):
        for key in ("identity", "identity_after"):
            del self.receipt[key]["sha256"]
        self.assert_only("another source tree")

    def test_tree_changed_during_the_suite_is_rejected(self):
        self.receipt["identity_unchanged"] = False
        self.assert_only("changed during verification")
        self.receipt["identity_unchanged"] = True
        self.receipt["identity_after"]["sha256"] = "d" * 64
        self.assert_only("changed during verification")

    def test_suite_on_an_uncommitted_fix_is_rejected(self):
        # The suite passed only because of an edit that the candidate commit does not have.
        (self.repo / "fix.txt").write_text("uncommitted")
        for key in ("identity", "identity_after"):
            self.receipt[key] = gate.source_identity(self.repo)
        (self.repo / "fix.txt").unlink()
        self.assert_only("another source tree")

    def test_dirty_checkout_is_rejected(self):
        (self.repo / "fix.txt").write_text("uncommitted")
        for key in ("identity", "identity_after"):
            self.receipt[key] = gate.source_identity(self.repo)
        self.assert_only("checkout is not clean")

    def test_git_settings_cannot_hide_a_dirty_checkout(self):
        git(self.repo, "config", "status.showUntrackedFiles", "no")
        (self.repo / "fix.txt").write_text("uncommitted")
        for key in ("identity", "identity_after"):
            self.receipt[key] = gate.source_identity(self.repo)
        self.assert_only("checkout is not clean")

    def test_local_ignore_rules_cannot_hide_a_fix(self):
        (self.repo / ".git" / "info").mkdir(exist_ok=True)
        (self.repo / ".git" / "info" / "exclude").write_text("fix.txt\n")
        (self.repo / "fix.txt").write_text("uncommitted")
        self.assert_only("only local ignore rules hide")

    def test_committed_ignore_rules_may_hide_build_output(self):
        (self.repo / ".gitignore").write_text(".local/\n")
        self.rebase(CHECKS)
        (self.repo / ".local").mkdir()
        (self.repo / ".local" / "build.log").write_text("output")
        self.assertEqual(self.problems(), [])

    def test_hidden_edit_of_the_policy_is_rejected(self):
        for hide, show in (("--assume-unchanged", "--no-assume-unchanged"), ("--skip-worktree", "--no-skip-worktree")):
            with self.subTest(hide=hide):
                policy = self.repo / ".rpi" / "policy.json"
                git(self.repo, "update-index", hide, ".rpi/policy.json")
                policy.write_text(json.dumps({"verification_checks": CHECKS[:1]}))
                whole = self.receipt["checks"]
                self.receipt["checks"] = whole[:1]
                for key in ("identity", "identity_after"):
                    self.receipt[key] = gate.source_identity(self.repo)
                self.assertEqual(self.problems(), ["the checkout hides changes from git", "check ocr: missing"])
                self.receipt["checks"] = whole
                git(self.repo, "update-index", show, ".rpi/policy.json")
                git(self.repo, "checkout", "-q", "--", ".")

    def test_checkout_of_another_commit_is_rejected(self):
        self.commit_policy(CHECKS + [{"name": "new", "argv": ["make", "new"]}])
        self.assertIn("the checkout is not at the candidate commit", self.problems())

    def test_missing_check_is_rejected(self):
        self.receipt["checks"].pop()
        self.assert_only("check ocr: missing")

    def test_failing_check_is_rejected(self):
        for code in (1, False, None, "0"):
            with self.subTest(code=code):
                self.receipt["checks"][1]["exit_code"] = code
                self.assert_only(f"check ocr: exit code {code}")

    def test_check_outside_the_policy_is_rejected(self):
        for name in ("extra", ["core"], None):
            with self.subTest(name=name):
                self.receipt["checks"].append({"name": name, "argv": ["x"], "exit_code": 0})
                self.assert_only(f"check {name}: not a required check")
                self.receipt["checks"].pop()

    def test_repeated_check_cannot_hide_a_failure(self):
        self.receipt["checks"].insert(1, {"name": "ocr", "argv": ["make", "ocr"], "exit_code": 1})
        self.assertEqual(self.problems(), ["check ocr: exit code 1", "check ocr: recorded more than once"])

    def rebase(self, checks):
        """A candidate whose committed policy declares these checks."""
        self.commit_policy(checks)
        for record in (self.evidence["candidate"], self.evidence["charter"], *self.evidence["probes"]):
            record["commit"] = self.commit
        self.write_build_info()
        for key in ("identity", "identity_after"):
            self.receipt[key] = gate.source_identity(self.repo)
        self.receipt["checks"] = [{**check, "exit_code": 0} for check in checks]
        digest = gate.bundle_digest(self.app)
        for record in (self.evidence["candidate"], self.evidence["charter"], *self.evidence["probes"]):
            record["bundle_digest"] = digest

    def test_empty_policy_is_rejected(self):
        self.rebase([])
        self.assert_only("policy declares no check")

    def test_nameless_policy_check_is_rejected(self):
        self.rebase([{"argv": ["x"]}])
        self.assertIn("the policy has a check with no name, or a repeated one", self.problems())


class Probes(GateCase):
    def test_zero_probes_is_rejected(self):
        self.evidence["probes"] = []
        found = self.problems()
        self.assertIn("no probe passed", found)

    def test_missing_probe_is_rejected(self):
        self.evidence["probes"].remove(self.named("selection-rex"))
        self.assert_only("probe selection-rex: missing")

    def test_any_status_but_pass_is_rejected(self):
        for status in ("fail", "skip", "not-run", "PASS", "na", None):
            with self.subTest(status=status):
                self.named("selection-rex")["status"] = status
                self.assert_only("probe selection-rex: status")

    def test_second_display_may_be_na_with_a_reason(self):
        self.named("second-display").update(status="na", reason="no second display on the test Mac",
                                            environment="", procedure="", outcome="", cleanup={"status": ""})
        self.assertEqual(self.problems(), [])

    def test_na_without_a_reason_is_rejected(self):
        self.named("second-display").update(status="na", reason=" ")
        self.assert_only("probe second-display: N/A needs a reason")

    def test_probe_for_another_candidate_is_rejected(self):
        for field, value in (("commit", OTHER), ("bundle_digest", "0" * 64)):
            with self.subTest(field=field):
                original = self.named("voice-accepted")[field]
                self.named("voice-accepted")[field] = value
                self.assert_only(f"probe voice-accepted: {field}")
                self.named("voice-accepted")[field] = original

    def test_missing_or_blank_record_field_is_rejected(self):
        for field in ("environment", "procedure", "outcome", "time"):
            with self.subTest(field=field):
                original = self.named("first-install")[field]
                self.named("first-install")[field] = ""
                self.assert_only(f"probe first-install: {field}")
                self.named("first-install")[field] = original

    def test_time_without_a_zone_or_outside_the_candidate_is_rejected(self):
        # Before the build, and after now.
        for time in ("2026-11-25T10:00:00", "2026-11-25T08:59:00+01:00", "2026-11-27T00:00:00Z"):
            with self.subTest(time=time):
                self.named("first-install")["time"] = time
                self.assert_only("probe first-install: time")

    def test_time_may_equal_the_build_time_and_now(self):
        for time in (BUILT, NOW.isoformat()):
            self.named("first-install")["time"] = time
            self.assertEqual(self.problems(), [])

    def test_missing_cleanup_is_rejected(self):
        del self.named("first-install")["cleanup"]
        self.assert_only("probe first-install: cleanup")

    def test_retained_resource_needs_an_owner_and_next_action(self):
        whole = {"status": "retained", "owner": "Juan", "next_action": "remove the Desktop backup"}
        for field in ("owner", "next_action"):
            self.named("first-install")["cleanup"] = {**whole, field: " "}
            self.assert_only("probe first-install: cleanup")
        self.named("first-install")["cleanup"] = whole
        self.assertEqual(self.problems(), [])

    def test_nothing_allocated_is_complete_cleanup(self):
        self.named("first-install")["cleanup"] = {"status": "nothing-allocated"}
        self.assertEqual(self.problems(), [])

    def test_unknown_probe_is_rejected(self):
        self.evidence["probes"].append(self.probe("selection-rx", self.evidence["candidate"]["bundle_digest"]))
        self.assert_only("probe selection-rx: not a required probe")

    def test_duplicate_probe_cannot_hide_a_failure(self):
        failed = copy.deepcopy(self.named("selection-rex"))
        failed["status"] = "fail"
        self.evidence["probes"].insert(0, failed)
        self.assertEqual(self.problems(), ["probe selection-rex: recorded more than once",
                                           "probe selection-rex: status fail"])


class Charter(GateCase):
    def finding(self, **changes):
        item = {"id": "F1", "severity": "S3", "disposition": "known-issue", "reason": "the Stop button works",
                "approved_by": "Juan", "approved_on": "2026-11-25"}
        item.update(changes)
        self.evidence["charter"]["findings"] = [item]
        return item

    def repaired(self, **changes):
        """The charter ran on an earlier build, and its finding was repaired and checked again."""
        self.evidence["charter"].update(commit=self.earlier, bundle_digest="0" * 64, time="2026-11-21T10:00:00Z")
        verified = {**self.evidence["candidate"], "status": "pass", "procedure": "repeated the crash steps",
                    "outcome": "no crash", "time": RAN}
        verified.update(changes)
        return self.finding(severity="S1", disposition="repaired", reason="fixed the crash", verified=verified)

    def maneuver(self, name):
        return next(m for m in self.evidence["charter"]["maneuvers"] if m["id"] == name)

    def test_missing_charter_is_rejected(self):
        del self.evidence["charter"]
        self.assert_only("charter: missing")

    def test_incomplete_charter_record_is_rejected(self):
        for field, value, expected in (
                ("independent", "yes", "charter: not independent"), ("author", " ", "charter: author"),
                ("environment", "", "charter: environment"), ("procedure", "", "charter: procedure"),
                ("time", "soon", "charter: time"), ("time", "2026-11-27T00:00:00Z", "charter: time"),
                ("time", "2026-11-25T07:00:00Z", "charter: time"), ("cleanup", {"status": "unknown"}, "charter: cleanup"),
                ("findings", {}, "charter: findings"), ("findings", ["x"], "charter: findings"),
                ("commit", OTHER[:7], "charter: commit"), ("bundle_digest", "0" * 63, "charter: bundle_digest"),
                ("bundle_digest", "0" * 65, "charter: bundle_digest"), ("commit", OTHER + "0", "charter: commit"),
                ("maneuvers", [*self.evidence["charter"]["maneuvers"], "x"], "charter: maneuvers")):
            with self.subTest(field=field, value=value):
                original = self.evidence["charter"][field]
                self.evidence["charter"][field] = value
                found = self.problems()
                # A malformed build also cannot be the candidate's, so only these two add a second problem.
                self.assertEqual(len(found), 1 if field not in ("commit", "bundle_digest") else len(found), found)
                self.assertTrue(any(problem.startswith(expected) for problem in found), found)
                self.evidence["charter"][field] = original

    def test_missing_maneuver_is_rejected(self):
        self.evidence["charter"]["maneuvers"].pop()
        self.assert_only(f"charter maneuver {gate.MANEUVERS[-1]}: missing")

    def test_charter_with_no_passing_maneuver_is_rejected(self):
        self.finding()
        for maneuver in self.evidence["charter"]["maneuvers"]:
            maneuver.update(status="fail", finding="F1")
        self.assert_only("charter: no maneuver passed")

    def test_empty_records_are_not_skipped(self):
        self.evidence["charter"]["findings"] = [{}]
        self.assertEqual(self.problems(), [
            "finding None: ID is missing or recorded more than once", "finding None: severity is not S1 to S4",
            "finding None: reason is missing",
            "finding None: disposition is not repaired, known-issue or rejected"])
        self.evidence["charter"]["findings"] = []
        self.evidence["charter"]["maneuvers"].append({})
        self.assert_only("charter maneuver None: not a required maneuver")

    def test_skipped_maneuver_is_rejected(self):
        self.maneuver("interruption")["status"] = "skip"
        self.assert_only("charter maneuver interruption: status skip")

    def test_passed_or_failed_maneuver_needs_an_outcome(self):
        self.maneuver("interruption")["outcome"] = ""
        self.assert_only("charter maneuver interruption: outcome")
        self.finding()
        self.maneuver("interruption").update(status="fail", finding="F1")
        self.assert_only("charter maneuver interruption: outcome")

    def test_failed_maneuver_needs_an_open_question_answered(self):
        self.maneuver("interruption")["status"] = "fail"
        self.assert_only("charter maneuver interruption: failed and names no recorded finding")
        self.maneuver("interruption")["finding"] = ["F1"]
        self.assert_only("charter maneuver interruption: failed and names no recorded finding")
        self.maneuver("interruption")["finding"] = "F1"
        self.finding(id="F2")
        self.assert_only("charter maneuver interruption: failed and names no recorded finding")
        self.finding()
        self.assertEqual(self.problems(), [])

    def test_rejected_finding_cannot_explain_a_failed_maneuver(self):
        self.maneuver("interruption").update(status="fail", finding="F1")
        self.finding(severity="S1", disposition="rejected", reason="not reproducible")
        self.assert_only("charter maneuver interruption: failed, but finding F1 is rejected")

    def test_na_is_limited_and_needs_a_reason(self):
        self.maneuver("downstream-state").update(status="na", outcome="")
        self.assert_only("charter maneuver downstream-state: N/A needs a reason")
        self.maneuver("downstream-state")["reason"] = "Cáptalo writes no data that another app reads"
        self.assertEqual(self.problems(), [])
        for name in ("interruption", "locale-or-device-change"):
            self.maneuver(name).update(status="na", reason="not applicable")
            self.assert_only(f"charter maneuver {name}: status na")
            self.maneuver(name)["status"] = "pass"

    def test_high_severity_cannot_be_a_known_issue(self):
        for severity in ("S1", "S2"):
            with self.subTest(severity=severity):
                self.finding(severity=severity)
                self.assert_only("F1: S1 and S2")

    def test_low_severity_known_issue_needs_owner_approval(self):
        for severity in ("S3", "S4"):
            for changes in ({"approved_by": " "}, {"approved_by": True}, {"approved_on": ""}, {"approved_on": True},
                            {"approved_on": "9999-99-99"}, {"approved_on": "2099-01-01"}):
                self.finding(severity=severity, **changes)
                self.assert_only("F1: known issue needs approved_by")
            self.finding(severity=severity)
            self.assertEqual(self.problems(), [])

    def test_rejected_finding_with_a_reason_is_accepted(self):
        self.finding(disposition="rejected", reason="the fixture was wrong: see log")
        self.assertEqual(self.problems(), [])

    def test_unclassified_finding_is_rejected(self):
        self.finding(severity="minor", disposition="rejected")
        self.assert_only("F1: severity")

    def test_finding_without_a_reason_or_disposition_is_rejected(self):
        self.finding(reason="")
        self.assert_only("F1: reason")
        self.finding(disposition="open")
        self.assert_only("F1: disposition")

    def test_finding_without_its_own_id_is_rejected(self):
        item = self.finding()
        self.evidence["charter"]["findings"] = [item, dict(item)]
        self.assert_only("finding F1: ID is missing or recorded more than once")
        self.finding(id="")
        self.assert_only("ID is missing")

    def test_verified_repair_after_the_charter_is_accepted(self):
        self.repaired()
        self.assertEqual(self.problems(), [])

    def test_repair_needs_its_own_passing_check_on_the_candidate(self):
        for changes in ({"commit": OTHER}, {"bundle_digest": "0" * 64}, {"status": "fail"}, {"status": None},
                        {"procedure": ""}, {"outcome": ""}, {"time": "2026-11-25T07:00:00Z"}):
            with self.subTest(changes=changes):
                self.repaired(**changes)
                self.assert_only("F1: repair is not verified on this candidate")

    def test_charter_on_the_candidate_cannot_have_a_repair_in_it(self):
        self.repaired()
        self.evidence["charter"].update(self.evidence["candidate"], time=RAN)
        self.assert_only("F1: a repair needs a charter on an earlier build")

    def test_moved_charter_must_be_on_an_earlier_commit_of_the_candidate(self):
        git(self.repo, "checkout", "-q", "--orphan", "unrelated")
        git(self.repo, "commit", "-q", "-m", "unrelated")
        unrelated = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "checkout", "-q", "--detach", self.commit)
        for commit in (OTHER, unrelated):
            with self.subTest(commit=commit):
                self.repaired()
                self.evidence["charter"]["commit"] = commit
                self.assert_only("charter: commit is not an earlier commit of the candidate")

    def test_moved_charter_ran_between_its_commit_and_the_candidate_build(self):
        for time in ("2026-11-20T11:59:59Z", "2026-11-25T08:00:01Z"):
            with self.subTest(time=time):
                self.repaired()
                self.evidence["charter"]["time"] = time
                self.assert_only("charter: time")
        for time in ("2026-11-20T12:00:00Z", BUILT):
            self.repaired()
            self.evidence["charter"]["time"] = time
            self.assertEqual(self.problems(), [])

    def test_charter_on_an_earlier_build_needs_a_repair(self):
        self.evidence["charter"].update(commit=self.earlier, bundle_digest="0" * 64, time="2026-11-21T10:00:00Z")
        self.assert_only("charter: ran on another build")

    def test_charter_without_a_build_is_rejected(self):
        for field in ("commit", "bundle_digest"):
            with self.subTest(field=field):
                self.repaired()
                del self.evidence["charter"][field]
                self.assertIn(f"charter: {field} is missing or malformed", self.problems())

    def test_charter_on_another_bundle_of_the_same_commit_is_rejected(self):
        self.evidence["charter"]["bundle_digest"] = "0" * 64
        self.assert_only("charter: ran on another bundle of the candidate commit")


class Malformed(GateCase):
    def test_wrong_schema_version_is_rejected(self):
        for version in (2, True, "1", None):
            with self.subTest(version=version):
                self.evidence["schema_version"] = version
                self.assert_only("schema_version")

    def test_unknown_top_level_key_is_rejected(self):
        self.evidence["findings"] = [{"id": "F9", "severity": "S1", "disposition": "open"}]
        self.assert_only("unknown key findings")

    def test_wrong_shapes_are_problems_not_crashes(self):
        for key, value, expected in (
                ("candidate", [], "candidate commit is not"), ("probes", {}, "no probe passed"),
                ("probes", ["x"], "no probe passed"), ("charter", "done", "charter: missing"),
                ("charter", {"findings": "none", "maneuvers": 3}, "charter: findings")):
            with self.subTest(key=key, value=value):
                broken = copy.deepcopy(self.evidence)
                broken[key] = value
                found = gate.analyze(broken, self.receipt, self.repo, self.app, NOW)
                self.assertTrue(any(p.startswith(expected) for p in found), found)

    def test_receipt_that_is_not_an_object_is_a_problem(self):
        for receipt in ([], None, {"checks": "x"}):
            with self.subTest(receipt=receipt):
                found = gate.analyze(self.evidence, receipt, self.repo, self.app, NOW)
                self.assertIn("the verification suite did not pass", found)
                self.assertIn("check core: missing", found)

    def test_unhashable_id_is_a_problem_not_a_crash(self):
        self.named("selection-rex")["id"] = ["selection-rex"]
        self.assertEqual(self.problems(), ["probe ['selection-rex']: not a required probe",
                                           "probe selection-rex: missing"])


class CommandLine(GateCase):
    def run_script(self, command="check", text=None, env=None):
        evidence, receipt = self.dir / "evidence.json", self.dir / "verification.json"
        evidence.write_text(json.dumps(self.evidence) if text is None else text)
        receipt.write_text(json.dumps(self.receipt))
        arguments = [command, "--app", str(self.app)]
        if command == "check":
            arguments += ["--evidence", str(evidence), "--verification", str(receipt), "--repo", str(self.repo)]
        return subprocess.run([str(SCRIPT), *arguments], capture_output=True, text=True, env={**os.environ, **(env or {})})

    def test_complete_evidence_passes_and_a_gap_blocks(self):
        # Times on the command line are compared with the real clock.
        self.write_build_info(built_at="2020-01-01T00:00:00Z")
        digest = gate.bundle_digest(self.app)
        for record in (self.evidence["candidate"], self.evidence["charter"], *self.evidence["probes"]):
            record["bundle_digest"] = digest
            record["time"] = "2020-01-02T00:00:00Z"
        del self.evidence["candidate"]["time"]
        passed = self.run_script()
        self.assertEqual((passed.returncode, passed.stderr), (0, ""))
        self.assertIn(f"PASS: {len(gate.REQUIRED_PROBES)} probes", passed.stdout)
        # The checkout is the one named on the command line, also inside a Git hook.
        self.assertEqual(self.run_script(env={"GIT_DIR": str(self.dir / "elsewhere")}).returncode, 0)
        self.named("selection-rex")["status"] = "skip"
        blocked = self.run_script()
        self.assertEqual(blocked.returncode, 1)
        self.assertEqual(blocked.stderr, "BLOCKED: 1 problem\n  probe selection-rex: status skip\n")

    def test_unreadable_input_is_not_a_result(self):
        text = json.dumps(self.evidence)
        for label, value, expected in (
                ("not JSON", "{", "evidence.json"), ("duplicate key", text[:-1] + ', "probes": []}', "duplicate key"),
                ("too deep", "[" * 200_000, "evidence.json")):
            with self.subTest(label=label):
                result = self.run_script(text=value)
                self.assertEqual(result.returncode, 2, result.stderr[-300:])
                self.assertIn(expected, result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_checkout_or_bundle_that_cannot_be_read_is_not_a_result(self):
        (self.app / "Contents" / "MacOS" / "Captalo").chmod(0)
        unreadable = self.run_script()
        self.assertEqual(unreadable.returncode, 2, unreadable.stderr)
        (self.app / "Contents" / "MacOS" / "Captalo").chmod(0o644)
        (self.repo / ".git").rename(self.repo / "not-git")
        outside = self.run_script()
        self.assertEqual(outside.returncode, 2, outside.stderr)
        self.assertNotIn("Traceback", unreadable.stderr + outside.stderr)

    def test_defaults_are_this_checkout(self):
        options = gate.parse(["check", "--app", "a", "--evidence", "e"])
        self.assertEqual((options.repo, options.verification), (ROOT, ROOT / ".rpi" / "local" / "verification.json"))

    def test_missing_build_info_is_not_a_result(self):
        self.build_info.unlink()
        for command in ("check", "template"):
            result = self.run_script(command)
            self.assertEqual(result.returncode, 2)
            self.assertIn("build-info.json", result.stderr)

    def test_template_is_bound_and_blocked_until_it_is_filled_in(self):
        made = self.run_script("template")
        self.assertEqual(made.returncode, 0, made.stderr)
        self.evidence = json.loads(made.stdout)
        candidate = {"commit": self.commit, "bundle_digest": gate.bundle_digest(self.app)}
        self.assertEqual(self.evidence["candidate"], candidate)
        for record in (self.evidence["charter"], *self.evidence["probes"]):
            self.assertEqual({key: record[key] for key in candidate}, candidate)
        found = self.problems()
        blank = [f"probe {name}: {gap}" for name in gate.REQUIRED_PROBES for gap in
                 ("status not-run", "environment is missing", "procedure is missing", "outcome is missing")]
        blank += [f"charter maneuver {name}: status not-run" for name in gate.MANEUVERS]
        blank += ["no probe passed", "charter: no maneuver passed", "charter: not independent", "charter: author is missing"]
        self.assertEqual([problem for problem in blank if problem not in found], [])
        for label in ("charter", *(f"probe {name}" for name in gate.REQUIRED_PROBES)):
            self.assertIn(f"{label}: cleanup is missing or incomplete", found)


if __name__ == "__main__":
    unittest.main()
