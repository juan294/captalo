"""Summarize the retained Studio pilot measurements without loading either model."""
import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path

PILOTS = Path(__file__).resolve().parents[1] / "Qualification/Explain/model-pilots"


def read(path):
    return json.loads(path.read_bytes())


def lines(path):
    with path.open() as stream:
        return [json.loads(line) for line in stream]


def check(condition, message):
    if not condition:
        raise ValueError(message)


def ordered(values):
    return all(isinstance(v, (float, int)) and math.isfinite(v) for v in values) and values == sorted(values)


def assets(directory, spec, setup):
    tensor = spec["main_tensor"]
    weights = (directory / tensor["file"]).stat().st_size
    check(weights == tensor["bytes"] == setup["tensor_bytes"] and setup["tensor_sha256"] == tensor["sha256"],
          "Tensor size or verification receipt differs from the pin")
    expected = set(spec["metadata_sha256"]) | {tensor["file"]}
    check({str(p.relative_to(directory)) for p in directory.rglob("*") if p.is_file()} == expected,
          "Model inventory differs from pinned assets")
    metadata = 0
    for name, digest in spec["metadata_sha256"].items():
        data = (directory / name).read_bytes()
        check(hashlib.sha256(data).hexdigest() == digest, f"Metadata mismatch for {name}")
        metadata += len(data)
    return dict(original_tensor_bytes=weights, original_tensor_sha256=tensor["sha256"],
                metadata_bytes=metadata, total_model_asset_bytes=weights + metadata)


def verified_voice(root, setup):
    intervals = lines(root / "voice-intervals.jsonl")
    end = read(root / "voice-summary.json")
    ready = setup["voice"]
    check(setup["clock"] == "mach_absolute_time()" and end["clock"] == "CLOCK_UPTIME_RAW seconds",
          "Cannot match Python and Kokoro macOS uptime clocks")
    check(setup["voice_ready"] is True and ready["voice_ready"] is True and ready["voice"] == "af_heart" and
          intervals and ready["pcm"] == intervals[0]["pcm"], "Voice readiness receipt differs from first synthesis")
    frames = active = previous = 0
    for index, interval in enumerate(intervals, 1):
        start, stop = interval["started_seconds"], interval["ended_seconds"]
        pcm = interval["pcm"]
        check(interval["sequence"] == index and ordered([previous, start, stop]) and stop > start and
              pcm["sustainedSignal"] is True and pcm["frames"] > 0 and pcm["sampleRate"] > 0,
              f"Invalid PCM interval {index}")
        previous = stop
        frames += pcm["frames"]
        active += stop - start
    check(not end.get("error") and end["completed"] == len(intervals) and
          frames == end["signal_frames_in_completed_utterances"] and math.isclose(active, end["active_seconds"]) and
          intervals[0]["started_seconds"] == end["first_started_seconds"] and
          intervals[0]["ended_seconds"] == end["first_completed_seconds"] and previous == end["last_completed_seconds"],
          "Voice teardown totals disagree with completed PCM intervals")
    return intervals, end


def telemetry(record, voice_pid):
    check(record["voice_pid"] == voice_pid, "Unexpected telemetry voice PID")
    rss = dict(tuple(map(int, line.split())) for line in record["rss_kib"].splitlines())
    free = re.search(r"System-wide memory free percentage:\s*(\d+)%", record["pressure"])
    swap = re.search(r"\bused\s*=\s*([\d.]+)M\b", record["swap"])
    return dict(clock=record["clock"], worker=record["worker_pid"], voice_bytes=rss.get(voice_pid, 0) * 1024,
                worker_bytes=rss.get(record["worker_pid"], 0) * 1024,
                memory_free_pct=int(free[1]) if free else None, swap_used_mib=float(swap[1]) if swap else None)


def measure(row, samples, intervals):
    launch, load, ready, start, stop, drained = [row[k] for k in (
        "process_launch", "load_start", "model_ready", "submitted", "terminal", "gpu_drained")]
    token, sentence = row["first_final"], row["first_sentence"]
    check(ordered([launch, load, ready, row["reserved"], start] + [t for t in (token, sentence) if t is not None]
                  + [stop, drained]) and stop > start and (sentence is None or token is not None), "Invalid clock order")
    active = [i for i in intervals if i["started_seconds"] < stop and start < i["ended_seconds"]]
    windows = [(max(start, i["started_seconds"]), min(stop, i["ended_seconds"])) for i in active]
    def covered(t):
        return any(a <= t < b for a, b in windows)
    overlap = sum(b - a for a, b in windows)
    previous = start
    max_gap = 0
    for a, b in windows:
        max_gap = max(max_gap, a - previous)
        previous = b
    voice = dict(overlapping_completed_utterances=len(active), request_onset=covered(start),
                 first_final_onset=covered(token) if token is not None else None,
                 first_sentence_onset=covered(sentence) if sentence is not None else None,
                 request_end=any(i["started_seconds"] <= stop <= i["ended_seconds"] for i in active), active_seconds=overlap,
                 active_fraction=overlap / (stop - start), largest_uncovered_seconds=max(max_gap, stop - previous))
    during = [s for s in samples if s["worker"] == row["pid"] and covered(s["clock"]) and
              s["worker_bytes"] > 0 and s["voice_bytes"] > 0]
    pairs = [s["worker_bytes"] + s["voice_bytes"] for s in during]
    memory = dict(mlx_allocator_peak_bytes=row["mlx_peak_bytes"], worker_lifetime_maxrss_bytes=row["rss_peak_bytes"],
                  active_paired_samples=len(pairs), active_paired_rss_peak_bytes=max(pairs, default=None),
                  active_worker_rss_peak_bytes=max((s["worker_bytes"] for s in during), default=None),
                  active_voice_rss_peak_bytes=max((s["voice_bytes"] for s in during), default=None))
    check(min(memory["mlx_allocator_peak_bytes"], memory["worker_lifetime_maxrss_bytes"]) > 0, "Missing memory peaks")
    def since(base):
        return dict(first_final=None if token is None else token-base, first_sentence=None if sentence is None else sentence-base,
                    terminal=stop-base)
    return dict(loaded_seconds=since(start), cold_seconds=since(launch) if row["repeat"] == 1 else None,
                cold_load_seconds=ready-load if row["repeat"] == 1 else None, gpu_drain_seconds=drained-stop,
                voice=voice, memory=memory, terminal_status=row["status"])


def summarize(root):
    measured = root / "measured"
    setup = read(measured / "setup.json")
    inventory = assets(root / "model", read(PILOTS / "inkling-six-spec.json"), setup)
    intervals, voice_end = verified_voice(root, setup)
    samples = [telemetry(s, setup["voice"]["pid"]) for s in lines(measured / "telemetry.jsonl")]
    check(samples and ordered([s["clock"] for s in samples]), "Telemetry missing or unordered")
    baseline = samples[0]
    rows = read(PILOTS / "sol-selected-six-v1.json")["rows"]
    attempts, gaps, workers = [], [], set()
    conditions = {key: [] for key in ("all_loaded_short", "warm_repeat_short", "cold_short")}
    previous = 0
    for case in rows:
        case_id, words = case["id"], case["source_words"]
        process = None
        for repeat in range(1, 4):
            label = f"{case_id}.{repeat}"
            path = measured / (label + ".answer.json")
            if not path.is_file():
                gaps.append(label + ": missing terminal receipt")
                continue
            row = read(path)
            check((row["id"], row["repeat"]) == (case_id, repeat), f"{label}: wrong receipt identity")
            identity = (row["pid"], row["process_launch"], row["model_ready"], row["load_start"])
            if process is None:
                check(identity not in workers and row["process_launch"] >= previous, f"{label}: unexpected process reuse")
                workers.add(identity)
                process = identity
            check(identity == process and row["submitted"] >= previous, f"{label}: repeats overlap or changed process")
            check(intervals[0]["ended_seconds"] <= row["process_launch"] and baseline["clock"] <= row["process_launch"],
                  f"{label}: voice warm-up or baseline followed model launch")
            previous = row["gpu_drained"]
            result = measure(row, samples, intervals)
            attempts.append(dict(case=case_id, source_words=words, repeat=repeat, **result))
            if any(row[k] is None for k in ("first_final", "first_sentence")):
                gaps.append(label + ": missing final text or sentence onset")
            if result["memory"]["active_paired_samples"] == 0:
                gaps.append(label + ": no paired RSS sample during active synthesis")
            if not result["voice"]["request_onset"] or result["voice"]["first_final_onset"] is not True:
                gaps.append(label + ": synthesis overlap unproven at request or first final text")
            if row["first_sentence"] is not None and not result["voice"]["first_sentence_onset"]:
                gaps.append(label + ": synthesis overlap unproven at first complete sentence")
            if not result["voice"]["request_end"]:
                gaps.append(label + ": synthesis overlap unproven at terminal")
            if words <= 300:
                for condition, seconds in [("all_loaded_short", result["loaded_seconds"]),
                                           ("warm_repeat_short", result["loaded_seconds"] if repeat > 1 else None),
                                           ("cold_short", result["cold_seconds"])]:
                    if seconds and seconds["first_sentence"] is not None:
                        conditions[condition].append((label, seconds["first_sentence"]))
    if not baseline["voice_bytes"] or any(s[k] is None for s in samples for k in ("swap_used_mib", "memory_free_pct")):
        gaps.append("Baseline voice RSS or host pressure/swap measurement missing")
    return dict(model_assets=inventory, attempts=attempts, measurement_gaps=gaps, voice_teardown=voice_end,
                short_sentence_bounds={k: dict(measured=len(v), above_3_seconds=[label for label, t in v if t > 3])
                                       for k, v in conditions.items()},
                host=dict(samples=len(samples), baseline_voice_rss_bytes=baseline["voice_bytes"],
                          baseline_free_pct=baseline["memory_free_pct"], baseline_swap_used_mib=baseline["swap_used_mib"],
                          minimum_free_pct=min((s["memory_free_pct"] for s in samples if s["memory_free_pct"] is not None), default=None),
                          maximum_swap_used_mib=max((s["swap_used_mib"] for s in samples if s["swap_used_mib"] is not None), default=None)),
                method=dict(clocks="Seconds on the same Mac uptime scale: mach_absolute_time and CLOCK_UPTIME_RAW. Sleep excluded.",
                            cold="Process launch to observation on repeat 1 per passage. File cache may be warm.",
                            loaded="Request submission to observed decoded final text, complete sentence or terminal. No audible output measured.",
                            voice="Overlap with completed synthesis calls that produced sustained PCM. Frames refer to entire utterances.",
                            memory="MLX allocator peak resets per attempt. Darwin maxrss is the process lifetime peak in bytes. "
                                   "Active RSS uses one ps call for both PIDs during synthesis. Its timestamp precedes ps. "
                                   "The paired RSS sum may double-count shared pages; it is not unique physical memory.",
                            assets="Pinned file sizes, excluding transport overhead, retries and runtime dependencies. "
                                   "Tensor hash was verified by the launcher. Metadata hashes were rechecked."))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence_root", type=Path)
    try:
        summary = summarize(parser.parse_args().evidence_root)
        print(json.dumps(summary, indent=2, allow_nan=False))
        sys.exit(1 if summary["measurement_gaps"] else 0)
    except (ValueError, OSError, KeyError, TypeError) as exc:
        sys.exit(f"Incomplete or invalid measurement evidence: {exc}")
