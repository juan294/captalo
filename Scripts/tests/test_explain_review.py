import copy
import hashlib
import json
from pathlib import Path
import runpy
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "explain-qualification-review"
SOURCE = "Three boats will cross the lake tomorrow, provided the wind remains calm."
ANSWER = "Three boats cross tomorrow if the wind stays calm."


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


class BlindReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tool = runpy.run_path(str(SCRIPT))

    def setUp(self):
        self.case = {"id": "boat-middle", "fixture": "lake", "suite": "corpus",
                     "depth": "middle", "style": "plain", "profile": "New to sailing."}
        self.result = {"id": self.case["id"], "answer": ANSWER, "observed_model": "test-only",
                       "answer_sha256": sha(ANSWER), "natural_stop": True, "request_sha256": sha("wire")}
        self.fixture = ([self.case], {"lake": SOURCE}, {"lake": ["Three boats", "wind condition"]}, sha("fixture"))
        self.answers = {self.case["id"]: self.result}
        self.packet, self.key = self.tool["blind_packet"](self.fixture, self.answers)
        self.item = self.packet["items"][0]
        self.verdict = {k: self.item[k] for k in ("label", "answer_sha256", "item_sha256")}
        self.verdict.update(verdict="pass", covered_facts=[0, 1], missing_facts=[], near_verbatim=False,
                            ambiguous=False, reason="")

    def receipt(self):
        return self.tool["make_receipt"](self.fixture, self.answers, self.packet, self.key,
                                         [self.verdict], sha("test config"))

    def test_blinds_labels_and_joins_without_raw_text(self):
        self.assertNotIn(self.case["id"], json.dumps(self.packet))
        self.assertNotIn("test-only", json.dumps(self.packet))
        self.assertNotEqual(self.tool["blind_packet"](self.fixture, self.answers)[1], self.key)
        receipt = self.receipt()
        self.assertEqual(receipt["rows"][0]["id"], self.case["id"])
        self.assertEqual(receipt["rows"][0]["answer_words"], len(ANSWER.split()))
        self.assertEqual(receipt["rows"][0]["source_sha256"], sha(SOURCE))
        for private in (SOURCE, ANSWER, self.case["profile"], self.verdict["label"]):
            self.assertNotIn(private, json.dumps(receipt))

    def test_fails_when_reviewed_source_or_facts_changed(self):
        for field, value in (("source", "bad"), ("facts", ["wind changed"])):
            with self.subTest(field=field):
                original = self.item[field]
                self.item[field] = value
                with self.assertRaisesRegex(ValueError, "packet"):
                    self.receipt()
                self.item[field] = original

    def test_rejects_unbound_or_duplicate_verdicts(self):
        for key in ("label", "answer_sha256", "item_sha256"):
            original = self.verdict[key]
            self.verdict[key] = "different"
            with self.assertRaises(ValueError):
                self.receipt()
            self.verdict[key] = original
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.tool["make_receipt"](self.fixture, self.answers, self.packet, self.key,
                                      [self.verdict, copy.copy(self.verdict)], sha("test config"))
        with self.assertRaisesRegex(ValueError, "missing"):
            self.tool["make_receipt"](self.fixture, self.answers, self.packet, self.key, [], sha("test config"))

    def test_cross_checks_completion_raw_bytes_and_case_order_independently(self):
        config = sha("config")
        prepared = {"provider": "openai", "model": "test-only", "configuration_sha256": config,
                    "fixtures_sha256": self.fixture[3], "requests": [{"id": self.case["id"], "body": "wire"}]}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            complete = {"provider": "openai", "model": "test-only", "configuration_sha256": config,
                        "fixtures_sha256": self.fixture[3], "count": 1,
                        "request_set_sha256": sha(json.dumps(prepared["requests"], sort_keys=True, separators=(",", ":")))}
            def save():
                raw = json.dumps(self.result) + "\n"
                (root / "answers.jsonl").write_text(raw)
                complete["answers_sha256"] = sha(raw)
                (root / "complete.json").write_text(json.dumps(complete))

            save()
            self.assertEqual(self.tool["load_answers"](root, prepared, self.fixture), self.answers)
            for field in ["request_sha256", "answer_sha256", "observed_model", "id"]:
                with self.subTest(field=field):
                    original = self.result[field]
                    self.result[field] = "stale"
                    save()
                    with self.assertRaises(ValueError):
                        self.tool["load_answers"](root, prepared, self.fixture)
                    self.result[field] = original
            save()
            (root / "answers.jsonl").write_text("")
            with self.assertRaisesRegex(ValueError, "answers digest"):
                self.tool["load_answers"](root, prepared, self.fixture)

    def test_only_exports_a_negative_to_the_rejected_archive(self):
        # Synthetic, in-memory records exercise the real portable scorer on the
        # actual schema. The temporary archive is removed when this test ends.
        checker = self.tool["SCORER"]
        fixture = checker["load_fixtures"](checker["FIXTURES"])
        cases, sources, facts, _ = fixture
        candidate_path = self.tool["ROOT"] / "Qualification/Explain/candidates/openai.json"
        config_hash = hashlib.sha256(candidate_path.read_bytes()).hexdigest()
        model = json.loads(candidate_path.read_text())["model"]
        adults = [case for case in cases if case["suite"] != "learner-blocked"]
        answers = {case["id"]: {**self.result, "id": case["id"], "observed_model": model} for case in adults}
        packet, key = self.tool["blind_packet"](fixture, answers)
        by_id = {case["id"]: case for case in adults}
        verdicts = []
        for item in packet["items"]:
            source_name = by_id[key[item["label"]]]["fixture"]
            verdicts.append({**self.verdict, **{k: item[k] for k in ("label", "answer_sha256", "item_sha256")},
                             "covered_facts": list(range(len(facts[source_name])))})
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            rejected = root / "rejected"
            output = root / "pass.json"
            negative = rejected / "negative.json"
            def build():
                return self.tool["make_receipt"](fixture, answers, packet, key, verdicts, config_hash)
            publish = self.tool["write_reviewed"]
            passing = build()
            with self.assertRaises(ValueError):
                publish(passing, "openai", negative, rejected)
            self.assertFalse(negative.exists())

            verdicts[0].update(verdict="fail", reason="Changed quantity.")
            failing = build()
            with self.assertRaisesRegex(ValueError, "verdict"):
                publish(failing, "openai", output, rejected)
            self.assertFalse(output.exists())
            publish(failing, "openai", negative, rejected)
            self.assertEqual(json.loads(negative.read_text()), failing)
            failing["rows"][0]["answer_sha256"] = "broken"
            with self.assertRaises(ValueError):
                publish(failing, "openai", rejected / "invalid.json", rejected)
            self.assertFalse((rejected / "invalid.json").exists())


if __name__ == "__main__":
    unittest.main()
