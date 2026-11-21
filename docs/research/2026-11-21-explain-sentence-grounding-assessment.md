# Can a source quote make streamed Explain reliable enough to speak?

**Decision, 2026-11-21.** Keep Explain on hold. An exact-source check accepted all ten sentences from four saved answers, including both answers that failed blind review. The results rule out using quote membership alone to decide that a sentence is safe to speak. Whether asking a model to select evidence improves its writing is a separate, untested hypothesis.

The proposed change uses one streamed request. Each record carries a source quotation and a speakable sentence. The app checks the complete record locally before speaking. The decision turns on three requirements: preserve what the source says, convey essential facts at the requested depth and style, and start the first audible word within three seconds on every measured trial. Both six-case pilots passed four cases. Their opposite verdicts on the minutes and handover supply a failed and a faithful answer for each source. [Pilot verdicts and scoring](../plans/2026-11-21-explain-qualification-recovery-notes.md#L43)

## What the local check caught

I kept the saved speech unchanged and supplied a contiguous source quotation for each sentence. The replay decoded each complete JSON record, required nonempty quote and speech fields, and looked for the decoded quote's exact UTF-8 bytes in the captured source. In the table, numbers identify source sentences in document order. A range denotes one verbatim span including the intervening spaces. The pilot models originally produced plain text. The quotes were assigned during this assessment. [Minutes and handover fixtures](../../Tests/ExplainQualification/sources.json#L6)

| Pilot answer | Source sentences paired with successive spoken sentences | Accepted records | Original review |
|---|---|---:|---|
| Terra, minutes | 2–3 / 2 / 4 | 3 of 3 | “Only the east door gets blue paint” turns approval into an outcome. |
| Sol, minutes | 1–2 / 3 / 4 | 3 of 3 | Preserves approval and which door it covers. |
| Terra, handover | 4 / 1–3 | 2 of 2 | Explains that FIRST REVIEW names the next stage. |
| Sol, handover | 4 / 1–3 | 2 of 2 | Omits what the label means. Its quote explicitly includes “The label describes the next stage.” |

The check rejected empty and invented quotes. Removing the closing brace also prevented all ten records from being decoded. It accepted a real handover quote paired with the unrelated claim “Both doors will be painted.” It also accepted the fragment “a review has happened.” from “It does not mean a review has happened.” paired with the opposite claim. Requiring a full source sentence closes that particular fragment loophole. Both actual failed answers already had whole-sentence quotations.

Quote membership establishes that the cited words occur in the capture. The minutes example also requires a judgment about what follows from those words. The handover example requires checking what the *listener hears* across the answer. A fixture can list essential facts in advance. An arbitrary selection arrives without that list. The existing runner checks that streamed text matches the completed reply, and preserved responses can be scored against the fixture facts. Neither operation supplies that missing judgment at playback time. [Stream checks](../../Scripts/explain-qualification-run#L123) · [Required fixture facts](../../Tests/ExplainQualification/required-facts.json#L26)

## Time to the first audible word

A complete first record took 162 bytes for Terra's minutes and 194 for Sol's, versus 65 and 82 bytes of speech alone. The two handover records each took 130 bytes for 54 bytes of speech. These are compact UTF-8 encodings with the quote first. They show how much more text the client must receive for these examples. Converting bytes to milliseconds would require actual stream measurements.

| Historical request to first complete plain-text sentence, 64 requests per model on inputs up to 300 words | Terra | Sol |
|---|---:|---:|
| Median | 1.457 s | 1.285 s |
| 95th percentile, nearest rank | 2.408 s | 1.873 s |
| Maximum | 3.810 s | 2.459 s |
| Cases over 3.0 s after adding the warm speech estimate | 3 | 1 |

The estimate adds 0.220 s to schedule speech and 0.325 s to reach detectable audio energy, medians from a different set of sentences. It allows capture and device latency to be zero and the chime to overlap generation. Terra delivered its first text delta after three seconds twice. Sol's slowest sentence finished 0.859 s after its first delta. The saved data do not say when a usable pair would have arrived. The six-case qualification runs have no per-record timestamps. [Cloud benchmark](2026-11-20-explain-cloud-engine-assessment.md#L82) · [Warm speech measurements](2026-11-20-explain-my-way-engine-assessment.md#L101) · [Qualification records](../../Scripts/explain-qualification-run#L291)

The signed-app criterion includes key-down, selection capture or a controlled region drag, the chime, synthesis and output-device onset for cold and warm trials at 30, 200 and 300 words. A future check would have to timestamp the first complete validated record and identify the first spoken word in the device recording. The estimate above cannot establish that either model meets the limit. [Signed-app timing criterion](../plans/2026-11-20-explain-own-key-phases/phase-5.md#L11)

## Options and disposition

- **Continue free paraphrase.** It preserves the intended range of depth and style. Both pilots missed the qualification threshold. Changing only the timing of playback leaves both observed quality failures possible.
- **Ask for a quote with each paraphrase.** This can point a reviewer to relevant text and might change what the model generates. It adds output and parsing work within the existing request. A client would have to handle split or truncated records, speak only the validated speech field, and discard late records after cancellation. Once a sentence is audible, a later check cannot retract it. The replay gives no basis for paying for another pilot or planning this as a fidelity fix.
- **Select complete source sentences and speak them verbatim.** The model could send sentence identifiers and the app could resolve them locally. That limits invented wording and keeps the first record small. A selection can still omit an essential condition or its antecedent. This would give the listener selected passages and would change the promised explanation and metaphor styles. Local Read already serves listeners who want the source wording.
- **Check meaning and coverage.** A candidate verifier would have to distinguish approval from outcome and detect missing required meaning across sentences. Buffering the whole answer would permit that second check, while delaying first speech. This assessment identified no demonstrated local verifier that satisfies both requirements.

**What would change the decision.** Reopen planning if an offline candidate can reject both failed answers, accept both faithful counterparts and repeat the result on unseen synthetic variants without access to fixture-specific answer keys at runtime. Then measure the exact streaming candidate against the signed-app timing criterion. A different product decision would be to assess whether listeners want selected passages. That decision belongs to Juan.

**Handoff.** Assessed offline on 2026-11-21 against retained branch `implement/explain-own-key` at `8a42d46` in `/Users/juan/code/captalo-explain-own-key`. Integration baseline was `develop` at `f74063d`. To repeat the four-answer replay, take rows 4 and 5 from each feature-worktree file `.local/explain-qualification/recovery-v1/selected/answers.jsonl` and `.local/explain-qualification/sol-selected-six-v1/run/answers.jsonl`, and apply the spans above. An independent read-only check recomputed timing from the primary checkout's `.local/assess-explain/cloud/results-openai-{terra,mid}.jsonl`, joining case IDs to input lengths in `.local/assess-explain/run/cases.json`. The assessment used existing synthetic records and made zero provider calls. No project assessment overlay was present. The Explain qualification hold remains in effect.
