# Offline test of an Explain verifier

**Decision, 2026-11-21.** Keep Explain on hold. Apple's on-device model, asked to check a complete explanation against its source, allowed seven of eight fresh faulty answers through. On the saved minutes it accepted the statement that the east door gets painted when the source only recorded approval for paint. The verifier alone also took more than three seconds in three trials. This candidate fails the quality criterion before app integration.

## Method

The [sentence-grounding assessment](2026-11-21-explain-sentence-grounding-assessment.md) set the test. Reject both historical errors, accept both faithful counterparts, and distinguish faithful and faulty explanations on unseen synthetic variants without a fixture answer key at runtime. Four historical answers were recovered byte for byte and checked against the [Terra receipt](../../Qualification/Explain/recovery/selected.json) and [Sol receipt](../../Qualification/Explain/model-pilots/sol-selected-six-v1.json). Historical expectations use the [blind review verdicts](../plans/2026-11-21-explain-qualification-recovery-notes.md#L62).

The candidate was Apple's installed Foundation Models framework on arm64 macOS 27.2.1 (26B131), using the default on-device model and greedy sampling. Each of 20 shuffled rows started a fresh session. Its only case inputs were the source and the proposed spoken explanation. The generic instructions asked for a short reason and separate fidelity and coverage verdicts. Fidelity requires that the source support every factual claim. Coverage requires that the listener hear every essential point, while allowing incidental background to be omitted. Acceptance requires two passes. An invalid verdict is counted separately and cannot authorize speech.

I froze the checker, instructions and scoring rule before writing eight fresh synthetic passages. Each received a faithful paraphrase and a deliberately altered answer. I froze those inputs and the separate expected verdicts before running inference once on every row. No examples, model names, case IDs, required-fact lists or expected verdicts were supplied to the verifier. These eight pairs were authored for this diagnostic. They give controlled counterexamples and do not estimate population accuracy.

## Results

| Saved answer | Expected | Frozen checker | What the model reported |
|---|---|---|---|
| Terra minutes | Reject | Accept | Passed the approval-to-outcome change. |
| Sol minutes | Accept | Accept | Passed the faithful wording. |
| Terra handover | Accept | Invalid | Passed both dimensions using title-case field names. |
| Sol handover | Reject | Invalid | Passed both dimensions using title-case field names. Its rationale recognized the label's meaning in the source while the answer omitted it. |

A case-insensitive reread of the same output would accept all four. Under the frozen rule both handovers would stay silent, including the faithful one. Formatting accounts for neither of the model's erroneous semantic judgments.

| Fresh pair | Faithful answer | Altered answer | Change in the altered answer |
|---|---|---|---|
| Lift repair | Accepted | Accepted | Approved funds became a completed repair. |
| Shuttle stop | Accepted | Accepted | Permission became an obligation. |
| Parcel slip | Accepted | Accepted | Omitted what READY means while retaining the collection restriction. |
| Visitor badge | Accepted | Accepted | Omitted the escort requirement while retaining the limit on what stripes indicate. |
| Well log | Accepted | Accepted | No recorded reading became proof that the pump did not run. |
| Loan lamp | Accepted | Rejected | Removed the final-night exception. |
| Tray count | Rejected | Accepted | Swapped the people who count and check. |
| Bottle sample | Rejected | Accepted | Extended one passing result to the whole crate. |

The model correctly accepted 6/8 faithful answers and correctly rejected 1/8 faulty answers. Only the lamp pair received both correct decisions. On the lift passage its rationale explicitly treated completed repairs as implied by funding. On the tray passage the altered answer reversed the two roles and received a better verdict than the faithful answer. Changing the output parser would leave all 16 fresh verdicts unchanged.

## Time and disposition

Across all 20 cases the local model call took 1.887 s minimum, 2.690 s median and 4.660 s maximum. Three calls exceeded 3.0 s. Timing began with the complete source and answer already available and ended when the verifier returned its response. Capture, cloud generation, synthesis and output-device onset were outside that interval. The [product limit](../plans/2026-11-20-explain-own-key-phases/phase-5.md#L11) covers key-down through the first audible word on every measured trial. These measurements alone rule out this whole-answer checker on that path for the three slow cases. A shorter response contract or a different model would require fresh evidence on both accuracy and time.

Close this verifier experiment. The existing local Read action remains the available path for hearing the source. Reconsider Explain if a materially different candidate demonstrates that it can catch both unsupported claims and omissions while preserving faithful paraphrases. These findings apply to this verifier and prompt. They do not establish limits for all on-device models.

## Reproduction record

Ran in the retained worktree at `/Users/juan/code/captalo-explain-own-key`, branch `implement/explain-own-key`, baseline `6ad8865`. Synthetic inputs, expected labels, original verdict text, per-row times and the one-shot checker remain in the ignored directory `.local/explain-qualification/meaning-coverage-apple-v1/`. From that directory, run `shasum -a 256 -c frozen-checker.sha256`, `shasum -a 256 -c frozen-cases.sha256` and `python3 score.py` to verify and score the saved run without inference. The SHA-256 of `observations.jsonl` is `86e5cd4b8cfa93149e6e0638766ad6f85bb2727ac89b1d2d096f6abf9832257f`. The checker exited after all 20 rows. No cloud requests or app installation were part of this experiment.
