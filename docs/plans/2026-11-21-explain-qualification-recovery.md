# Explain qualification recovery

**Proposed Phase 1 amendment · 2026-11-21.** Can Cáptalo give a shorter, recognizable explanation without changing what the passage says? Compare the current OpenAI instruction with an instruction built for the listener’s selected depth and style. Run the same six difficult synthetic passages through both. A candidate must pass all six before any of the 13 held-out cases can be sent.

This amends [Phase 1 of Explain with your own key](2026-11-20-explain-own-key-phases/phase-1.md). The [parent plan](2026-11-20-explain-own-key.md) still governs provider and learner eligibility, private connection, streaming, UI, device latency, signed installation and the listening trial. This plan authorizes no provider spend. Its implementation can begin offline after acceptance.

## Why this comparison

The last two pilots passed four and three of six cases under the existing scorer. In the last pilot, the legal explanation used 42 words for a 40-word passage. The cup explanation implied a cause the source left open. An earlier minutes answer passed factual review while omitting its requested metaphor. Two independent readers subsequently accepted a 35-word hall-agreement metaphor and a 30-word minutes metaphor that preserved the essential conditions. These authored examples establish feasibility on two passages. They are evaluator material and must stay out of the prompt. See the retained branch at `docs/research/2026-11-21-explain-qualification-recovery-assessment.md:9` and `docs/plans/2026-11-20-explain-own-key-notes.md:90`.

| Approach | Decision and trade-off |
| --- | --- |
| Selected depth/style and an explicit word budget | Test first. This removes competing instructions and gives Middle a count that includes the illustration. The model can still exceed it or alter a fact. |
| One unrelated worked metaphor | Test only if the first treatment preserves facts and its remaining misses concern metaphor recognition or Middle compression on metaphor rows. An example costs input tokens and can introduce unwanted factual detail. |
| Change model, buffer the whole answer, or request a rewrite | A model change would need a new comparison. Buffering delays speech and another request changes the single-call design. Return these choices to Juan if the experiment fails. |

## Sequence and spending decision

| Step | Deliverable and gate |
| --- | --- |
| [1. Freeze the request variants](2026-11-21-explain-qualification-recovery-phases/phase-1.md) | Reproduce the historical control byte for byte. Demonstrate the selected instruction across all 12 settings offline. |
| [2. Make the comparison reproducible](2026-11-21-explain-qualification-recovery-phases/phase-2.md) | Demonstrate repeat isolation, blind scoring, recovery and spend limits with synthetic responses and zero network calls. |
| [3. Run and decide](2026-11-21-explain-qualification-recovery-phases/phase-3.md) | After separate authorization, compare the paired six-case results. Only a clean treatment can earn a fresh 83-case run. Juan retains the listening verdict. |

Proposed ceiling for the existing OpenAI assessment credential and frozen synthetic adult fixtures is **101 requests and US$3.00 in model-usage reservations**. The control repeat, selected instruction and conditional example each get at most six requests and US$0.20. One conditional full run gets at most 83 requests and US$2.40. Without the example, the ceiling is 95 requests and US$2.80. The last control preview was US$0.16466750 for six requests and US$2.14052875 for 83. These historical bounds are neither current prices nor billed totals. Before authorization, show the exact previews for the frozen candidates using a verified applicable price bound. Halt if a per-run or aggregate ceiling cannot cover them. The previous 95-request authorization used both pilots and neither passed. Its unused dollars confer no authority here. See the intervention and ledger at `docs/plans/2026-11-20-explain-own-key-notes.md:92` and `:107` on the retained branch.

## Consumer sweep

Planning baseline is local `develop` at `24e13d9`. The implementation references below resolve at `ef075b2` in `/Users/juan/code/captalo-explain-own-key`. From the primary checkout, read any cited file with `git show ef075b2:<path>`. The local Graphify query at the integration root did not surface the retained feature symbols. Source searches in the feature worktree established these boundaries:

```sh
rg -n 'ExplainCandidate|ExplainInput\(|requestBody\(|targetWords' Packages Captalo
rg -n 'explain-candidate|explain-qualif|prepared.json|configuration_sha256|request_set_sha256' Scripts .rpi/policy.json
rg --files Qualification/Explain Tests/ExplainQualification
rg -n 'main-email|reservations|receipt|packet' .local/explain/authorized-95 .local/explain/review-six.py -g '*.py'
```

| Current producer, reader or fixture | Coverage |
| --- | --- |
| `Packages/CaptaloCore/Sources/CaptaloCore/Explain/ExplainInput.swift:38`, `Packages/CaptaloCore/Sources/CaptaloCore/Explain/ExplainCandidate.swift:37` and `:52` | Step 1 owns counts, config and wire serialization. No native Explain caller exists at this baseline. The future native caller uses the same selected builder. |
| `Packages/CaptaloCore/Sources/ExplainQualificationProbe/main.swift:18`, `Scripts/explain-candidate:36`, `Qualification/Explain/candidates/openai.json:1` and `Qualification/Explain/candidates/anthropic.json:1` | Step 1 covers both probe modes and the check, freeze and prepare paths. Preserve historical configuration and request hashes alongside the new format. |
| `Scripts/explain-qualification-run:33`, `:55`, `:225` and `:239` | Step 2 covers prepared-file loading, pricing, selection, attempt recording, replay protection and aggregate reservation. Step 3 uses the same dispatch path. |
| `Scripts/explain-qualification-review:25`, `:63`, `:77` and `:125`; `Scripts/explain-qualify:48`, `:83`, `:150`, `:167` and `:191` | Step 2 covers packet, verdict join, receipt writing, strict versioned scoring, archived rejections, default discovery and the explicit qualification check. Distinguish tuning receipts from full results. |
| `Tests/ExplainQualification/manifest.json:10`, `Tests/ExplainQualification/RUBRIC.md:7` | Keep the hashed cases, sources, required facts and historical rubric intact. Step 2 adds prospective review instructions and records their identity separately. Existing tuning receipts, archived configurations and rejected receipts retain their original meaning. |
| `Packages/CaptaloCore/Tests/CaptaloCoreTests/ExplainInstructionTests.swift:12`, `Scripts/tests/test_explain_candidate.py:10`, `Scripts/tests/test_explain_run.py:102`, `Scripts/tests/test_explain_review.py:41`, `Scripts/tests/test_explain_qualification.py:28` | Extend the real builder, freeze, sender-boundary, evidence-join and scoring fixtures in the step that changes each contract. Preserve tests for both receipt generations. |
| `.local/explain/authorized-95/dispatch.py:7`, `.local/explain/authorized-95/score.py:9`, `.local/explain/authorized-95/archive.py:1`, `.local/explain/review-six.py:7` | These ignored one-off writers explain the previous receipts. Preserve them as historical evidence. The new experiment must run from versioned tooling on a clean checkout. |
| `Makefile:132`, `.rpi/policy.json:36` | The integration owner runs the full sequential local gate after each implementation step and includes new deterministic checks in that policy. Metered generation and listening have separate evidence. |

## Stuck states and recovery

| State | What the operator or listener sees and how to proceed | Required test |
| --- | --- | --- |
| Middle has one source word | The treatment builder returns a specific local reason. The probe identifies the case and suggests a longer passage or another depth. Parent Phase 3 presents the same recovery to the listener. | Reject one-word Middle before send, then accept a two-word Middle or one-word Simple input. |
| Missing or stale control, changed request, unexpected model, fixture, or reviewer guide | The CLI identifies the mismatched artifact. Restore the frozen revision or prepare a new candidate and preview it. | Corrupt each binding independently, verify zero dispatch or withheld receipt as appropriate, restore and verify again. |
| Missing approval, wrong cohort, duplicate run, price unknown or budget exceeded | The CLI reports the exact failed check and the authorized scope or missing price. Use an eligible preview or request a new decision. | Deny each case before send. Verify valid scope can run once and two concurrent starts cannot claim the same allowance. |
| Interruption, transport error or incomplete ledger | The operator sees the affected run and last reserved case. Preserve evidence, report the reservation and stop. A fresh identity requires a fresh decision. | Kill after reservation, simulate a failed stream, then reopen. Both remain incomplete, replay stays blocked and the next operator sees why. |
| Missing, conflicting, unbound or unsuccessful review | Show the missing label or failed criterion. Recover a missing review from the same blinded packet or adjudicate the exact source. A genuine miss follows the Step 3 decision table. | Swap two runs, remove a label, dispute a causal claim and omit a metaphor. Verify repair of a clerical error and retention of a genuine miss. |
| Pilot, full qualification, listening or eligibility fails | Juan sees the affected case, cohort or route and its evidence. Return to the parent Phase 1 decision. Local Read remains available. | Exercise each decision branch offline, including a perfect pilot followed by a failed held-out case. Record listening and eligibility before provisional route acceptance. |

## Handoff

Planning used the integration branch and the retained assessment at `ef075b2`. At that revision OpenAI configuration `193ac7aad8e461cf5c130cb404bac2a5b905ed39f302e9bd7676454ada721d9a` is the control. The full 17-check offline suite last passed at `fba38ae`. Later scoped checks and the historical paid evidence cover their own revisions only. The worktree owner retains raw synthetic answers, the calibration packet and listening material until they can be preserved through cleanup. This planning pass allocated no service. The optional project planning overlay is absent. On resumption, inspect both Git refs, the retained worktree status, hashes and current approval. The next gate is offline implementation of Step 1. Merge, pruning, installation and the week-long trial remain behind the parent plan’s gates.
