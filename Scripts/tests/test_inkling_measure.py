import hashlib
import json
from pathlib import Path
import runpy
from tempfile import TemporaryDirectory
import unittest

M = runpy.run_path(str(Path(__file__).resolve().parents[1] / "inkling_measure.py"))


METRICS = runpy.run_path(str(Path(__file__).resolve().parents[1] / "inkling_metrics.py"))


class MeasurementTests(unittest.TestCase):
    def test_cold_clock_and_simultaneous_voice_memory(self):
        row = dict(process_launch=10, load_start=11, model_ready=15, reserved=16, submitted=17,
                   first_final=19, first_sentence=20, terminal=21, gpu_drained=22, repeat=1,
                   pid=44, status="eos", mlx_peak_bytes=100, rss_peak_bytes=75)
        samples = [dict(worker=44, clock=18, worker_bytes=40, voice_bytes=10),
                   dict(worker=44, clock=22, worker_bytes=55, voice_bytes=12)]
        intervals = [dict(started_seconds=16, ended_seconds=19.5),
                     dict(started_seconds=20.25, ended_seconds=21.5)]
        result = METRICS["measure"](row, samples, intervals)
        self.assertEqual(result["loaded_seconds"]["first_sentence"], 3)
        self.assertEqual(result["cold_seconds"]["first_sentence"], 10)
        self.assertTrue(result["voice"]["first_final_onset"])
        self.assertFalse(result["voice"]["first_sentence_onset"])
        self.assertEqual(result["memory"]["active_paired_rss_peak_bytes"], 50)
        self.assertIsNone(METRICS["measure"](dict(row, repeat=2), samples, intervals)["cold_seconds"])

    def test_eos_and_cap_from_actual_ids(self):
        def sample(ids, limit):
            pieces = {40: "Hello.", 50: "private"}
            seq = ((n, pieces.get(n, ""), i / 10) for i, n in enumerate(ids))
            return M["collect"](seq, limit)
        row = sample([200001, 200008, 50, 200010, 200001, 200004, 40, 200010, 200006], 9)
        self.assertEqual((row["status"], row["tokens"], row["answer"]), ("eos", 9, "Hello."))
        self.assertEqual(row["first_sentence"], 0.8)
        self.assertNotIn("private", str(row))
        self.assertEqual(sample([200001, 200004, 40], 3)["status"], "cap")
        self.assertEqual(sample([200001], 4096)["status"], "eof")

    def test_disk_events_are_exclusive_and_survive_interrupt(self):
        with TemporaryDirectory() as tmp:
            p = Path(tmp) / "case-start.json"
            M["write_once"](p, {"id": "first"})
            with self.assertRaises(FileExistsError):
                M["write_once"](p, {"id": "second"})
            self.assertEqual(json.loads(p.read_bytes()), {"id": "first"})

    def test_prompt_bound_to_token_hash_and_count(self):
        ids = [1, 2]
        digest = hashlib.sha256(b"[1,2]").hexdigest()
        M["verify_tokens"](ids, {"id": "a", "tokens": 2, "token_ids_sha256": digest})
        for altered in [[2, 1], [1]]:
            with self.assertRaises(ValueError):
                M["verify_tokens"](altered, {"id": "a", "tokens": 2, "token_ids_sha256": digest})
