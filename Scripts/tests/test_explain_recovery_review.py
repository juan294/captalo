import contextlib
import copy
import io
import shutil
import tempfile
from pathlib import Path
import runpy
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
REVIEW = runpy.run_path(str(SCRIPTS / "explain-qualification-review"))["RECOVERY"]


class RecoveryReviewTests(unittest.TestCase):
    def setUp(self):
        self.item = {"label": "a" * 24, "item_sha256": "b" * 64, "answer_sha256": "c" * 64,
                     "answer": "Like a gate, it opens Fridays.", "source": "The gate opens only on Fridays.",
                     "facts": ["Opens only on Fridays"]}
        self.vote = {k: self.item[k] for k in ("label", "item_sha256", "answer_sha256")}
        self.vote.update(verdict="pass", covered_facts=[0], missing_facts=[], near_verbatim=False,
                         ambiguous=False, perceived_style="metaphors", reason="")

    def test_requires_each_bound_style_and_disposition(self):
        validate = REVIEW["validate_vote"]
        validate(self.vote, self.item)
        for key in self.vote:
            altered = dict(self.vote)
            del altered[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(altered, self.item)
        for changes in [{"answer_sha256": "e"*64}, {"covered_facts": [0, 0]}, {"verdict": "fail"},
                        {"perceived_style": "unmeasured"}, {"ambiguous": 0}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(dict(self.vote, **changes), self.item)

    def test_disputed_votes_need_a_blinded_source_backed_resolution(self):
        resolve = REVIEW["resolve_votes"]
        other = dict(self.vote, perceived_style="indeterminate")
        with self.assertRaisesRegex(ValueError, "adjudicat"):
            resolve(self.item, self.vote, other, None)
        third = dict(other, reason="The reference to a gate repeats the literal gate.",
                     source_quote="The gate opens only on Fridays.")
        scores, disposition = resolve(self.item, self.vote, other, third)
        self.assertEqual(scores["perceived_style"], "indeterminate")
        self.assertEqual(disposition, "adjudicated")
        for altered in [dict(third, source_quote="Sunday"), dict(third, reason=""), dict(third, verdict="fail")]:
            with self.assertRaises(ValueError):
                resolve(self.item, self.vote, other, altered)

    def test_adjudicating_one_omission_preserves_other_agreed_omissions(self):
        item = dict(self.item, facts=["Actor", "Deadline", "Condition"])
        a = dict(self.vote, covered_facts=[0], missing_facts=[1, 2])
        b = dict(self.vote, covered_facts=[0, 2], missing_facts=[1])
        third = dict(b, covered_facts=[0, 1, 2], missing_facts=[], reason="The condition is present.",
                     source_quote="The gate opens only on Fridays")
        with self.assertRaisesRegex(ValueError, "agreed"):
            REVIEW["resolve_votes"](item, a, b, third)

    def test_example_eligibility_depends_on_failed_dimensions_and_arm(self):
        decide = REVIEW["recovery_decision"]
        case = dict(id="test", style="metaphors", depth="middle")
        self.assertEqual(decide("selected", [case], []), "pass")
        for why in ["style mismatch", "Middle answer must be shorter"]:
            self.assertEqual(decide("selected", [case], [f"test: {why}"]), "example-eligible")
            self.assertEqual(decide("example", [case], [f"test: {why}"]), "fail")
        self.assertEqual(decide("selected", [case], ["test: missing facts [0]"]), "fail")
        self.assertEqual(decide("selected", [dict(case, style="plain")], ["test: style mismatch"]), "fail")


class PortableRecoveryTests(unittest.TestCase):
    """A fresh checkout verifies bindings without using stored answers or blind keys."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.outputs = self.root / "Qualification/Explain/recovery"
        self.outputs.mkdir(parents=True)
        project = SCRIPTS.parent
        for path in ("Tests/ExplainQualification", "Qualification/Explain/candidates"):
            shutil.copytree(project / path, self.root / path)
        self.runner = REVIEW["RUNNER"]
        self.scorer = REVIEW["SCORER"]

    def receipt(self, arm):
        config_file = self.root / "Qualification/Explain/candidates" / (self.runner["recovery_candidate_name"](arm) + ".json")
        config = self.scorer["load"](config_file)
        config_hash = self.scorer["sha"](config_file.read_bytes())
        fixtures = self.root / "Tests/ExplainQualification"
        all_cases, sources, facts, _ = self.scorer["load_fixtures"](fixtures)
        cases = [c for c in all_cases if c["suite"] != "learner-blocked" and
                 (arm.endswith("-full") or c["id"] in self.runner["PILOT_CASES"])]
        identity = self.runner["recovery_identity"](self.root, arm, config, config_hash, [c["id"] for c in cases])
        rows = []
        for case in cases:
            name = case["fixture"]
            fields = dict(verdict="pass", covered_facts=list(range(len(facts[name]))), missing_facts=[],
                          near_verbatim=False, ambiguous=False, perceived_style=case["style"])
            row = dict(id=case["id"], configuration_sha256=config_hash, source_sha256=self.scorer["sha"](sources[name].encode()),
                       source_words=len(sources[name].split()), answer_sha256=REVIEW["hashed"]([arm, case["id"]]),
                       answer_words=3, natural_stop=True, request_sha256=config["request_sha256"][case["id"]],
                       adjudication="agreed", **fields)
            row["judgments"] = []
            for name in ("reader-a", "reader-b"):
                vote = dict(**fields, reviewer_sha256=REVIEW["hashed"](name), vote_sha256=REVIEW["hashed"]([case["id"], name]))
                vote["binding_sha256"] = REVIEW["vote_binding"](identity, row, vote)
                row["judgments"].append(vote)
            rows.append(row)
        return dict(schema_version=2, identity=identity, rows=rows)

    def test_changed_answer_counts_hash_or_candidate_cannot_reuse_judgments(self):
        verify = REVIEW["verify_portable"]
        valid = self.receipt("selected")
        self.assertFalse((self.root / ".local").exists())
        self.assertEqual(verify(self.root, "selected", valid)[0], "pass")
        for field, value in (("answer_words", 2), ("answer_sha256", "4" * 64), ("perceived_style", "picture"),
                             ("request_sha256", "4" * 64)):
            with self.subTest(field=field), self.assertRaises(ValueError):
                change = copy.deepcopy(valid)
                change["rows"][0][field] = value
                verify(self.root, "selected", change)
        for arm in ("control", "selected-full", "example"):
            with self.subTest(arm=arm), self.assertRaises(ValueError):
                verify(self.root, arm, valid)
        with self.assertRaisesRegex(ValueError, "cohort"):
            verify(self.root, "selected", dict(valid, rows=valid["rows"][1:]))
        with self.assertRaisesRegex(ValueError, "v2"):
            verify(self.root, "selected", dict(valid, schema_version=1))

    def test_full_receipt_alone_never_admits_candidate(self):
        receipt = self.receipt("selected-full")
        self.assertEqual(REVIEW["verify_portable"](self.root, "selected-full", receipt)[0], "pass")
        (self.outputs / "selected-full.json").write_bytes(REVIEW["encoded"](receipt))
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(ValueError, "treatment pilot"):
            REVIEW["portable_outcomes"](self.root)
