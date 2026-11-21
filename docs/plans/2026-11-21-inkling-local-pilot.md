# Test Inkling 2 Mini on six Cáptalo Explain passages

**Decision to support.** Is one fixed, offline Inkling configuration faithful enough and fast enough on Juan’s M5 Ultra to justify the larger adult Explain qualification? Juan selected a six-case stopping point on November 21. The deliverable is a score out of six, the reason for each miss, cold/warm timing, peak memory with the voice ready, and a next-gate decision. A documented negative result completes the experiment.

## Candidate and design choices

Use original Thinking Machines weights, a text-only Python MLX process and the existing selected Explain instructions. This measures one local generator with the exact passages on which Terra and Sol each passed four cases. A blind comparison can reveal a changed condition or missing fact even when an answer sounds convincing. The model receives the passage and listener settings. Only reviewers receive the fact sheet. The released three-pass model is the candidate. A variable-loop checkpoint, smaller conversion, verifier role, or Swift app integration would answer a different question. [Accepted assessment](../research/2026-11-21-inkling-2-mini-assessment.md#L27) · [Historical pilot](2026-11-21-explain-qualification-recovery-notes.md#L60)

| Choice | Reason |
| --- | --- |
| Original mixed-precision weights via MLX | Uses one model process on Apple silicon and permits direct observation of token boundaries and memory. Hugging Face documents original-weight support. On November 21 the matching MLX-LM implementation was an open draft PR. Pin its tested source revision and verify it offline before admitting scored inputs. [Runtime guide](https://huggingface.co/blog/inkling2mini#mlx) · [MLX-LM implementation and original-weight example](https://github.com/ml-explore/mlx-lm/pull/2086) |
| Ollama or smaller GGUF | Convenient for a later install or a lower-memory trial. A different package, runtime or quantization confounds this first comparison. |
| Existing six-case selection | Four Middle Metaphors and two Simple Plain cases include the historic approval error, the label omission and the distant exceptions in 3,000 words. The pilot has limited coverage of depth, style and short-input lengths. [Ordered case and request identities](../../Qualification/Explain/model-pilots/sol-selected-six-v1.json#L1) |

## Phases and acceptance

| Phase | Deliverable | Acceptance |
| --- | --- | --- |
| [1. Freeze and rehearse](2026-11-21-inkling-local-pilot-phases/phase-1.md) | A test command, fixture-only regression tests and a six-row preview | Reproduce the selected input bytes, blind controls, offline refusal, output boundaries and scoring rules before downloading weights. |
| [2. Run once offline](2026-11-21-inkling-local-pilot-phases/phase-2.md) | An integrity-checked runtime and a private run with six attempt records | Demonstrate sandbox enforcement, voice readiness, six independent contexts, truthful stop reasons, clock and memory evidence. Preserve incomplete runs. |
| [3. Score blind and decide](2026-11-21-inkling-local-pilot-phases/phase-3.md) | Two independent reviews, adjudication where needed, and a concise versioned result | Rebuild the verdict from saved evidence. All six must pass quality. Report runtime feasibility separately. |

One integration owner works locally. Execute and accept phases in order. For behavioral tooling use a failing fixture first, independent review, repair, simplify and sequential `make verify` after each phase. Existing script-test discovery covers deterministic tests. Keep downloads, inference and human judgments outside normal verification. A completed pilot requires no modification to the installed app. [Script-test entry](../../Makefile#L125) · [Verification policy](../../.rpi/policy.json#L140)

## Consumer sweep

The proposed command reads existing contracts and writes a new pilot record under its own experiment identity. Preserve the inputs and the meaning of every existing provider receipt. Searches on the integration baseline included `rg -n 'prepared.json|recovery_packet|sol-selected-six-v1|verify_receipt|requestBody\(' Scripts Packages Tests Qualification` and `rg --files --hidden --no-ignore .local/archive | rg 'sol-selected-six-v1/.*/answers.jsonl'`.

| Producer or consumer | Treatment |
| --- | --- |
| [Swift serializer](../../Packages/CaptaloCore/Sources/CaptaloCore/Explain/ExplainCandidate.swift#L58), [probe](../../Packages/CaptaloCore/Sources/ExplainQualificationProbe/main.swift#L22), [prepare command](../../Scripts/explain-candidate#L65) | Phase 1 verifies the selected serialized bodies against the historical hashes and adapts only the two text fields to Inkling. |
| [Review packet and vote checks](../../Scripts/explain_recovery_review.py#L100), [adjudication](../../Scripts/explain_recovery_review.py#L58), [quality scorer](../../Scripts/explain-qualify#L84), [style check](../../Scripts/explain_recovery_review.py#L306) | Phases 1 and 3 reuse compatible logic and assert parity with historical cases. Keep the new identity outside the fixed cloud-arm registry. |
| [Cloud dispatcher](../../Scripts/explain-qualification-run#L1), [cloud review CLI](../../Scripts/explain-qualification-review#L1), [comparison rehearsal](../../Scripts/tests/rehearse_explain_recovery.py#L1), [historical receipt discovery](../../Scripts/explain-qualify#L213) | Read-only references. The local command never dispatches a provider request or writes into a cloud run directory. Existing rehearsals and receipts remain verification oracles. |
| [Sandbox harness](../../Scripts/offline-test#L45), [voice readiness](../../Packages/CaptaloSpeech/Sources/CaptaloSpeech/VoiceSetup.swift#L41), archived Sol answers | Phase 2 uses the deny-outbound technique and the voice readiness contract. Phase 3 reads archived synthetic answers as blind controls. |

## Stuck states and recovery

The test operator sees the case or artifact identity, the failed check and the action below. The listener-facing app has no pilot state.

| State | Visible disposition and recovery | Required evidence |
| --- | --- | --- |
| Missing or altered fixture, selected body, checkpoint file, runtime or blind control | Name the path and expected digest. Regenerate prepared requests or restore the exact artifact. Stop setup if the pin cannot be obtained. | Damage one of each, confirm rejection before generation, restore it and confirm successful validation. |
| Asset download interrupted, disk full or runtime incompatible | Mark setup incomplete, keep the partial transfer isolated, resume the pinned download after capacity returns or report the exact incompatible dependency. | Truncated-file rehearsal, clean checksum and smoke test required before recording a case. |
| Voice unavailable, sandbox ineffective or network attempt | Hold measured execution, identify the voice or control failure, repair owned setup and repeat the controls. Report an unexplained termination as such. | Positive and denied network controls, missing-voice rehearsal, successful offline neutral smoke. |
| Duplicate launch, exception, process kill or measurement loss | Identify the reserved run and affected row. Preserve partial evidence. Resume only unused rows if the original protocol and cold/warm conditions can be reproduced. Otherwise report incomplete. | Interrupt after reservation, attempt a second start and verify no duplicate score or hidden reroll. Remove a timing field and verify the performance verdict is withheld. |
| Length cap, refusal, invalid channel or no speakable sentence | Preserve the status and count it as a candidate miss when attributable to model output. A demonstrated harness fault makes the run incomplete. | Fixture streams for valid EOS, truncation, thinking-only, malformed output and explicit refusal. |
| Missing, mismatched or disputed vote | Print the affected blinded labels and give the same private packet to the required reader. Recompute offline when their bound vote arrives. | Replay missing labels, duplicates, stale answer hashes and disagreements with and without valid adjudication. |
| Genuine quality miss, valid timing overrun or insufficient evidence | Publish the observed case result locally and use the decision table in Phase 3. A changed configuration is a new experiment. | Rehearse pass, fail, timing hold and incomplete outcomes with synthetic records. |

## Handoff

Planning baseline is local develop at `818990757ea7ae879f1c0c3effc58bdcda26b720` in `/Users/juan/code/captalo`. Graphify located the qualification probe, scorer and packet builders. Direct source and a SHA-256 check located all six historical Sol answers in the integration checkout’s private archive. The former Explain worktree has been removed. The host reported macOS 27.2.1 (26B131), M5 Ultra and 96 GiB. The optional project plan overlay was absent. Planning allocated no runtime or model assets. On resumption, revalidate the branch, evidence archive, available disk and model/runtime identities. The next authorized workflow, if requested, starts with Phase 1. The plan’s terminal decision is eligibility for a separately authorized 83-case adult qualification and native audio timing.
