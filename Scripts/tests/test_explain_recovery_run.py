import concurrent.futures
import hashlib
import json
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/explain-qualification-run"


def wire(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


class RecoveryRunTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.runner = runpy.run_path(str(SCRIPT))
        fixture = self.root / "Tests/ExplainQualification"
        shutil.copytree(ROOT / "Tests/ExplainQualification", fixture)
        (fixture / "RECOVERY-REVIEW.md").write_text("Synthetic guide")
        cases = json.loads((fixture / "cases.json").read_bytes()) + json.loads((fixture / "held-out.json").read_bytes())
        fixture_hash = sha((fixture / "manifest.json").read_bytes())
        configs = self.root / "Qualification/Explain/candidates"
        configs.mkdir(parents=True)
        for name in ("openai", "openai-selected", "openai-example"):
            body = wire(dict(model="gpt-6.1-terra", stream=True, store=False, service_tier="default",
                             reasoning={"effort": "none"}, instructions=name, input="synthetic", max_output_tokens=4096))
            rows = [{"id": case["id"], "body": body.decode()} for case in cases if case["suite"] != "learner-blocked"]
            config = dict(provider="openai", model="gpt-6.1-terra", fixtures_sha256=fixture_hash,
                          request_set_sha256=sha(wire(rows)))
            if name != "openai":
                config["request_sha256"] = {r["id"]: sha(r["body"].encode()) for r in rows}
            config_path = configs / (name + ".json")
            config_path.write_bytes(wire(config))
            prepared = {k: config[k] for k in ("provider", "model", "fixtures_sha256")}
            prepared.update(configuration_sha256=sha(config_path.read_bytes()), requests=rows)
            directory = self.root / ".local/explain-qualification" / name
            directory.mkdir(parents=True)
            (directory / "prepared.json").write_bytes(wire(prepared))
        self.dispatch = self.runner["recovery_run"]
        self.approval = self.runner["recovery_manifest"](self.root)

    def status(self):
        return self.runner["recovery_status"](self.root)

    def send(self, provider, model, body):
        return "Synthetic.", model

    def test_fixed_arms_have_distinct_identity_and_stale_approval_fails(self):
        arms = ["control", "selected", "example", "selected-full", "example-full"]
        identities = [self.runner["recovery_context"](self.root, arm)[1] for arm in arms]
        self.assertEqual(len({identity["run_sha256"] for identity in identities}), 5)
        self.assertEqual(len({identity["subset_sha256"] for identity in identities}), 2)
        for approval in (None, dict(self.approval, max_requests=100), dict(self.approval, max_usd="2.99")):
            with self.assertRaisesRegex(ValueError, "approval"):
                self.dispatch(self.root, "control", approval, self.fail)
        (self.root / "Tests/ExplainQualification/RECOVERY-REVIEW.md").write_text("new guide")
        with self.assertRaisesRegex(ValueError, "approval"):
            self.dispatch(self.root, "control", self.approval, self.fail)
        self.assertEqual(self.status()["reserved_requests"], 0)

    def test_concurrent_control_starts_have_one_winner(self):
        calls = []
        def send(*args):
            calls.append(1)
            return self.send(*args)
        def start():
            try:
                self.dispatch(self.root, "control", self.approval, send)
                return True
            except ValueError:
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            self.assertCountEqual(list(pool.map(lambda _: start(), range(2))), [False, True])
        self.assertEqual(len(calls), 6)
        status = self.status()
        self.assertEqual(status["reserved_requests"], 6)
        self.assertEqual(status["runs"]["control"]["state"], "complete")

    def test_crashes_leave_whole_reservation_and_disclose_next_action(self):
        def crash(*args):
            raise KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt):
            self.dispatch(self.root, "control", self.approval, crash)
        current = self.status()
        self.assertEqual(current["reserved_requests"], 6)
        self.assertEqual(current["runs"]["control"]["state"], "incomplete")
        self.assertEqual(current["runs"]["control"]["last_attempt"], "main-email-middle-metaphors")
        self.assertIn("decision", current["runs"]["control"]["recovery"])
        for arm in ("control", "selected"):
            with self.assertRaisesRegex(ValueError, "incomplete|already reserved"):
                self.dispatch(self.root, arm, self.approval, self.fail)

    def test_stale_bytes_outside_pilot_fail_before_send(self):
        path = self.root / ".local/explain-qualification/openai/prepared.json"
        prepared = json.loads(path.read_bytes())
        prepared["requests"][-1]["body"] += " "
        path.write_bytes(wire(prepared))
        with self.assertRaisesRegex(ValueError, "identity|digest"):
            self.dispatch(self.root, "control", self.approval, self.fail)
        self.assertEqual(self.status()["reserved_requests"], 0)

    def test_optimized_mode_and_invalid_flags_refuse_execute_before_any_send(self):
        result = subprocess.run([sys.executable, "-O", str(SCRIPT), "openai", "--recovery-arm", "control",
                                 "--execute"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("optimized", result.stderr)
        for args in (["openai", "--recovery-preview", "--execute"], ["anthropic", "--recovery-status"]):
            result = subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)

    def test_after_reservation_before_attempt_crash_discloses_zero_progress(self):
        with patch.dict(self.dispatch.__globals__, {"dispatch": lambda *args: sys.exit(3)}):
            with self.assertRaises(SystemExit):
                self.dispatch(self.root, "control", self.approval, self.fail)
        status = self.status()
        self.assertEqual(status["reserved_requests"], 6)
        self.assertIsNone(status["runs"]["control"]["last_attempt"])
        self.assertEqual(status["runs"]["control"]["completed_cases"], [])
        with self.assertRaisesRegex(ValueError, "already reserved"):
            self.dispatch(self.root, "control", self.approval, self.fail)

    def test_sent_answer_lost_before_flush_is_charged_once(self):
        sends = []
        record = self.runner["append_record"]
        def interrupt(file, row):
            if file.name.endswith("answers.jsonl"):
                raise KeyboardInterrupt()
            record(file, row)
        def send(*args):
            sends.append(1)
            return self.send(*args)
        with patch.dict(self.dispatch.__globals__, {"append_record": interrupt}), self.assertRaises(KeyboardInterrupt):
            self.dispatch(self.root, "control", self.approval, send)
        self.assertEqual(sends, [1])
        self.assertEqual(self.status()["reserved_requests"], 6)
        self.assertEqual(self.status()["runs"]["control"]["completed_cases"], [])
        with self.assertRaisesRegex(ValueError, "already reserved"):
            self.dispatch(self.root, "control", self.approval, self.fail)

    def test_mismatched_model_never_writes_complete_marker(self):
        with self.assertRaisesRegex(ValueError, "stopped"):
            self.dispatch(self.root, "control", self.approval, lambda *_: ("Blue.", "other-model"))
        self.assertEqual(self.status()["runs"]["control"]["state"], "incomplete")

    def test_full_and_pilot_requests_exceeding_unit_price_cap_never_reserve(self):
        from decimal import Decimal
        context = self.dispatch.__globals__
        for unit, first_miss in [("0.05", "control"), ("0.03", "selected-full")]:
            with patch.dict(context, {"price_bound": lambda *_: Decimal(unit)}):
                with self.assertRaisesRegex(ValueError, first_miss + " exceeds its USD ceiling"):
                    self.dispatch(self.root, "control", self.approval, self.fail)
        self.assertEqual(self.status()["reserved_requests"], 0)

    def test_aggregate_reservation_enforces_both_limits(self):
        from decimal import Decimal
        context = self.dispatch.__globals__
        # Exercise the in-lock cumulative check using a smaller approved experiment.
        for ceiling in ({"max_requests": 5}, {"max_usd": str(Decimal("0.001"))}):
            envelope = {**self.approval, **ceiling}
            with patch.dict(context, {"recovery_manifest": lambda _: envelope}):
                with self.assertRaisesRegex(ValueError, "aggregate"):
                    self.dispatch(self.root, "control", envelope, self.fail)
            self.assertEqual(self.status()["reserved_requests"], 0)

    def test_legacy_control_evidence_never_counts_as_a_new_occurrence(self):
        path = self.root / ".local/explain-qualification/openai/tuning/historical"
        path.mkdir(parents=True)
        (path / "complete.json").write_text("historical")
        with self.assertRaisesRegex(ValueError, "sequence"):
            self.dispatch(self.root, "selected", self.approval, self.fail)
        self.dispatch(self.root, "control", self.approval, self.send)
        self.dispatch(self.root, "selected", self.approval, self.send)
        self.assertEqual((path / "complete.json").read_text(), "historical")
        self.assertEqual(self.status()["reserved_requests"], 12)

    def test_learner_or_reordered_heldout_cohort_is_rejected_even_if_refrozen(self):
        path = self.root / ".local/explain-qualification/openai/prepared.json"
        config_path = self.root / "Qualification/Explain/candidates/openai.json"
        prepared, config = json.loads(path.read_bytes()), json.loads(config_path.read_bytes())
        heldout = json.loads((self.root / "Tests/ExplainQualification/held-out.json").read_bytes())
        prepared["requests"][-1]["id"] = next(c["id"] for c in heldout if c["suite"] == "learner-blocked")
        config["request_set_sha256"] = sha(wire(prepared["requests"]))
        config_path.write_bytes(wire(config))
        prepared["configuration_sha256"] = sha(config_path.read_bytes())
        path.write_bytes(wire(prepared))
        with self.assertRaisesRegex(ValueError, "cohort"):
            self.dispatch(self.root, "control", self.approval, self.fail)
        self.assertEqual(self.status()["reserved_requests"], 0)

    def test_named_treatments_must_bind_every_individual_request(self):
        config_path = self.root / "Qualification/Explain/candidates/openai-selected.json"
        prepared_path = self.root / ".local/explain-qualification/openai-selected/prepared.json"
        config = json.loads(config_path.read_bytes())
        config.pop("request_sha256", None)
        config_path.write_bytes(wire(config))
        prepared = json.loads(prepared_path.read_bytes())
        prepared["configuration_sha256"] = sha(config_path.read_bytes())
        prepared_path.write_bytes(wire(prepared))
        with self.assertRaisesRegex(ValueError, "individual"):
            self.runner["recovery_manifest"](self.root)

    def test_partial_completion_record_discloses_last_case_and_blocks_later_arm(self):
        path = self.dispatch(self.root, "control", self.approval, self.send)
        (path / "complete.json").write_text("{")
        run = self.status()["runs"]["control"]
        self.assertEqual(run["state"], "incomplete")
        self.assertEqual(len(run["completed_cases"]), 6)
        self.assertIn("complete.json", run["recovery"])
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.dispatch(self.root, "selected", self.approval, self.fail)

    def test_damaged_prior_run_prevents_next_reservation(self):
        path = self.dispatch(self.root, "control", self.approval, self.send)
        original = {p.name: p.read_bytes() for p in path.iterdir()}
        for damage in ("missing-auth", "wrong-auth-cap", "missing-model", "bad-attempt", "wrong-wire",
                       "wrong-answer-model", "bad-stop", "stale-answer-digest", "wrong-answer-id"):
            with self.subTest(damage=damage):
                if damage == "missing-auth":
                    (path / "authorization.json").unlink()
                elif damage == "wrong-auth-cap":
                    auth = json.loads(original["authorization.json"])
                    (path / "authorization.json").write_bytes(wire(dict(auth, max_usd="9")))
                elif damage == "missing-model":
                    complete = json.loads(original["complete.json"])
                    del complete["model"]
                    (path / "complete.json").write_bytes(wire(complete))
                elif damage == "bad-attempt":
                    attempts = [json.loads(l) for l in original["attempts.jsonl"].splitlines()]
                    attempts[0]["request_sha256"] = "a" * 64
                    (path / "attempts.jsonl").write_bytes(b"".join(wire(r) + b"\n" for r in attempts))
                else:
                    answers = [json.loads(l) for l in original["answers.jsonl"].splitlines()]
                    field, value = {"wrong-wire": ("request_sha256", "b" * 64),
                                    "wrong-answer-model": ("observed_model", "other-model"),
                                    "bad-stop": ("natural_stop", False),
                                    "stale-answer-digest": ("answer_sha256", "c" * 64),
                                    "wrong-answer-id": ("id", "other-case")}[damage]
                    answers[0][field] = value
                    raw = b"".join(wire(r) + b"\n" for r in answers)
                    (path / "answers.jsonl").write_bytes(raw)
                    complete = json.loads(original["complete.json"])
                    (path / "complete.json").write_bytes(wire(dict(complete, answers_sha256=sha(raw))))
                with self.assertRaisesRegex(ValueError, "incomplete|inconsistent|missing|differs"):
                    self.dispatch(self.root, "selected", self.approval, self.fail)
                self.assertEqual(self.status()["reserved_requests"], 6)
                for name, content in original.items():
                    (path / name).write_bytes(content)
        self.dispatch(self.root, "selected", self.approval, self.send)
        self.assertEqual(self.status()["reserved_requests"], 12)

    def test_torn_attempt_record_discloses_last_known_case_and_full_reservation(self):
        path = self.dispatch(self.root, "control", self.approval, self.send)
        attempts = (path / "attempts.jsonl").read_bytes().splitlines()
        (path / "attempts.jsonl").write_bytes(attempts[0] + b"\n" + b'{"id":')
        info = self.status()
        self.assertEqual(info["reserved_requests"], 6)
        run = info["runs"]["control"]
        self.assertEqual(run["state"], "incomplete")
        self.assertEqual(run["last_attempt"], "main-email-middle-metaphors")
        self.assertIn("attempts.jsonl", run["recovery"])
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.dispatch(self.root, "selected", self.approval, self.fail)
