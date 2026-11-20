import copy
import hashlib
import json
import runpy
import shutil
import subprocess
import sys
import tempfile
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


class HistoricalRejectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.script = self.root / "Scripts/explain-qualify"
        self.script.parent.mkdir()
        shutil.copyfile(SCRIPT, self.script)
        original = SCRIPT.parents[1]
        self.qual = self.root / "Qualification/Explain"
        shutil.copytree(original / "Qualification/Explain/candidates", self.qual / "candidates")
        fixtures = self.root / "Tests/ExplainQualification"
        shutil.copytree(original / "Tests/ExplainQualification", fixtures)
        self.fixture_data = runpy.run_path(str(self.script))["load_fixtures"](fixtures)
        self.archives = self.qual / "rejected/configurations"
        self.archives.mkdir(parents=True)
        self.config = json.loads((self.qual / "candidates/openai.json").read_bytes())
        self.config["instruction"] += " Historical synthetic test variant."
        self.config["instruction_sha256"] = digest(self.config["instruction"])

    def archive(self):
        snapshot = json.dumps(self.config)
        identity = digest(snapshot)
        path = self.archives / f"{identity}.json"
        path.write_text(snapshot)
        cases, sources, facts, _ = self.fixture_data
        _, _, _, receipt = example()
        template = receipt["rows"][0]
        rows = []
        for case in cases:
            if case["suite"] != "learner-blocked":
                source = sources[case["fixture"]]
                rows.append({**template, "id": case["id"], "configuration_sha256": identity,
                             "source_sha256": digest(source), "source_words": len(source.split()),
                             "covered_facts": list(range(len(facts[case["fixture"]]))), "answer_words": 1})
        rows[0]["verdict"] = "fail"
        receipt.update(configuration_sha256=identity, fixtures_sha256=self.config["fixtures_sha256"],
                       observed_model=self.config["revision"], rows=rows)
        record = self.qual / "rejected" / path.name
        record.write_text(json.dumps(receipt))
        return path, record, receipt

    def cli(self, *args):
        return subprocess.run([sys.executable, self.script, *args], capture_output=True, text=True)

    def test_default_rechecks_negative_without_admitting_archived_config(self):
        config, record, receipt = self.archive()
        checked = self.cli()
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertIn("REJECTED openai", checked.stdout)
        self.assertNotIn("blind verdict", checked.stdout)
        explicit = self.cli("--record-outcome", "--config", config, "--receipt", record)
        self.assertEqual(explicit.returncode, 0, explicit.stderr)
        self.assertIn("blind verdict fail", explicit.stdout)
        ordinary = self.cli("--config", config, "--receipt", record)
        self.assertNotEqual(ordinary.returncode, 0)
        self.assertIn("unrecognized candidate", ordinary.stderr)
        receipt["rows"][0]["verdict"] = "pass"
        record.write_text(json.dumps(receipt))
        result = self.cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("passing quality", result.stderr)

    def test_refuses_modified_archived_configuration(self):
        config, record, _ = self.archive()
        config.write_text(config.read_text() + "\n")
        for args in ((), ("--record-outcome", "--config", config, "--receipt", record)):
            with self.subTest(args=args):
                self.assertNotEqual(self.cli(*args).returncode, 0)

    def test_older_fixtures_unavailable_only_for_historical_verification(self):
        self.config["fixtures_sha256"] = digest("older frozen corpus")
        config, record, receipt = self.archive()
        default = self.cli()
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertIn("historical fixtures unavailable", default.stdout)
        self.assertNotIn("REJECTED openai", default.stdout)
        explicit = self.cli("--record-outcome", "--config", config, "--receipt", record)
        self.assertNotEqual(explicit.returncode, 0)
        self.assertIn("fixture", explicit.stderr)
        receipt["fixtures_sha256"] = digest("different binding")
        record.write_text(json.dumps(receipt))
        self.assertNotEqual(self.cli().returncode, 0)


if __name__ == "__main__":
    unittest.main()
