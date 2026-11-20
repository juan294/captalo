import copy
import hashlib
import json
import runpy
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "explain-qualify"


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


# Synthetic examples with independent blind dispositions. The checker consumes
# the verdict; the text here makes the reason for each example inspectable.
SOURCE = "The reading room opens on Friday only if the lamp passes inspection."
GOOD = "Friday opening depends on the lamp passing inspection."
BAD_FACT = "The reading room opens on Thursday."
CONFIG_HASH = digest("example frozen configuration")
FIXTURE_HASH = digest("example frozen manifest")


def example():
    cases = [{"id": "friday", "fixture": "room", "depth": "middle", "suite": "corpus"}]
    sources = {"room": SOURCE}
    facts = {"room": ["Friday opening", "conditional on the lamp passing inspection"]}
    row = {
        "id": "friday", "configuration_sha256": CONFIG_HASH,
        "source_sha256": digest(SOURCE), "answer_sha256": digest(GOOD),
        "source_words": len(SOURCE.split()), "answer_words": len(GOOD.split()),
        "natural_stop": True, "verdict": "pass", "covered_facts": [0, 1],
        "missing_facts": [], "near_verbatim": False, "ambiguous": False,
    }
    receipt = {"schema_version": 1, "configuration_sha256": CONFIG_HASH,
               "fixtures_sha256": FIXTURE_HASH, "observed_model": "example-model",
               "rows": [row]}
    return cases, sources, facts, receipt


class QualificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.check = staticmethod(runpy.run_path(str(SCRIPT))["verify_receipt"])

    def setUp(self):
        self.cases, self.sources, self.facts, self.receipt = example()
        self.row = self.receipt["rows"][0]
        self.required = {"room": [0, 1]}

    def verify(self):
        self.check(self.receipt, self.cases, self.sources, self.facts, CONFIG_HASH, FIXTURE_HASH,
                   "example-model", self.required)

    def test_passes_supported_compact_answer(self):
        self.verify()

    def test_rejects_invented_fact_even_at_natural_end(self):
        self.row.update(answer_sha256=digest(BAD_FACT), answer_words=len(BAD_FACT.split()),
                        verdict="fail")
        with self.assertRaisesRegex(ValueError, "verdict"):
            self.verify()

    def test_rejects_missing_exception_despite_faithfulness_pass(self):
        self.row.update(covered_facts=[0], missing_facts=[1])
        with self.assertRaisesRegex(ValueError, "missing facts"):
            self.verify()

    def test_preserves_nonessential_omissions_separately(self):
        self.required["room"] = [1]
        self.row.update(covered_facts=[1], missing_facts=[0])
        self.verify()

    def test_rejects_different_observed_model(self):
        self.receipt["observed_model"] = "an-unqualified-model"
        with self.assertRaisesRegex(ValueError, "observed model"):
            self.verify()

    def test_rejects_incomplete_fact_sheet(self):
        self.row["covered_facts"] = [0]
        with self.assertRaisesRegex(ValueError, "fact coverage"):
            self.verify()

    def test_rejects_uncertain_or_ambiguous_blind_results(self):
        for key, value in [("verdict", "uncertain"), ("ambiguous", True)]:
            with self.subTest(field=key):
                self.row[key] = value
                with self.assertRaisesRegex(ValueError, key):
                    self.verify()
                self.row[key] = "pass" if key == "verdict" else False

    def test_rejects_too_long_middle(self):
        self.row.update(answer_sha256=digest(SOURCE), answer_words=len(SOURCE.split()),
                        near_verbatim=True)
        with self.assertRaisesRegex(ValueError, "shorter"):
            self.verify()

    def test_rejects_truncated_answer(self):
        self.row["natural_stop"] = False
        with self.assertRaisesRegex(ValueError, "natural stop"):
            self.verify()

    def test_requires_every_case_exactly_once(self):
        for rows, error in [([], "missing cases"), ([self.row, copy.copy(self.row)], "duplicate")]:
            with self.subTest(error=error):
                self.receipt["rows"] = rows
                with self.assertRaisesRegex(ValueError, error):
                    self.verify()

    def test_excludes_direct_learner_from_paid_run(self):
        self.cases[0]["suite"] = "learner-blocked"
        with self.assertRaisesRegex(ValueError, "unexpected case"):
            self.verify()

    def test_rejects_stale_inputs_and_malformed_answers(self):
        for obj, key in [(self.receipt, "configuration_sha256"), (self.receipt, "fixtures_sha256"),
                         (self.row, "configuration_sha256"), (self.row, "source_sha256"),
                         (self.row, "source_words"), (self.row, "answer_sha256"),
                         (self.row, "answer_words"), (self.row, "covered_facts")]:
            with self.subTest(key=key):
                previous = obj[key]
                obj[key] = False
                with self.assertRaises(ValueError):
                    self.verify()
                obj[key] = previous

    def test_rejects_raw_content_in_sanitized_receipt(self):
        self.row["answer"] = GOOD
        with self.assertRaisesRegex(ValueError, "fields"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
