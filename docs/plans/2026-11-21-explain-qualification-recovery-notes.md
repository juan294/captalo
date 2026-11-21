# Explain qualification recovery implementation

## Step 1 — Request variants

The integration owner merged the accepted local plan at f74063d into the retained implementation worktree at 1b9bed8. No project implementation overlay was present. The product builder, probe, freeze/check/prepare command and regression tests now reproduce all 83 adult requests for each variant. The OpenAI control (193ac7aa) and Anthropic (7fd44755) match their historical bytes. Selected (f36de885) and example (462eda34) differ only on Metaphors rows. Full identities are the SHA-256 of each checked-in candidate file.

The independent fixture reader rejected an eight-word source paired with a longer example. The replacement describes a shuttle and bobbin and shortens its 20-word source to 13 words. The reader checked topic, distinctive wording and fact overlap against the corpus, held-out material, calibration and prior answers. A second reviewer checked actual legal Middle Metaphors and long Simple Plain wire requests and all four ordered request sets. The review identified three missing regression assertions. The repaired suite checks exclusive clauses for each of 12 settings, corruption of pilot and nonpilot wire bytes, and one-word recovery through the probe. The independent follow-up approved the repairs.

Red evidence for the missing variant API and missing candidate snapshots is retained under the worktree's ignored .local/recovery-* logs. The first green attempt exposed an escaped interpolation in the test expectation. Correcting it produced four passing Swift tests. The simplify pass reused the existing serializer and word counts, checked naming and removed duplicate freeze-test invocations. Verification covers synthetic requests and local code only. Juan retains the listening verdict. The integration owner retains the worktree and its earlier raw evidence through qualification.

## Deviations

The canonical OpenAI snapshot continues to represent the historical control. Candidate preparation emits two additional named snapshots. This lets existing tools and archived evidence continue to resolve the old identity while the comparison is pending.

## Step 2 — Offline comparison

Step 1 passed the complete 17-check sequential gate at cd9510b, including the debug and release builds, native OCR and all 79 script tests. The integration owner retained a copy of the receipt under .local/recovery-rehearsal/. The Step 2 transport, review and end-to-end rehearsal have disjoint test ownership. Rehearsal cases use generated responses and simulated votes in a disposable local directory. They test gate behavior. Only the future metered run can supply candidate quality evidence.

Price basis checked on 2026-11-21 for the global standard OpenAI Responses endpoint, gpt-6.1-terra, default 30-minute cache retention. The conservative reservation prices each UTF-8 wire byte plus 1,024 framing tokens at US$1.25 per million, and reserves all 4,096 possible output tokens at US$5 per million. This exceeds the ordinary input rate and covers the default write rate. The request bounds fall below the long-context threshold. Recheck prices before a later paid run. [Model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-terra) · [Default cache retention](https://developers.openai.com/api/docs/guides/prompt-caching)

Two independent readers rehearsed the factual and perceived-style judgments on nine archived calibration items with the expected styles removed. Both detected the unsupported causal link in the cup answer and recognized the literal minutes answer as Plain. They also both flagged the long register answer that implied an unsupported exclusion. They differed on two short minutes answers. A third blinded reader cited the source and assessed one as faithful and the “untouched garden marker” as uncertain. Both omit the discussion of painting both doors blue. These new rehearsal votes illustrate what requires adjudication. They do not replace the historical receipts or qualify a treatment.

The paired rehearsal uses the actual CLI for preparing requests, exporting opaque packets, joining votes and verifying a full portable receipt from a checkout with its private evidence removed. The injected sender and fabricated review decisions exercise three paths: a factual pilot miss stops after 12 simulated requests, a clean treatment can fail held-out qualification after 95, and an eligible example can finish the 101-request path. These totals are simulated. The real ledger is empty.

Independent review caught a predecessor check that initially allowed an incomplete control identity, an arm name in a reviewer-facing directory, a missing answer-to-vote binding in portable admission, and an untested full-run price ceiling. The repairs verify the complete predecessor and its reservation before spending, return only an opaque reviewer directory, bind each judgment to the exact run, case, wire and answer, and exercise both caps separately. A clean-checkout rehearsal also exposed a missing provider name in the qualification result. The scorer now reports the full candidate digest. The simplify pass reused frozen request checking and the completed-attempt verifier, preserved version 1 scoring for old evidence, and kept fixture preparation outside each individual rehearsal scenario.

To reproduce locally, run `Scripts/explain-candidate prepare`, `python3 Scripts/tests/rehearse_explain_recovery.py`, `Scripts/explain-qualification-run openai --recovery-preview`, and `Scripts/explain-qualification-run openai --recovery-status`. The proposal includes the exact case list, run identities and pricing. For metered use the integration owner needs a fresh explicit approval of the preview. Keep the approved envelope in ignored evidence. The dispatcher accepts only a matching envelope and eligible arm. After generation the operator uses `Scripts/explain-qualification-review recovery-packet pair` to hand the neutral packet to two independent readers. The review CLI lists the receipt options, and a disagreement identifies the labels requiring a third vote. A missing review can be completed offline without sending the underlying text again.

| Prospective arm | Requests | Maximum model-usage reservation (USD) |
| --- | ---: | ---: |
| Control repeat | 6 | 0.16466750 |
| Selected instruction | 6 | 0.15992750 |
| Optional example | 6 | 0.16108250 |
| Full selected instruction | 83 | 2.07385875 |
| Full example | 83 | 2.08425375 |

Only one full run can occur. The largest eligible path reserves US$2.56993125 under the proposed ceiling of US$3.00. A clean selected pilot skips the example and reserves up to US$2.39845375 across 95 requests. Raw rehearsal evidence and the previous paid evidence remain in the retained implementation worktree. No application or paid qualification result is implied by this handoff.

## Step 3 — Paid comparison and disposition

Juan approved the frozen conditional comparison after the 18-check offline gate at 204b60f. The integration owner rechecked the exact candidate preparations, price basis, empty ledger and approved manifest digest 2499807dfa45fee0e04ff9d54c66af5e1d241022a07e39fa1548617069a84e8c. The existing OpenAI assessment credential sent six synthetic requests for the control and six for the selected instruction. All 12 terminated naturally on the frozen model. Reservations were US$0.16466750 and US$0.15992750, totaling US$0.32459500. Actual invoiced spend was unmeasured.

The repeated control passed 2/6 across all criteria. The selected instruction passed 4/6. Reviewers recognized all 12 requested styles. All four selected Middle answers were shorter than their respective sources. The full dispositions below include word counts for the three observations. Historical style was unmeasured. The historical column gives the original factual verdict and any separate recorded failure.

| Case (source words) | Historical control | Fresh control | Selected instruction |
| --- | --- | --- | --- |
| Email (33) | 32, pass | 32, pass | 25, missing Tuesday exclusivity and the count of Mira’s updates |
| Legal agreement (40) | 42, factual pass, exceeded length | 44, factual pass, exceeded length | 35, pass |
| Textbook (46) | 28, unsupported cause | 28, unsupported cause and missing class action | 25, pass |
| Minutes (31) | 26, uncertain metaphor | 27, uncertain metaphor | 29, asserted the door gets painted when the committee only approved paint |
| Handover (32) | 22, pass | 20, inferred no review had happened and lost the limit on what the label establishes | 22, pass |
| Room register (3,000) | 215, pass | 223, pass | 250, pass |

Two independent blinded readers reviewed the mixed packet. A third independently adjudicated the email. The final email judgment allows the literal wording as supported and marks two required facts omitted. Both original readers rejected the minutes’ shift from approval to an outcome. The handover case illustrates variation under identical control bytes. The three successful repairs on the selected arm (legal, textbook and handover) came alongside the email regression. Neither arm met the six-case entry condition. The selected misses concern fidelity and essential coverage, so the example variant and full 83-case run are ineligible. No held-out or learner case was sent. No model choice, product integration, signed install or trial follows from this result.

Sanitized receipts are in `Qualification/Explain/recovery/control.json` and `Qualification/Explain/recovery/selected.json`. Use `Scripts/explain-qualify` to reproduce the paired results offline. The private run, attempts, answers, votes and bindings remain under the worktree’s ignored experiment evidence. The integration owner retains the worktree at /Users/juan/code/captalo-explain-own-key through the next provider decision. The implementation overlay is absent. The next decision belongs to Juan under the parent Phase 1 failure disposition.
