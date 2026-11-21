"""Weight-free, deliberately fabricated input to the pilot's blind-review contracts."""
from copy import deepcopy


def exercise(pilot, fault):
    blind, scorer = pilot["BLIND"], pilot["SCORER"]
    fixtures = pilot["FIXTURES"]
    sha, require = pilot["sha"], pilot["require"]
    sol = pilot["historical"]()
    cases, sources, facts, fixture_hash = scorer["load_fixtures"](fixtures)
    ids = [row["id"] for row in sol["manifest"]["requests"]]
    by_id = {case["id"]: case for case in cases}
    six = [by_id[key] for key in ids]
    required = scorer["read_required_facts"](facts, fixtures)
    config = sha(b"fabricated Inkling rehearsal")
    data = {}
    for arm in ("candidate", "control"):
        identity = {"run_sha256": sha(arm.encode())}
        for case in six:
            key = case["id"]
            fixture = case["fixture"]
            text = "The report describes a room." if arm == "candidate" else "The report mentions a room."
            if arm == "candidate" and key == ids[0] and fault in ("refusal", "miss-and-missing-time"):
                text = "I cannot explain this."
            ans = dict(answer=text, answer_sha256=sha(text.encode()))
            data[arm, key] = (identity, case, sources[fixture], facts[fixture], ans)

    items, private = blind["make_items"](data, "a" * 64)
    votes = []
    for label in sorted(items):
        item = items[label]
        arm, key = private[label]
        vote = {name: item[name] for name in ("label", "item_sha256", "answer_sha256")}
        # These scripted votes test the join. They do not judge answer quality.
        vote.update(verdict="pass", perceived_style=by_id[key]["style"], near_verbatim=False,
                    ambiguous=False, covered_facts=list(range(len(item["facts"]))), missing_facts=[], reason="")
        if arm == "control" or (key == ids[0] and fault in ("refusal", "miss-and-missing-time")):
            vote.update(verdict="fail", reason="Synthetic rejection exercising arm isolation.")
        votes.append(vote)
    first = {"reviewer": "reader A", "votes": votes}
    second = {"reviewer": "reader B", "votes": deepcopy(votes)}
    candidate = next(v for v in second["votes"] if private[v["label"]] == ("candidate", ids[0]))
    third = None
    if fault == "stale-vote":
        candidate["answer_sha256"] = sha(b"another run")
    elif fault == "duplicate-vote":
        second["votes"].append(candidate)
    elif fault == "missing-vote":
        second["votes"].remove(candidate)
    elif fault in ("adjudication", "missing-adjudication"):
        final = dict(candidate, source_quote=items[candidate["label"]]["source"].split()[0],
                     reason="Synthetic adjudication of the disputed style.")
        candidate["perceived_style"] = "indeterminate"
        if fault == "adjudication":
            third = {"reviewer": "reader C", "votes": [final]}

    # Use the same opaque labels, bindings and independent vote resolution as recovery reviews.
    r1, a = blind["reader"](first, items)
    r2, b = blind["reader"](second, items)
    require(r1 != r2, "Distinct reviewers required")
    disputes = {label for label in items if blind["decision"](a[label]) != blind["decision"](b[label])}
    r3, c = blind["reader"](third, disputes) if third else (None, {})
    require(r3 not in (r1, r2), "Distinct adjudicator required")
    rows, misses = [], []
    for label, item in items.items():
        final, _ = blind["resolve_votes"](item, a[label], b[label], c.get(label))
        arm, key = private[label]
        if arm != "candidate":
            continue
        style = final.pop("perceived_style")
        if style != by_id[key]["style"]:
            misses.append(f"{key}: style mismatch")
        rows.append(dict(final, id=key, configuration_sha256=config, source_sha256=sha(item["source"].encode()),
                         source_words=len(item["source"].split()), answer_words=len(item["answer"].split()),
                         answer_sha256=item["answer_sha256"], natural_stop=not (fault == "cap" and key == ids[0])))
    receipt = dict(schema_version=1, configuration_sha256=config, fixtures_sha256=fixture_hash,
                   observed_model="fabricated", rows=rows)
    misses.extend(scorer["verify_receipt"](receipt, six, sources, facts, config, fixture_hash,
                                          "fabricated", required, record_negative=None))
    observations = [dict(source_words=len(sources[case["fixture"]].split()), first_sentence_seconds=1,
                         mlx_peak_bytes=80, rss_peak_bytes=100) for case in six]
    if fault in ("missing-time", "miss-and-missing-time"):
        del observations[-1]["first_sentence_seconds"]
    timing = pilot["performance"](observations, 2.01 if fault == "late" else 2.0)
    return dict(evidence="fabricated rehearsal", candidate_cases=len(rows), blind_items=len(items),
                misses=misses, outcome="quality-miss" if misses else timing)
