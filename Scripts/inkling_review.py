"""Build the blind six-passage packet and score its sealed, repeated occurrences."""
import argparse
import json
import secrets
import shutil
import sys
import tempfile
from pathlib import Path

from inkling_measure import FROZEN, PILOT, canonical, require, sha

BLIND, SCORER, FIXTURES, load = (PILOT[k] for k in ("BLIND", "SCORER", "FIXTURES", "load"))
TERRA_RECEIPT = PILOT["ROOT"] / "Qualification/Explain/recovery/selected.json"
TERRA_RECEIPT_SHA = "6f3636cff1b78fb553c25a2624952cb27ede8f1b3ebfa31aa2dd7d21c0fa0a31"
TERRA_ANSWERS_SHA = "6a84f9239f8516848915e6ea151c5202773f9194382797f271ff82f43a2a4785"
SENTINEL = "main-minutes-middle-metaphors"
GUIDES = ("RUBRIC.md", "RECOVERY-REVIEW.md")


def controls(path, digest, receipt_rows, expected_ids, arm):
    raw = path.read_bytes()
    require(sha(raw) == digest, f"{arm}: archived file digest differs")
    rows = [json.loads(line, object_pairs_hook=SCORER["unique_object"]) for line in raw.splitlines()]
    saved = {row["id"]: row for row in receipt_rows}
    require(len(saved) == len(receipt_rows) == len(rows) == len(expected_ids) and
            set(saved) == set(expected_ids) == {r["id"] for r in rows}, f"{arm}: wrong archived cases")
    result = []
    for row in rows:
        case_id = row["id"]
        ref = saved[case_id]
        require(sha(row["answer"].encode()) == row["answer_sha256"] == ref["answer_sha256"] and
                row["natural_stop"] is ref["natural_stop"] and row["request_sha256"] == ref["request_sha256"],
                f"{arm}/{case_id}: archived answer differs from receipt")
        result.append(dict(id=case_id, arm=arm, repeat=None, answer=row["answer"],
                           answer_sha256=row["answer_sha256"], natural_stop=row["natural_stop"], saved=ref))
    return result


def candidates(run, expected_ids):
    setup = load(run / "setup.json")
    require(setup["preview_sha256"] == FROZEN, "Run does not match the frozen preview")
    files = {f"{case}.{repeat}.answer.json" for case in expected_ids for repeat in (1, 2, 3)}
    require({p.name for p in run.glob("*.answer.json")} == files, "Expected exactly 18 candidate occurrences")
    records = []
    for case_id in expected_ids:
        for repeat in (1, 2, 3):
            path = run / f"{case_id}.{repeat}.answer.json"
            raw = path.read_bytes()
            row = json.loads(raw, object_pairs_hook=SCORER["unique_object"])
            require(row["id"] == case_id and type(row["repeat"]) is int and row["repeat"] == repeat and
                    sha(row["answer"].encode()) == row["answer_sha256"], f"{path.name}: incorrect answer binding")
            require(row["status"] in {"eos", "empty", "invalid-channel", "eof", "cap"},
                    f"{path.name}: unrecognized terminal status")
            records.append(dict(id=case_id, arm="inkling", repeat=repeat, answer=row["answer"],
                                answer_sha256=row["answer_sha256"], natural_stop=row["status"] == "eos",
                                status=row["status"], record_sha256=sha(raw)))
    return records


def inputs(run, archive):
    sol = PILOT["historical"]()
    PILOT["check_file"](TERRA_RECEIPT, TERRA_RECEIPT_SHA)
    ids = [r["id"] for r in sol["manifest"]["requests"]]
    records = candidates(run, ids)
    records += controls(archive / "sol-selected-six-v1/run/answers.jsonl", sol["answers_sha256"], sol["rows"], ids, "sol")
    records += controls(archive / "recovery-v1/selected/answers.jsonl", TERRA_ANSWERS_SHA, load(TERRA_RECEIPT)["rows"],
                        ids, "terra")
    cases, sources, facts, fixture_hash = SCORER["load_fixtures"](FIXTURES)
    return records, {c["id"]: c for c in cases if c["id"] in ids}, sources, facts, fixture_hash


def blind_items(records, cases, sources, facts, salt):
    # The prior blind labeler binds labels to a run and case. Use the answer digest as the run
    # identity here so identical answer bytes within a case get a single vote across all arms.
    data, occurrences = {}, {}
    for row in records:
        key = row["answer_sha256"], row["id"]
        case = cases[row["id"]]
        fixture = case["fixture"]
        if key in data:
            require(data[key][-1]["answer"] == row["answer"], "Answer digest collision")
        else:
            data[key] = ({"run_sha256": key[0]}, case, sources[fixture], facts[fixture], row)
        occurrences.setdefault(key, []).append({k: v for k, v in row.items() if k not in {"answer", "saved"}})
    items, labels = BLIND["make_items"](data, salt)
    return dict(sorted(items.items())), {label: occurrences[key] for label, key in labels.items()}


def packet(directory, records, cases, sources, facts):
    def material(salt):
        items, mapping = blind_items(records, cases, sources, facts, salt)
        return items, mapping, {"items": list(items.values())}
    if not directory.exists():
        directory.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory.parent) as tmp:
            stage = Path(tmp) / "review"
            public = stage / "public"
            stage.mkdir(mode=0o700)
            public.mkdir()
            salt = secrets.token_hex(32)
            _, mapping, content = material(salt)
            (stage / "private.json").write_bytes(canonical(dict(salt=salt, occurrences=mapping)))
            (public / "packet.json").write_bytes(canonical(content))
            for name in GUIDES:
                shutil.copyfile(FIXTURES / name, public / name)
            stage.rename(directory)
    sealed = load(directory / "private.json")
    items, mapping, content = material(sealed["salt"])
    public = directory / "public"
    require(sealed["occurrences"] == mapping and (public / "packet.json").read_bytes() == canonical(content),
            "Sealed occurrence map or packet changed")
    require({p.name for p in public.iterdir()} == {"packet.json", *GUIDES} and
            all((public / guide).read_bytes() == (FIXTURES / guide).read_bytes() for guide in GUIDES),
            "Blind packet guide or file inventory changed")
    return items, mapping


def vote_pair(items, first, second):
    a_id, a = BLIND["reader"](first, items)
    b_id, b = BLIND["reader"](second, items)
    require(a_id != b_id, "Two independent readers required")
    disputed = []
    for label, item in items.items():
        BLIND["validate_vote"](a[label], item)
        BLIND["validate_vote"](b[label], item)
        if BLIND["decision"](a[label]) != BLIND["decision"](b[label]):
            disputed.append(label)
    return (a_id, b_id), a, b, disputed


def resolutions(items, pair, third):
    readers, a, b, disputed = pair
    c = {}
    if third is not None:
        identity, c = BLIND["reader"](third, disputed)
        require(identity not in readers, "A distinct third reader is required")
    result = {}
    for label, item in items.items():
        decision, method = BLIND["resolve_votes"](item, a[label], b[label], c.get(label))
        cast = [a[label], b[label]] + ([c[label]] if label in c else [])
        reasons = list(dict.fromkeys(v["reason"] for v in ([c[label]] if label in c else cast) if v["reason"]))
        result[label] = dict(**decision, resolution=method, reasons=reasons,
                             vote_sha256=[BLIND["hashed"](v) for v in cast])
    return result


def calibration(label, final, attestation):
    binding = BLIND["hashed"]([label, final])
    status = "unreliable" if final["verdict"] == "pass" else "unresolved"
    if attestation is not None:
        SCORER["require_fields"](attestation, {"binding_sha256", "disposition", "reason"}, "sentinel assessment")
        require(attestation["binding_sha256"] == binding and attestation["disposition"] in
                {"credited", "uncertain", "rejected"} and isinstance(attestation["reason"], str) and
                attestation["reason"].strip(), "Assessment must describe this exact sentinel judgment")
        if attestation["disposition"] == "credited":
            status = "unreliable"
        elif final["verdict"] == "fail" and attestation["disposition"] == "rejected":
            require(attestation["reason"] in final["reasons"], "Cite the applicable final reader reason verbatim")
            status = "passed"
    return dict(label=label, binding_sha256=binding, verdict=final["verdict"], final_reasons=final["reasons"],
                status=status, assessment=attestation)


def score_attempt(row, final, case, sources, facts, fixture_hash, required):
    fixture = case["fixture"]
    source = sources[fixture]
    metrics = dict(id=case["id"], configuration_sha256=FROZEN, source_sha256=sha(source.encode()),
                   answer_sha256=row["answer_sha256"], source_words=len(source.split()),
                   answer_words=len(row["answer"].split()), natural_stop=row["natural_stop"],
                   **{k: final[k] for k in PILOT["REVIEW"]["SCORES"]})
    misses = []
    if metrics["answer_words"]:
        receipt = dict(schema_version=1, configuration_sha256=FROZEN, fixtures_sha256=fixture_hash,
                       observed_model="inkling", rows=[metrics])
        misses = SCORER["verify_receipt"](receipt, [case], sources, facts, FROZEN, fixture_hash,
                                          "inkling", required, record_negative=None)
    else:
        misses.append(f"{case['id']}: empty answer")
    matches = case["style"] == final["perceived_style"]
    if not matches:
        misses.append(f"{case['id']}: style mismatch")
    result = dict(**metrics, repeat=row["repeat"], fidelity=final["verdict"], style_match=matches,
                  expected_style=case["style"], perceived_style=final["perceived_style"],
                  middle_shorter=(metrics["answer_words"] < metrics["source_words"]) if case["depth"] == "middle" else None,
                  missing_required_facts=sorted(set(required[fixture]) & set(final["missing_facts"])),
                  terminal_status=row.get("status"), quality_pass=not misses, misses=misses)
    if fixture == "document3000":
        result["long_exceptions"] = {name: index in final["covered_facts"]
                                     for index, name in enumerate(("first", "middle", "last"))}
    return result


def score(records, mapping, resolved, cases, sources, facts, fixture_hash, attestation):
    labels = {(r["arm"], r["id"], r["repeat"]): label for label, rows in mapping.items() for r in rows}
    required = SCORER["read_required_facts"](facts, FIXTURES)
    attempts, comparisons = [], []
    for row in records:
        label = labels[row["arm"], row["id"], row["repeat"]]
        final = resolved[label]
        if row["arm"] == "inkling":
            attempt = score_attempt(row, final, cases[row["id"]], sources, facts, fixture_hash, required)
            attempts.append(dict(**attempt, resolution=final["resolution"], label=label, reasons=final["reasons"]))
        else:
            saved = BLIND["decision"](row["saved"])
            fresh = BLIND["decision"](final)
            comparisons.append(dict(arm=row["arm"], id=row["id"], label=label, answer_sha256=row["answer_sha256"],
                                    saved=saved, fresh=fresh, changed=[k for k in sorted(saved) if saved[k] != fresh[k]]))
    sentinel = labels["terra", SENTINEL, None]
    calibrated = calibration(sentinel, resolved[sentinel], attestation)
    per_repeat = {str(rep): sum(a["quality_pass"] for a in attempts if a["repeat"] == rep) for rep in (1, 2, 3)}
    changes = {}
    for case_id in cases:
        hashes = [a["answer_sha256"] for a in attempts if a["id"] == case_id]
        changes[case_id] = {"ordered_answer_sha256": hashes, "identical": len(set(hashes)) == 1}
    passes = sum(per_repeat.values())
    return dict(original_occurrences=len(records), distinct_outputs=len(mapping), quality_passes=passes,
                quality_gate="pass" if passes == 18 and calibrated["status"] == "passed" else "hold",
                calibration=calibrated, passed_cases_per_repeat=per_repeat, repeat_changes=changes,
                attempts=attempts, historical_comparisons=comparisons)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    for action in ("packet", "disputes", "score"):
        sub = commands.add_parser(action)
        for arg in ("run", "archive", "out"):
            sub.add_argument("--" + arg, type=Path, required=True)
        if action != "packet":
            for arg in ("first", "second"):
                sub.add_argument("--" + arg, type=Path, required=True)
        if action == "score":
            sub.add_argument("--third", type=Path)
            sub.add_argument("--calibration", type=Path)
    args = parser.parse_args()
    records, cases, sources, facts, fixture_hash = inputs(args.run, args.archive)
    if args.action != "packet":
        require((args.out / "private.json").is_file(), "Create the blind packet before resolving any votes")
    items, mapping = packet(args.out, records, cases, sources, facts)
    if args.action == "packet":
        print(args.out / "public")
        return
    pair = vote_pair(items, load(args.first), load(args.second))
    if args.action == "disputes":
        result = {"items": [items[label] for label in pair[-1]]}
    else:
        resolved = resolutions(items, pair, load(args.third) if args.third else None)
        result = score(records, mapping, resolved, cases, sources, facts, fixture_hash,
                       load(args.calibration) if args.calibration else None)
    print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        sys.exit(str(error))
