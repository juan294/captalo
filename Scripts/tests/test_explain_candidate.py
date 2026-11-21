import json
import os
import runpy
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CandidateFreezeTests(unittest.TestCase):
    def test_app_builder_reproduces_the_frozen_adult_request_set(self):
        result = subprocess.run([ROOT / "Scripts/explain-candidate", "check"], cwd=ROOT,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for provider in ["openai", "anthropic"]:
            self.assertIn(f"{provider}: 83 requests", result.stdout)
            candidate = json.loads((ROOT / "Qualification/Explain/candidates" / f"{provider}.json").read_bytes())
            self.assertEqual(candidate["provider"], provider)
            self.assertEqual(candidate["max_output_tokens"], 4096)

        self.assertIn("openai-selected: 83 requests", result.stdout)
        self.assertIn("openai-example: 83 requests", result.stdout)
        selected, example = [json.loads((ROOT / "Qualification/Explain/candidates" / f"openai-{arm}.json").read_bytes())
                             for arm in ("selected", "example")]
        sources = ROOT / "Tests/ExplainQualification"
        cases = json.loads((sources / "cases.json").read_bytes()) + json.loads((sources / "held-out.json").read_bytes())
        adult = {c["id"]: c["style"] for c in cases if c["suite"] != "learner-blocked"}
        self.assertEqual(adult.keys(), selected["request_sha256"].keys())
        self.assertEqual(adult.keys(), example["request_sha256"].keys())
        for case, style in adult.items():
            self.assertEqual(selected["request_sha256"][case] != example["request_sha256"][case], style == "metaphors")

    def test_probe_recovery_and_off_subset_wire_binding(self):
        serializer = runpy.run_path(str(ROOT / "Scripts/explain-candidate"))
        env = dict(os.environ)
        env.setdefault("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")
        build = ["swift", "build", "--package-path", str(ROOT / "Packages/CaptaloCore")]
        subprocess.run([*build, "--product", "ExplainQualificationProbe"], env=env, check=True, capture_output=True)
        probe = Path(subprocess.check_output([*build, "--show-bin-path"], env=env, text=True).strip()) / "ExplainQualificationProbe"
        command = [probe, "openai", "requests", "selected"]
        invalid = [dict(id="short-case", depth="middle", style="plain", source="one", profile="")]
        result = subprocess.run(command, input=json.dumps(invalid), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("short-case: Select a longer passage or choose another depth.", result.stderr)
        cases, _ = serializer["fixtures"]()
        requests = json.loads(subprocess.check_output(command, input=json.dumps(cases).encode()))
        config = json.loads((ROOT / "Qualification/Explain/candidates/openai-selected.json").read_bytes())
        check = serializer["check_requests"]
        check(config, requests)
        for case in ("main-email-middle-metaphors", next(c["id"] for c in cases if c["suite"] == "held-out")):
            changed = [dict(row, body=row["body"] + " ") if row["id"] == case else row for row in requests]
            with self.assertRaisesRegex(ValueError, "set digest"):
                check(config, changed)
            with self.assertRaisesRegex(ValueError, "body digest"):
                check(dict(config, request_set_sha256=serializer["sha"](serializer["canonical"](changed))), changed)
