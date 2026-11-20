"""The qualification runner never contacts a live provider in these tests."""
import hashlib
import io
import json
import runpy
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "explain-qualification-run"
MODEL = "gpt-6.1-terra"


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stream(*events):
    return io.BytesIO(b"".join(b"data: " + encoded(event) + b"\n\n" for event in events))


def openai_events():
    return [
        {"type": "response.output_text.delta", "delta": "Blue."},
        {"type": "response.completed", "response": {
            "model": MODEL, "status": "completed",
            "output": [{"type": "message", "role": "assistant", "status": "completed",
                        "content": [{"type": "output_text", "text": "Blue."}]}]}}
    ]


def anthropic_events():
    return [
        {"type": "message_start", "message": {"model": "claude-sonnet-5-5", "content": []}},
        {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Blue."}},
        {"type": "content_block_stop", "index": 0},
        {"type": "message_delta", "delta": {"stop_reason": "end_turn"}},
        {"type": "message_stop"},
    ]


class RunTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = runpy.run_path(str(SCRIPT))

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.work = self.root / ".local/explain-qualification/openai"
        self.work.mkdir(parents=True)
        candidate_dir = self.root / "Qualification/Explain/candidates"
        candidate_dir.mkdir(parents=True)
        self.candidate_path = candidate_dir / "openai.json"
        self.prepared_path = self.work / "prepared.json"
        body = encoded({"model": MODEL, "store": False, "stream": True, "service_tier": "default",
                        "reasoning": {"effort": "none"}, "max_output_tokens": 10,
                        "instructions": "Explain.", "input": "Synthetic."}).decode()
        self.requests = [{"id": "one", "body": body}, {"id": "two", "body": body}]
        self.candidate = {"provider": "openai", "model": MODEL, "fixtures_sha256": "a" * 64,
                          "request_set_sha256": digest(encoded(self.requests))}
        self.candidate_path.write_bytes(encoded(self.candidate))
        self.prepared = {"configuration_sha256": digest(self.candidate_path.read_bytes()),
                         "fixtures_sha256": "a" * 64, "provider": "openai", "model": MODEL,
                         "requests": self.requests}
        self.prepared_path.write_bytes(encoded(self.prepared))

    def run_metered(self, send, limit=2, usd="5"):
        self.runner["run"](self.root, "openai", limit, Decimal(usd), send)

    def test_no_dispatch_when_limits_or_frozen_digest_fail(self):
        for limit, usd in [(1, "5"), (2, "0.0000001"), (2, "NaN"), (2, "Infinity")]:
            with self.subTest(limit=limit, usd=usd), self.assertRaises(ValueError):
                self.run_metered(self.fail, limit, usd)
        self.requests[-1]["body"] += " "
        self.prepared_path.write_bytes(encoded(self.prepared))
        with self.assertRaisesRegex(ValueError, "identity"):
            self.run_metered(self.fail)

    def test_stale_serializer_prevents_chargeable_run(self):
        scripts = self.root / "Scripts"
        scripts.mkdir()
        check = scripts / "explain-candidate"
        check.write_text("#!/bin/sh\nexit 1\n")
        check.chmod(0o755)
        main = self.runner["main"]
        with patch.dict("os.environ", {"OPENAI_API_KEY": "synthetic-test-only"}), \
             patch.dict(main.__globals__, {"ROOT": self.root, "send_request": self.fail}), \
             patch("sys.argv", ["runner", "openai", "--execute", "--max-usd", "5", "--max-requests", "2"]):
            with self.assertRaisesRegex(ValueError, "preflight"):
                main()
        self.assertEqual(list(self.work.iterdir()), [self.prepared_path])

    def test_tuning_uses_only_named_frozen_requests_and_separate_evidence(self):
        sent = []
        def send(provider, model, body):
            sent.append(body)
            return "Blue.", model

        # "one" represents a held-out adult case included in the full qualification set.
        fixtures = self.root / "Tests/ExplainQualification"
        fixtures.mkdir(parents=True)
        (fixtures / "cases.json").write_text(json.dumps([{"id": "two", "suite": "corpus"}]))
        for ids in [["absent"], ["two", "two"], ["one"]]:
            with self.assertRaises(ValueError):
                self.runner["run"](self.root, "openai", 1, Decimal("1"), send, case_ids=ids)
        self.assertEqual(sent, [])
        evidence = self.runner["run"](self.root, "openai", 1, Decimal("1"), send, case_ids=["two"])
        self.assertEqual(sent, [self.requests[1]["body"].encode()])
        self.assertEqual(json.loads((evidence / "authorization.json").read_bytes())["case_ids"], ["two"])
        self.assertFalse((self.work / self.prepared["configuration_sha256"] / "complete.json").exists())
        with self.assertRaisesRegex(ValueError, "exists"):
            self.runner["run"](self.root, "openai", 1, Decimal("1"), self.fail, case_ids=["two"])

    def test_natural_completions_only(self):
        parse = self.runner["read_answer"]
        for provider, model, events in [
            ("openai", MODEL, openai_events()),
            ("anthropic", "claude-sonnet-5-5", anthropic_events())
        ]:
            self.assertEqual(parse(stream(*events), provider, model), ("Blue.", model))
            for bad in [events[:-1], events + [events[-1]], events + [{"type": "error"}]]:
                with self.assertRaises(ValueError):
                    parse(stream(*bad), provider, model)
            with self.assertRaises(ValueError):
                parse(stream(*events), provider, "different-model")
        bad = openai_events()
        bad[-1]["response"]["output"][0]["content"][0]["text"] = "Wrong."
        with self.assertRaises(ValueError):
            parse(stream(*bad), "openai", MODEL)
        bad = anthropic_events()
        bad[-2]["delta"]["stop_reason"] = "max_tokens"
        with self.assertRaises(ValueError):
            parse(stream(*bad), "anthropic", "claude-sonnet-5-5")
        with self.assertRaises(ValueError):
            parse(stream(*anthropic_events()[:3], *anthropic_events()[-2:]), "anthropic", "claude-sonnet-5-5")

    def test_records_run_scope_and_answers_and_rejects_replay(self):
        sent = []
        def send(provider, model, body):
            sent.append((provider, model, body))
            return "Blue.", model

        self.run_metered(send)
        self.assertEqual(sent, [("openai", MODEL, row["body"].encode()) for row in self.requests])
        evidence = self.work / self.prepared["configuration_sha256"]
        self.assertEqual(json.loads((evidence / "authorization.json").read_bytes())["max_requests"], 2)
        answers = (evidence / "answers.jsonl").read_bytes()
        self.assertEqual(json.loads(answers.splitlines()[0])["answer_sha256"], digest(b"Blue."))
        complete = json.loads((evidence / "complete.json").read_bytes())
        self.assertEqual(complete["answers_sha256"], digest(answers))
        self.assertEqual(complete["count"], 2)
        with self.assertRaisesRegex(ValueError, "exists"):
            self.run_metered(self.fail)

    def test_failed_dispatch_is_recorded_once_without_http_error_body(self):
        attempts = []
        def send(*_):
            attempts.append(1)
            raise ValueError("private-example")
        with self.assertRaisesRegex(ValueError, "case one"):
            self.run_metered(send)
        evidence = self.work / self.prepared["configuration_sha256"]
        self.assertEqual(len(attempts), 1)
        self.assertFalse((evidence / "complete.json").exists())
        self.assertNotIn("private-example", (evidence / "attempts.jsonl").read_text())

    @patch("http.client.HTTPSConnection")
    def test_redirect_never_receives_a_second_request(self, connect):
        conn = connect.return_value
        conn.getresponse.return_value.status = 307
        with patch.dict("os.environ", {"OPENAI_API_KEY": "synthetic-test-only"}):
            with self.assertRaisesRegex(ValueError, "HTTP 307"):
                self.runner["send_request"]("openai", MODEL, b"{}")
        self.assertEqual(connect.call_args.args[0], "api.openai.com")
        self.assertEqual(conn.request.call_count, 1)
        self.assertEqual(conn.request.call_args.args[:2], ("POST", "/v1/responses"))
        conn.getresponse.return_value.read.assert_not_called()


if __name__ == "__main__":
    unittest.main()
