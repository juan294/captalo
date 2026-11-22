"""Offline worker for one passage, with three scored attempts per fresh process."""
import argparse
import json
import os
from pathlib import Path
import resource
import runpy
import signal
import time
import tempfile

PILOT = runpy.run_path(str(Path(__file__).with_name("explain-inkling-pilot")))
sha, canonical, require = (PILOT[k] for k in ("sha", "canonical", "require"))
FROZEN = "97447da1a0308c7b6a834f42e4cc39a54c9f1d453f0a0b2d351cd366bf7a290c"


def write_once(path, record):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent) as handle:
        json.dump(record, handle, ensure_ascii=False, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
        os.link(handle.name, path)



def verify_tokens(ids, row):
    require(len(ids) == row["tokens"] and sha(canonical(ids)) == row["token_ids_sha256"],
            f"{row['id']}: prompt token sequence differs from frozen input")


def collect(events, limit):
    count = 0

    def counted():
        nonlocal count
        for entry in events:
            count += 1
            yield entry

    result = PILOT["observe"](counted(), "eof")
    if result["status"] == "eof" and count == limit:
        result["status"] = "cap"
    result["tokens"] = count
    return result


def run(args):
    import mlx.core as mx
    from mlx_lm import load
    from mlx_lm.generate import generate_step, generation_stream
    from mlx_lm.sample_utils import make_sampler
    from tokenizers.decoders import DecodeStream

    preview = PILOT["load"](args.preview)
    require(preview.pop("candidate_sha256") == FROZEN == sha(canonical(preview)), "Restore frozen preview")
    spec = preview["spec"]
    load_start = time.monotonic()
    model, tokenizer = load(str(args.model.resolve()), lazy=False, tokenizer_config={"local_files_only": True},
                            trust_remote_code=False)
    mx.synchronize()
    ready = time.monotonic()
    if args.case == "smoke":
        body = {"instructions": "Answer in one complete English sentence.", "input": "Name a color of fresh grass."}
    else:
        row = next(r for r in preview["rows"] if r["id"] == args.case)
        prepared = PILOT["load"](PILOT["PREPARED"])
        wire = next(r["body"] for r in prepared["requests"] if r["id"] == args.case)
        require(sha(wire.encode()) == row["base_request_sha256"], "Incorrect source request")
        body = json.loads(wire)
    for repeat in range(1, 2 if args.case == "smoke" else 4):
        base = f"{args.case}.{repeat}"
        identity = dict(id=args.case, repeat=repeat, pid=os.getpid(), load_start=load_start, model_ready=ready,
                        process_launch=args.launch, reserved=time.monotonic())
        write_once(args.out / (base + ".start.json"), identity)
        signal.alarm(300)
        mx.reset_peak_memory()
        start = time.monotonic()
        identity["submitted"] = start
        rendered = tokenizer.apply_chat_template(PILOT["messages"](body), tokenize=False, reasoning_effort="none",
                                                 add_generation_prompt=True)
        PILOT["check_render"](body, rendered)
        ids = tokenizer.encode(rendered, add_special_tokens=False)
        # Verify before the timed run in the controller, then attest the actual IDs after its terminal mark.
        decoder = DecodeStream(skip_special_tokens=False)
        limit = spec["max_tokens"]
        raw = generate_step(mx.array(ids), model, max_tokens=limit, sampler=make_sampler(temp=0.0))

        def events():
            for token, _ in raw:
                # Clock includes final tokenization, prefill, reasoning and incremental decoding.
                piece = decoder.step(tokenizer.backend_tokenizer, token) or ""
                yield token, piece, time.monotonic()

        try:
            result = collect(events(), limit)
        except Exception as error:
            write_once(args.out / (base + ".error.json"), dict(identity, reason=type(error).__name__))
            raise
        finally:
            raw.close()
        finished = time.monotonic()
        mx.synchronize(generation_stream)
        drained = time.monotonic()
        signal.alarm(0)
        if args.case != "smoke":
            verify_tokens(ids, row)
        result.update(identity, terminal=finished, gpu_drained=drained, input_tokens=len(ids),
                      token_ids_sha256=sha(canonical(ids)),
                      answer_sha256=sha(result["answer"].encode()), mlx_peak_bytes=mx.get_peak_memory(),
                      rss_peak_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
        write_once(args.out / (base + ".answer.json"), result)
        print(base, result["status"], result["tokens"], flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("model", "preview", "out"):
        parser.add_argument("--" + flag, required=True, type=Path)
    parser.add_argument("--case", required=True)
    parser.add_argument("--launch", required=True, type=float)
    run(parser.parse_args())
