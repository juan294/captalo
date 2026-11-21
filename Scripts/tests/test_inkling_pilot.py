"""Weight-free checks for the frozen six-case local experiment."""
import copy
import json
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PILOT = runpy.run_path(str(ROOT / "Scripts/explain-inkling-pilot"))


class InputTests(unittest.TestCase):
    def setUp(self):
        self.raw = json.dumps({"instructions": "Explain literally.", "input": '{"source":"Ends here."}'})
        self.rows = [{"id": "short", "body": self.raw}, {"id": "long", "body": self.raw}]
        self.refs = [{"id": row["id"], "base_request_sha256": PILOT["sha"](self.raw.encode())} for row in self.rows]

    def test_wire_selection_and_contamination(self):
        select = PILOT["select_rows"]
        self.assertEqual(select(self.rows, self.refs), self.rows)
        for altered in [self.rows[::-1], self.rows + self.rows[:1], self.rows[:1],
                        [self.rows[0], dict(self.rows[1], body=self.raw[:-5])]]:
            with self.assertRaises(ValueError):
                select(altered, self.refs)

    def test_exact_two_messages_and_effort(self):
        body = json.loads(self.raw)
        messages = PILOT["messages"](dict(body, facts=["never reveal"], id="hidden"))
        self.assertEqual(messages, [{"role": "system", "content": body["instructions"]},
                                    {"role": "user", "content": body["input"]}])
        text = PILOT["expected_render"](body)
        self.assertIn("Thinking effort level: 0<|end_message|>", text)
        for bad in [text.replace("level: 0", "level: 0.9"), text.replace("message_user", "message_system"),
                    text.replace("Ends here.", ""), text + "never reveal"]:
            with self.assertRaises(ValueError):
                PILOT["check_render"](body, bad)

    def test_asset_repair(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture"
            expected = PILOT["sha"](b"OK")
            for damaged in [None, b"O"]:
                if damaged:
                    path.write_bytes(damaged)
                with self.assertRaisesRegex(ValueError, expected):
                    PILOT["check_file"](path, expected)
            path.write_bytes(b"OK")
            PILOT["check_file"](path, expected)


class StreamTests(unittest.TestCase):
    def parse(self, events, stop="eof"):
        return PILOT["observe"]([(i, text, n) for n, (i, text) in enumerate(events, 1)], stop)

    def test_reasoning_is_silent_and_token_ids_define_control(self):
        result = self.parse([(200001, ""), (200008, ""), (23, "Secret."), (200010, ""),
                             (200001, ""), (200004, ""), (24, "Dr. "), (25, "A paid 2."),
                             (26, "5 today."), (27, " More <|content_thinking|>."), (200010, ""), (200006, "")])
        self.assertEqual(result["answer"], "Dr. A paid 2.5 today. More <|content_thinking|>.")
        self.assertEqual((result["reasoning_tokens"], result["first_sentence"], result["status"]), (1, 10, "eos"))
        self.assertNotIn("Secret", str(result))

    def test_natural_stop_cap_and_invalid_channel(self):
        final = [(200001, ""), (200004, ""), (10, "Answer."), (200010, "")]
        self.assertEqual(self.parse(final + [(200006, "")])["first_sentence"], 5)
        for stop in ["eof", "cap", "timeout"]:
            self.assertEqual(self.parse(final, stop)["status"], stop)
        for wrong in [[(200001, ""), (200008, ""), (10, "hidden"), (200010, ""), (200006, "")],
                      [(200001, ""), (200024, ""), (10, "tool"), (200006, "")]]:
            self.assertNotEqual(self.parse(wrong)["status"], "eos")
            self.assertEqual(self.parse(wrong)["answer"], "")


class ReviewTests(unittest.TestCase):
    def test_all_six_and_controls_and_stale_votes(self):
        rehearse = PILOT["rehearse"]
        self.assertEqual(rehearse()["outcome"], "next-gate")
        for fault, expected in [("refusal", "quality-miss"), ("cap", "quality-miss"),
                                ("late", "latency-hold"), ("missing-time", "incomplete")]:
            with self.subTest(fault=fault):
                self.assertEqual(rehearse(fault)["outcome"], expected)
        for fault in ["stale-vote", "duplicate-vote", "missing-vote", "missing-adjudication"]:
            with self.assertRaises(ValueError):
                rehearse(fault)
        self.assertEqual(rehearse("adjudication")["outcome"], "next-gate")


class RecoveryTests(unittest.TestCase):
    def test_failed_setup_discloses_the_fix_and_recovered_setup_reserves_once(self):
        ready = {"runtime": "pinned", "voice_ready": True, "local_control": 0, "denied_control": -9}
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "attempts"
            for field, bad, fix in [("runtime", "other", "runtime"), ("voice_ready", False, "voice"),
                                    ("local_control", 1, "sandbox"), ("denied_control", 0, "sandbox")]:
                with self.assertRaisesRegex(ValueError, fix):
                    PILOT["reserve_run"](run, dict(ready, **{field: bad}), "pinned")
                self.assertFalse(run.exists())
            PILOT["reserve_run"](run, ready, "pinned")
            # A kill after reservation leaves an identifiable, non-overwritable run.
            with self.assertRaisesRegex(ValueError, "incomplete"):
                PILOT["reserve_run"](run, ready, "pinned")
            self.assertTrue(run.is_dir())

    def test_timing_requires_six_valid_observations(self):
        six = [{"source_words": n, "first_sentence_seconds": 1.5, "rss_peak_bytes": 10,
                "mlx_peak_bytes": 8} for n in [33, 40, 46, 31, 32, 3000]]
        summary = PILOT["performance"]
        self.assertEqual(summary(six, load_seconds=1.5), "next-gate")
        self.assertEqual(summary(six, load_seconds=1.6), "latency-hold")
        self.assertEqual(summary(six[:-1], load_seconds=0), "incomplete")
        for field in ["first_sentence_seconds", "rss_peak_bytes", "mlx_peak_bytes"]:
            altered = copy.deepcopy(six)
            del altered[-1][field]
            self.assertEqual(summary(altered, load_seconds=0), "incomplete")

    def test_unpunctuated_eos_gives_no_sentence_timestamp(self):
        events = [(200001, "", 0), (200004, "", 1), (10, "A fragment", 2), (200010, "", 3), (200006, "", 4)]
        self.assertIsNone(PILOT["observe"](events, "eof")["first_sentence"])

    def test_confirmed_quality_miss_survives_missing_timing(self):
        self.assertEqual(PILOT["rehearse"]("miss-and-missing-time")["outcome"], "quality-miss")

    def test_unobserved_eos_and_empty_sentence_are_not_evidence(self):
        with self.assertRaisesRegex(ValueError, "EOS"):
            PILOT["observe"]([], "eos")
        for fragment in ["...", "---", "Mr.", "Wait for"]:
            result = PILOT["observe"]([(200001, "", 1), (200004, "", 2), (9, fragment, 3),
                                       (200010, "", 4), (200006, "", 5)], "eof")
            self.assertIsNone(result["first_sentence"])
