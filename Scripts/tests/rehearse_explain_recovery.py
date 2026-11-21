"""Exercise real freeze, dispatch, packet, verdict and qualification paths with synthetic transport."""
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ComparisonRehearsal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.base.cleanup)
        cls.prepared = Path(cls.base.name)
        (cls.prepared / "Scripts").mkdir()
        for script in (ROOT / "Scripts").glob("explain*"):
            if script.is_file():
                shutil.copy2(script, cls.prepared / "Scripts" / script.name)
        shutil.copytree(ROOT / "Tests/ExplainQualification", cls.prepared / "Tests/ExplainQualification")
        shutil.copytree(ROOT / "Qualification/Explain/candidates", cls.prepared / "Qualification/Explain/candidates")
        (cls.prepared / "Packages").mkdir()
        (cls.prepared / "Packages/CaptaloCore").symlink_to(ROOT / "Packages/CaptaloCore")
        cls.env = {k: v for k, v in os.environ.items() if k not in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY")}
        subprocess.run([cls.prepared / "Scripts/explain-candidate", "prepare"], env=cls.env,
                       check=True, capture_output=True, text=True)

    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.root = Path(work.name).resolve() / "rehearsal"
        shutil.copytree(self.prepared, self.root, symlinks=True)
        self.runner = runpy.run_path(str(self.root / "Scripts/explain-qualification-run"))
        self.review = runpy.run_path(str(self.root / "Scripts/explain-qualification-review"))
        self.approval = self.runner["recovery_manifest"](self.root)
        self.observations = {}

    def dispatch(self, arm):
        _, _, rows = self.runner["recovery_context"](self.root, arm)
        case_ids = {row["body"].encode(): row["id"] for row in rows}

        def simulated_provider(provider, model, wire):
            self.assertEqual(provider, "openai")
            message = json.loads(json.loads(wire)["input"])
            answer = f"Synthetic sentence {len(self.observations)}."
            self.observations[answer] = (arm, case_ids[wire], message["style"])
            return answer, model

        return self.runner["recovery_run"](self.root, arm, self.approval, simulated_provider)

    def score(self, group, mark):
        command = [self.root / "Scripts/explain-qualification-review"]
        directory = Path(subprocess.check_output([*command, "recovery-packet", group], env=self.env, text=True).strip())
        self.assertEqual(directory.parent, self.root / ".local/reader-packets")
        self.assertRegex(directory.name, r"^[a-f0-9]{24}$")
        self.assertEqual({p.name for p in directory.iterdir()}, {"packet.json", "RUBRIC.md", "RECOVERY-REVIEW.md"})
        packet = json.loads((directory / "packet.json").read_bytes())
        votes = []
        for item in packet["items"]:
            self.assertEqual(set(item), {"label", "facts", "source", "answer", "answer_sha256", "item_sha256"})
            arm, case, style = self.observations[item["answer"]]
            vote = {k: item[k] for k in ("label", "answer_sha256", "item_sha256")}
            vote.update(perceived_style=style, verdict="pass", near_verbatim=False, ambiguous=False,
                        covered_facts=list(range(len(item["facts"]))), missing_facts=[], reason="")
            mark(vote, arm, case)
            votes.append(vote)
        paths = []
        for reader in ("reader-one", "reader-two"):
            path = self.root / f"{group}-{reader}.json"
            path.write_text(json.dumps({"reviewer": reader, "votes": votes}))
            paths.append(path)
        result = subprocess.run([*command, "recovery-receipt", group, "--first", paths[0], "--second", paths[1]],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def paired(self, mark):
        self.dispatch("control")
        self.dispatch("selected")
        self.score("pair", mark)
        self.assertEqual(len(self.observations), 12)
        return self.review["verified_outcome"](self.root, "selected")

    def test_full_run_after_clean_pilot_can_fail_held_out(self):
        self.assertEqual(self.paired(lambda *_: None), "pass")
        self.dispatch("selected-full")

        def mark(vote, arm, case):
            if case.startswith("held-"):
                vote.update(verdict="fail", reason="The synthetic answer introduces an unsupported claim.")

        self.score("selected-full", mark)
        self.assertEqual(len(self.observations), 95)
        self.assertEqual(self.review["verified_outcome"](self.root, "selected-full"), "fail")

    def test_only_illustration_miss_can_unlock_the_example(self):
        def miss_metaphor(vote, arm, case):
            if arm == "selected" and case == "main-legal-middle-metaphors":
                vote["perceived_style"] = "plain"
        self.assertEqual(self.paired(miss_metaphor), "example-eligible")
        self.dispatch("example")
        self.score("example", lambda *_: None)
        self.dispatch("example-full")
        self.score("example-full", lambda *_: None)
        self.assertEqual(len(self.observations), 101)
        self.assertEqual(self.review["verified_outcome"](self.root, "example-full"), "pass")
        # A portable receipt must still verify from a checkout without private answers, votes or keys.
        shutil.rmtree(self.root / ".local")
        check = subprocess.run([self.root / "Scripts/explain-qualify", "--require", "openai"],
                               env=self.env, text=True, capture_output=True)
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertIn("openai", check.stdout.lower())

    def test_pilot_factual_miss_closes_both_paid_routes(self):
        def causal_claim(vote, arm, case):
            if arm == "selected" and case == "main-textbook-simple-plain":
                vote.update(verdict="fail", reason="The rehearsal reviewer identified an unsupported cause.")
        self.assertEqual(self.paired(causal_claim), "fail")
        for arm in ("example", "selected-full", "example-full"):
            with self.assertRaisesRegex(ValueError, "ineligible|not eligible"):
                self.dispatch(arm)
        self.assertEqual(len(self.observations), 12)


if __name__ == "__main__":
    unittest.main()
