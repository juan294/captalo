import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import inkling_review as r


class ReviewTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.sources = {"a": "The first door is open.", "b": "The second door is closed."}
        self.facts = {"a": ["Door open."], "b": ["Door closed."]}
        self.cases = {f: {"id": f, "fixture": f, "depth": "simple", "style": "plain", "suite": "corpus"}
                      for f in self.sources}
        self.records = [dict(id=case, arm=arm, repeat=rep, answer="A door.", answer_sha256=r.sha(b"A door."),
                             natural_stop=True) for case in self.sources
                        for arm, rep in (("inkling", 1), ("inkling", 2), ("sol", None))]
        self.items, self.mapping = r.blind_items(self.records, self.cases, self.sources, self.facts, "ac" * 32)

    def test_packets_deduplicate_only_within_case_across_arms(self):
        self.assertEqual(len(self.items), 2)
        self.assertEqual(sum(map(len, self.mapping.values())), 6)
        self.assertEqual({len(k) for k in self.items}, {24})
        for item in self.items.values():
            self.assertEqual(set(item), {"answer", "answer_sha256", "source", "facts", "item_sha256", "label"})
        review = self.path / "review"
        r.packet(review, self.records, self.cases, self.sources, self.facts)
        r.packet(review, self.records, self.cases, self.sources, self.facts)
        (review / "public/packet.json").write_text('{"items":[]}')
        with self.assertRaises(ValueError):
            r.packet(review, self.records, self.cases, self.sources, self.facts)

    def test_control_rejects_altered_file_answer_or_case(self):
        row = {"id": "a", "answer": "hello", "answer_sha256": r.sha(b"hello"),
               "natural_stop": True, "request_sha256": "req"}
        path = self.path / "answers.jsonl"
        path.write_text(json.dumps(row) + "\n")
        digest = r.sha(path.read_bytes())
        self.assertEqual(len(r.controls(path, digest, [row], ["a"], "sol")), 1)
        for field, value in [("answer", "changed"), ("id", "other")]:
            path.write_text(json.dumps(dict(row, **{field: value})) + "\n")
            for pin in [digest, r.sha(path.read_bytes())]:
                with self.assertRaises(ValueError):
                    r.controls(path, pin, [row], ["a"], "sol")

    def votes(self, name):
        return {"reviewer": name, "votes": [dict(**{k: item[k] for k in ("label", "answer_sha256", "item_sha256")},
                verdict="pass", covered_facts=[0], missing_facts=[], ambiguous=False, near_verbatim=False,
                perceived_style="plain", reason="") for item in self.items.values()]}

    def test_resolve_enforces_independence_and_source_quote(self):
        a, b = self.votes("A"), self.votes("B")
        with self.assertRaises(ValueError):
            r.vote_pair(self.items, a, a)
        b["votes"][0].update(verdict="fail", reason="Unsupported.")
        pair = r.vote_pair(self.items, a, b)
        label = b["votes"][0]["label"]
        self.assertEqual(pair[-1], [label])
        with self.assertRaises(ValueError):
            r.resolutions(self.items, pair, None)
        c = {"reviewer": "C", "votes": [dict(b["votes"][0], source_quote="absent quote")]}
        with self.assertRaises(ValueError):
            r.resolutions(self.items, pair, c)
        c["votes"][0]["source_quote"] = self.items[label]["source"]
        resolved = r.resolutions(self.items, pair, c)
        self.assertEqual(resolved[label]["verdict"], "fail")
        self.assertEqual(resolved[label]["reasons"], ["Unsupported."])

    def test_wrong_or_missing_calibration_evidence_cannot_clear_quality(self):
        row = dict(verdict="fail", reasons=["The answer changes approval into an outcome."])
        pending = r.calibration("x", row, None)
        self.assertEqual(pending["status"], "unresolved")
        att = dict(binding_sha256=pending["binding_sha256"], disposition="rejected", reason=row["reasons"][0])
        self.assertEqual(r.calibration("x", row, att)["status"], "passed")
        with self.assertRaises(ValueError):
            r.calibration("x", dict(row, reasons=["Different."]), att)
        for verdict, status in [("pass", "unreliable"), ("uncertain", "unresolved")]:
            self.assertEqual(r.calibration("x", dict(row, verdict=verdict), None)["status"], status)

    def test_scores_keep_dimensions_distinct_and_long_exceptions_named(self):
        cases, sources, facts, manifest = r.SCORER["load_fixtures"](r.FIXTURES)
        required = r.SCORER["read_required_facts"](facts, r.FIXTURES)
        case = next(c for c in cases if c["id"] == "main-document3000-simple-plain")
        missing = [1]
        covered = [i for i in range(len(facts["document3000"])) if i not in missing]
        verdict = dict(verdict="pass", covered_facts=covered, missing_facts=missing, ambiguous=False,
                       near_verbatim=False, perceived_style="examples")
        scored = r.score_attempt(self.records[0] | {"id": case["id"]}, verdict, case, sources,
                                 facts, manifest, required)
        self.assertEqual(scored["fidelity"], "pass")
        self.assertEqual(scored["missing_required_facts"], [1])
        self.assertEqual(scored["long_exceptions"], {"first": True, "middle": False, "last": True})
        self.assertFalse(scored["quality_pass"])
        self.assertFalse(scored["style_match"])

    def test_candidate_identity_binding_and_complete_inventory(self):
        path = self.path
        (path / "setup.json").write_bytes(r.canonical({"preview_sha256": r.FROZEN}))
        for repeat in (1, 2, 3):
            data = dict(id="a", repeat=repeat, status="eos", answer="A.", answer_sha256=r.sha(b"A."))
            (path / f"a.{repeat}.answer.json").write_bytes(r.canonical(data))
        self.assertEqual([1, 2, 3], [rec["repeat"] for rec in r.candidates(path, ["a"])])
        file = path / "a.3.answer.json"
        for update in ({"answer": "changed"}, {"repeat": 1}, {"id": "other"}, {"status": "unknown"}):
            file.write_bytes(r.canonical(data | update))
            with self.assertRaises(ValueError):
                r.candidates(path, ["a"])
        file.unlink()
        with self.assertRaises(ValueError):
            r.candidates(path, ["a"])

    def test_all_thirty_occurrences_score_against_both_control_receipts(self):
        # These votes and answer strings exercise only the scoring machinery.
        cases, sources, facts, fixture_hash = r.SCORER["load_fixtures"](r.FIXTURES)
        saved = r.PILOT["historical"]()["rows"]
        ids = [row["id"] for row in saved]
        selected = {case["id"]: case for case in cases if case["id"] in ids}
        records = []
        for ref in saved:
            key = ref["id"]
            for arm, repeat in (("inkling", 1), ("inkling", 2), ("inkling", 3), ("terra", None), ("sol", None)):
                answer = "An explanation."
                if arm == "terra" and key == r.SENTINEL:
                    answer = "Another explanation."
                if key == ids[0] and repeat == 2:
                    answer = "Different words."
                records.append(dict(id=key, arm=arm, repeat=repeat, answer=answer,
                                    answer_sha256=r.sha(answer.encode()), natural_stop=True, saved=ref))
        items, mapping = r.blind_items(records, selected, sources, facts, "ac" * 32)
        resolved = {}
        for label, occurrences in mapping.items():
            case_id = occurrences[0]["id"]
            is_sentinel = case_id == r.SENTINEL and occurrences[0]["arm"] == "terra"
            resolved[label] = dict(verdict="fail" if is_sentinel else "pass", covered_facts=list(range(len(items[label]["facts"]))),
                                   missing_facts=[], perceived_style=selected[case_id]["style"], ambiguous=False,
                                   near_verbatim=False, reasons=["Fixture reason."] if is_sentinel else [],
                                   resolution="agreed")
        args = records, mapping, resolved, selected, sources, facts, fixture_hash
        result = r.score(*args, None)
        self.assertEqual((result["original_occurrences"], result["distinct_outputs"]), (30, 8))
        self.assertEqual((len(result["historical_comparisons"]), len(result["attempts"])), (12, 18))
        self.assertEqual(result["quality_gate"], "hold")
        self.assertTrue(result["calibration"]["final_reasons"])
        att = dict(binding_sha256=result["calibration"]["binding_sha256"], disposition="rejected", reason="Fixture reason.")
        result = r.score(*args, att)
        self.assertEqual(result["passed_cases_per_repeat"], {"1": 6, "2": 6, "3": 6})
        self.assertEqual(result["quality_gate"], "pass")
        self.assertFalse(result["repeat_changes"][ids[0]]["identical"])
        changed = next(label for label in items if items[label]["answer"] == "Different words.")
        resolved[changed]["verdict"] = "fail"
        result = r.score(*args, att)
        self.assertEqual(result["passed_cases_per_repeat"], {"1": 6, "2": 5, "3": 6})
        self.assertEqual(result["quality_gate"], "hold")
