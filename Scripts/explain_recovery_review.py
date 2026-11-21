"""Blind comparison of the fixed recovery runs. Loaded with the existing review/scorer tools."""

import hmac
import os
import re
import secrets
import shutil
import tempfile
from pathlib import Path

GROUPS = {"pair": ("control", "selected"), "example": ("example",),
          "selected-full": ("selected-full",), "example-full": ("example-full",)}
STYLES = {"plain", "examples", "metaphors", "picture", "indeterminate"}
DECISIONS = SCORES | {"perceived_style"}


def hashed(value):
    return sha(canonical(value))


def decision(vote):
    return {name: sorted(vote[name]) if name in {"covered_facts", "missing_facts"} else vote[name]
            for name in DECISIONS}


def validate_scores(vote, facts):
    require(vote["verdict"] in {"pass", "fail", "uncertain"} and vote["perceived_style"] in STYLES,
            "invalid verdict or perceived style")
    require(all(type(vote[name]) is bool for name in ("ambiguous", "near_verbatim")), "invalid flags")
    for name in ("covered_facts", "missing_facts"):
        require(isinstance(vote[name], list) and all(type(i) is int for i in vote[name]), "invalid fact indices")
    require(sorted(vote["covered_facts"] + vote["missing_facts"]) == list(range(len(facts))),
            "fact dispositions must cover every index exactly once")


def validate_vote(vote, item, *, adjudicator=False):
    fields = BINDINGS | DECISIONS | {"reason"}
    SCORER["require_fields"](vote, fields | ({"source_quote"} if adjudicator else set()), "reader vote")
    require(all(vote[k] == item[k] for k in BINDINGS), f"{item['label']}: unbound vote")
    validate_scores(vote, item["facts"])
    require(isinstance(vote["reason"], str) and (vote["reason"].strip() or
            (vote["verdict"] == "pass" and not vote["ambiguous"] and not adjudicator)), "a reason is required")
    if adjudicator:
        quote = vote["source_quote"]
        require(isinstance(quote, str) and quote.strip() and quote in item["source"], "quote the source exactly")


def preserves_agreement(first, second, final):
    for name in DECISIONS:
        if name in ("covered_facts", "missing_facts"):
            if not (set(first[name]) & set(second[name])) <= set(final[name]):
                return False
        elif first[name] == second[name] and final[name] != first[name]:
            return False
    return True


def resolve_votes(item, first, second, third):
    validate_vote(first, item)
    validate_vote(second, item)
    a, b = decision(first), decision(second)
    if a == b:
        require(third is None, f"{item['label']}: unexpected adjudication")
        return a, "agreed"
    require(third is not None, f"{item['label']}: independent adjudication required")
    validate_vote(third, item, adjudicator=True)
    final = decision(third)
    require(preserves_agreement(a, b, final),
            f"{item['label']}: adjudication changed an agreed judgment")
    return final, "adjudicated"


def recovery_decision(arm, cases, misses):
    if not misses:
        return "pass"
    eligible = {f"{case['id']}: {why}" for case in cases if case["depth"] == "middle" and case["style"] == "metaphors"
                for why in ("style mismatch", "Middle answer must be shorter")}
    return "example-eligible" if arm == "selected" and set(misses) <= eligible else "fail"


def recovery_data(root, group):
    cases, sources, facts, _ = SCORER["load_fixtures"](root / "Tests/ExplainQualification")
    by_id = {c["id"]: c for c in cases if c["suite"] != "learner-blocked"}
    data = {}
    manifest = RUNNER["recovery_manifest"](root)
    for arm in GROUPS[group]:
        _, identity, requests = RUNNER["recovery_context"](root, arm)
        answers = RUNNER["verified_recovery_answers"](root, arm, manifest)
        for request in requests:
            case = by_id[request["id"]]
            fixture = case["fixture"]
            data[arm, case["id"]] = (identity, case, sources[fixture], facts[fixture], answers[case["id"]])
    return data


def review_directory(root, group):
    return root / ".local/explain-qualification/recovery-v1/reviews" / group


def make_items(data, salt):
    require(isinstance(salt, str) and re.fullmatch("[a-f0-9]{64}", salt), "invalid private label key")
    items, identities = {}, {}
    for (arm, case_id), (run, _, source, facts, ans) in data.items():
        label = hmac.digest(bytes.fromhex(salt), canonical([run["run_sha256"], case_id]), "sha256").hex()[:24]
        require(label not in items, "duplicate review label")
        item = dict(label=label, source=source, facts=facts, answer=ans["answer"], answer_sha256=ans["answer_sha256"])
        item["item_sha256"] = hashed(item)
        items[label], identities[label] = item, (arm, case_id)
    return items, identities


def public_packet(root, review):
    salt = load(review / "private-key.json")
    token = hmac.digest(bytes.fromhex(salt), b"reviewer packet directory", "sha256").hex()[:24]
    target = root / ".local/reader-packets" / token
    private_copy = review / "reviewer"
    if not target.exists():
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=target.parent) as temp:
            stage = Path(temp) / "packet"
            shutil.copytree(private_copy, stage)
            stage.rename(target)
    files = ("packet.json", "RUBRIC.md", "RECOVERY-REVIEW.md")
    require({p.name for p in target.iterdir()} == set(files) and
            all((target / n).read_bytes() == (private_copy / n).read_bytes() for n in files),
            "shared blind packet differs from the private review copy")
    return target


def recovery_packet(root, group):
    root = Path(root)
    review = review_directory(root, group)
    data = recovery_data(root, group)
    if review.exists():
        checked_packet(root, group, data)
        return public_packet(root, review)
    review.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=review.parent) as temp:
        stage = Path(temp) / "packet"
        public = stage / "reviewer"
        public.mkdir(parents=True)
        salt = secrets.token_hex(32)
        items = list(make_items(data, salt)[0].values())
        secrets.SystemRandom().shuffle(items)
        (public / "packet.json").write_bytes(encoded({"items": items}))
        (stage / "private-key.json").write_bytes(encoded(salt))
        for name in ("RUBRIC.md", "RECOVERY-REVIEW.md"):
            shutil.copyfile(root / "Tests/ExplainQualification" / name, public / name)
        stage.rename(review)
    return public_packet(root, review)


def checked_packet(root, group, data):
    review = review_directory(root, group)
    public = review / "reviewer"
    for name in ("RUBRIC.md", "RECOVERY-REVIEW.md"):
        require((public / name).read_bytes() == (root / "Tests/ExplainQualification" / name).read_bytes(),
                f"reviewed {name} differs from the frozen guide")
    expected, identities = make_items(data, load(review / "private-key.json"))
    packet = load(public / "packet.json")["items"]
    require(len(packet) == len(expected) and {x["label"]: x for x in packet} == expected,
            "review packet differs from its exact runs")
    return expected, identities


def reader(envelope, expected):
    SCORER["require_fields"](envelope, {"reviewer", "votes"}, "review file")
    name = envelope["reviewer"]
    require(isinstance(name, str) and name.strip() and name == name.strip(), "invalid reviewer identifier")
    votes = envelope["votes"]
    require(isinstance(votes, list), "expected a list of votes")
    by_label = {vote["label"]: vote for vote in votes}
    require(len(votes) == len(by_label), "duplicate vote")
    missing = sorted(set(expected) - set(by_label))
    require(not missing and set(expected) == set(by_label), f"incorrect review coverage, missing labels {missing}")
    return sha(name.encode()), by_label


def vote_binding(identity, row, vote):
    metrics = {k: row[k] for k in ("id", "source_sha256", "source_words", "answer_sha256", "answer_words",
                                    "request_sha256", "natural_stop")}
    public_vote = {k: v for k, v in vote.items() if k != "binding_sha256"}
    return hashed([identity["run_sha256"], metrics, public_vote])


def receipts_for(root, group, first, second, adjudications):
    data = recovery_data(root, group)
    items, key = checked_packet(root, group, data)
    public_packet(root, review_directory(root, group))
    r1, a = reader(first, items)
    r2, b = reader(second, items)
    require(r1 != r2, "two independent reviewers are required")
    disputed = []
    for label, item in items.items():
        validate_vote(a[label], item)
        validate_vote(b[label], item)
        if decision(a[label]) != decision(b[label]):
            disputed.append(label)
    require(adjudications is not None or not disputed, f"independent adjudication required on labels {sorted(disputed)}")
    r3, c = reader(adjudications, disputed) if adjudications is not None else (None, {})
    require(r3 not in (r1, r2), "a distinct adjudicator is required")
    receipts = {}
    by_case = {case: label for label, case in key.items()}
    for (arm, case_id), (identity, case, source, facts, ans) in data.items():
        label = by_case[arm, case_id]
        final, disposition = resolve_votes(items[label], a[label], b[label], c.get(label))
        cast = [(r1, a[label]), (r2, b[label])]
        if label in c:
            cast.append((r3, c[label]))
        row = dict(id=case_id, configuration_sha256=identity["configuration_sha256"], source_sha256=sha(source.encode()),
                   source_words=len(source.split()), answer_sha256=ans["answer_sha256"], answer_words=len(ans["answer"].split()),
                   request_sha256=ans["request_sha256"], natural_stop=True, adjudication=disposition,
                   judgments=[dict(**decision(v), reviewer_sha256=r, vote_sha256=hashed(v)) for r, v in cast], **final)
        for vote in row["judgments"]:
            vote["binding_sha256"] = vote_binding(identity, row, vote)
        receipt = receipts.setdefault(arm, dict(schema_version=2, identity=identity, rows=[]))
        receipt["rows"].append(row)
    return receipts


def publish(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=path.parent) as temp:
        new = Path(temp) / "result"
        new.write_bytes(encoded(content))
        try:
            os.link(new, path)
        except FileExistsError:
            require(path.read_bytes() == new.read_bytes(), f"{path.name} already exists with different evidence")


def recovery_receipts(root, group, first, second, adjudications=None):
    root = Path(root)
    envelopes = [load(p) if p is not None else None for p in (first, second, adjudications)]
    results = receipts_for(root, group, *envelopes)
    for arm, receipt in results.items():
        verify_portable(root, arm, receipt)
    private = review_directory(root, group)
    for filename, envelope in zip(("reader-1.json", "reader-2.json", "adjudication.json"), envelopes):
        if envelope is not None:
            publish(private / filename, envelope)
    for arm, receipt in results.items():
        publish(root / "Qualification/Explain/recovery" / f"{arm}.json", receipt)
    return results


def verified_outcome(root, arm):
    root = Path(root)
    group = "pair" if arm in GROUPS["pair"] else arm
    review = review_directory(root, group)
    third = review / "adjudication.json"
    results = receipts_for(root, group, load(review / "reader-1.json"), load(review / "reader-2.json"),
                           load(third) if third.exists() else None)
    for member, receipt in results.items():
        require(load(root / "Qualification/Explain/recovery" / f"{member}.json") == receipt,
                f"{member}: portable receipt differs from the reviewed run")
    return verify_portable(root, arm, results[arm])[0]


def verify_portable(root, arm, receipt):
    """Check a sanitized record against only versioned fixtures, instructions and requests."""
    root = Path(root)
    fixtures = root / "Tests/ExplainQualification"
    all_cases, sources, facts, fixture_hash = SCORER["load_fixtures"](fixtures)
    config_name = RUNNER["recovery_candidate_name"](arm)
    config_path = root / "Qualification/Explain/candidates" / f"{config_name}.json"
    config = load(config_path)
    config_hash = sha(config_path.read_bytes())
    require(config["fixtures_sha256"] == fixture_hash and config["instruction_sha256"] == sha(config["instruction"].encode()),
            "configuration no longer matches frozen fixtures or instruction")
    full = arm.endswith("-full")
    cases = [c for c in all_cases if c["suite"] != "learner-blocked" and
             (full or (c["suite"] == "corpus" and c["id"] in RUNNER["PILOT_CASES"]))]
    ids = [c["id"] for c in cases]
    require(len(ids) == (83 if full else 6), "invalid recovery case inventory")
    identity = RUNNER["recovery_identity"](root, arm, config, config_hash, ids)
    SCORER["require_fields"](receipt, {"schema_version", "identity", "rows"}, "recovery receipt")
    require(type(receipt["schema_version"]) is int and receipt["schema_version"] == 2, "expected prospective v2 receipt")
    require(receipt["identity"] == identity, f"{arm}: wrong receipt identity")
    rows = receipt["rows"]
    require(isinstance(rows, list) and [row["id"] for row in rows] == ids, f"{arm}: incorrect receipt cohort or order")
    legacy_rows, misses = [], []
    for case, row in zip(cases, rows):
        SCORER["require_fields"](row, SCORER["ROW_FIELDS"] | {"request_sha256", "perceived_style", "judgments", "adjudication"},
                                 "recovery row")
        case_id = case["id"]
        require(re.fullmatch("[0-9a-f]{64}", row["request_sha256"]), f"{case_id}: invalid request digest")
        if "request_sha256" in config:
            require(row["request_sha256"] == config["request_sha256"][case_id], f"{case_id}: changed wire digest")
        votes = row["judgments"]
        require(isinstance(votes, list) and len(votes) in (2, 3), f"{case_id}: invalid reviewer count")
        for vote in votes:
            SCORER["require_fields"](vote, DECISIONS | {"reviewer_sha256", "vote_sha256", "binding_sha256"}, "sanitized judgment")
            require(all(re.fullmatch("[0-9a-f]{64}", vote[key]) for key in ("reviewer_sha256", "vote_sha256")),
                    f"{case_id}: invalid reviewer binding")
            require(vote["binding_sha256"] == vote_binding(identity, row, vote), f"{case_id}: unbound sanitized vote")
            validate_scores(vote, facts[case["fixture"]])
        require(len({v["reviewer_sha256"] for v in votes}) == len(votes), f"{case_id}: duplicate reviewer")
        a, b = [decision(v) for v in votes[:2]]
        agreed = a == b
        require(len(votes) == (2 if agreed else 3) and row["adjudication"] == ("agreed" if agreed else "adjudicated"),
                f"{case_id}: missing or spurious adjudication")
        final = decision(votes[-1])
        require(decision(row) == final and preserves_agreement(a, b, final),
                f"{case_id}: final judgment differs from review")
        if final["perceived_style"] != case["style"]:
            misses.append(f"{case_id}: style mismatch")
        legacy_rows.append({k: row[k] for k in SCORER["ROW_FIELDS"]})
    require(len({tuple(v["reviewer_sha256"] for v in r["judgments"][:2]) for r in rows}) == 1,
            f"{arm}: independent reader identities changed within the review")
    if arm == "control":
        # The sealed v1 control predates per-wire hashes. This binds the six reviewed wire bytes from cd9510b.
        wires = {r["id"]: r["request_sha256"] for r in rows}
        require(hashed(wires) == "4ac624894730ad6654b96fc7a15d00707b4a61ed6e783006d9d9f651ee70e5ad",
                "control wire digests differ from the frozen repeat")
    base = dict(schema_version=1, configuration_sha256=config_hash, fixtures_sha256=fixture_hash,
                observed_model=identity["model"], rows=legacy_rows)
    required = SCORER["read_required_facts"](facts, fixtures)
    misses.extend(SCORER["verify_receipt"](base, cases, sources, facts, config_hash, fixture_hash, config["revision"],
                                          required, record_negative=None))
    failed = {m.split(":", 1)[0] for m in misses}
    cohorts = {suite: (sum(c["id"] not in failed for c in cases if c["suite"] == suite),
                       sum(c["suite"] == suite for c in cases)) for suite in ("corpus", "held-out")}
    return recovery_decision(arm, cases, misses), misses, cohorts


def comparison_summary(row):
    if row is None:
        return "unavailable"
    return (f"{row['verdict']}, words {row['answer_words']}/{row['source_words']}, "
            f"style {row.get('perceived_style', 'unmeasured')}, "
            f"ambiguous {row['ambiguous']}, missing facts {row['missing_facts']}, "
            f"natural stop {row['natural_stop']}, near-verbatim {row['near_verbatim']}")


def portable_outcomes(root):
    root = Path(root)
    records = root / "Qualification/Explain/recovery"
    outcomes = {}
    receipts = {}
    for path in sorted(records.glob("*.json")):
        arm = path.stem
        require(any(arm in group for group in GROUPS.values()), "unrecognized recovery receipt")
        receipts[arm] = load(path)
        outcome, misses, cohorts = verify_portable(root, arm, receipts[arm])
        outcomes[arm] = outcome
        counts = ", ".join(f"{suite} {passed}/{total}" for suite, (passed, total) in cohorts.items() if total)
        print(f"OpenAI recovery {arm} {receipts[arm]['identity']['configuration_sha256']}: {outcome} ({counts})")
        for miss in misses:
            print(f"  {miss}")
    if "control" in outcomes and "selected" in outcomes:
        control = receipts["control"]
        require([v["reviewer_sha256"] for v in control["rows"][0]["judgments"][:2]] ==
                [v["reviewer_sha256"] for v in receipts["selected"]["rows"][0]["judgments"][:2]],
                "inconsistent paired reader identities")
        history_dir = root / "Qualification/Explain/tuning" / control["identity"]["configuration_sha256"]
        history = history_dir / (control["identity"]["subset_sha256"] + ".json")
        rows = load(history)["receipt"]["rows"] if history.exists() else []
        previous = {r["id"]: r for r in rows}
        for base, treatment in zip(control["rows"], receipts["selected"]["rows"]):
            case_id = base["id"]
            old = previous.get(case_id)
            print(f"{case_id}: historical {comparison_summary(old)} | repeat {comparison_summary(base)} | selected {comparison_summary(treatment)}")
    if "example" in outcomes:
        require("control" in outcomes and outcomes.get("selected") == "example-eligible", "example has no eligible pilot")
    full_runs = [arm for arm in outcomes if arm.endswith("-full")]
    require(len(full_runs) <= 1, "multiple full runs for one experiment")
    for arm in full_runs:
        require("control" in outcomes and outcomes.get(arm.removesuffix("-full")) == "pass",
                "full run requires a passing treatment pilot and reviewed control")
    return outcomes
