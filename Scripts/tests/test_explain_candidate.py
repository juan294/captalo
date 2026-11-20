import json
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
