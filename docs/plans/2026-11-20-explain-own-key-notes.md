# Explain own-key implementation handoff

On 2026-11-20 Juan authorized all five phases of 2026-11-20-explain-own-key.md, followed by local integration, worktree cleanup and signed installation. The implementation branch is `implement/explain-own-key` at `/Users/juan/code/captalo-explain-own-key`, based on local develop `24e13d91b47de383e4918b2092bce9d3d6b35b06`. The optional project overlay at `.rpi/project/rpi-implement.md` is absent. Stock rpi-implement applies.

## Phase 1 evidence

| Candidate or gate | Disposition |
| --- | --- |
| Original corpus | Verified original IDs, settings, UTF-8 source bytes, historical fact lists and rubric for all 70 cases. The manifest identifies the original files and the promoted inputs. |
| Held-out coverage | 13 adult cases cover matched report number, actor and exception changes, three depths, four styles, ordinary and professional backgrounds, an embedded source instruction and a conflicting profile. Two learner fixtures exercise exclusion from the metered request set. |
| Frozen request sets | The Swift serializer emits 83 eligible synthetic requests for each configuration. The fixture manifest SHA-256 is `4376d4b02fb5e80627fcf7342e5b9c0658c1c4d0ee8237cb9f52163bf6e480d3`. See the versioned candidate JSON for the instruction, its digest, the whole request-set digest, model and options. |
| OpenAI adult | Candidate SHA-256 `f02279dfbe1ff11187dfdfac9280ab099a6ca64311aa30d95e7e29568ac7debd`. The offline price bound is US$2.13602875 for 83 requests. Rejected after the authorized metered run and blind semantic review below. |
| Anthropic adult | Candidate SHA-256 `cff7b97459a15469e24a76e9ba0e8654b672dbbf8e9288c941a070b2dca0b12a`. US$4.117668 for 83 requests under standard pricing. Separate spend authority and qualification are pending. |
| Learner routes | Both unavailable. Current primary-source evidence and the conditions for reconsideration are in 2026-11-20-explain-route-eligibility.md. |
| Product | Phase 1 is open. The preparatory code registers no action and enables no provider. A qualified OpenAI configuration and the owner's blind listening verdict are prerequisites to Phase 2. The week-long trial belongs to Phase 5 on the signed candidate. |

## Reproducing the evidence

Run `Scripts/explain-candidate check` to compare fresh requests from the Swift builder with both frozen candidate snapshots. Run `Scripts/explain-candidate prepare` to write the ignored synthetic request sets, then `Scripts/explain-qualification-run openai` to print the offline bound. The default check `Scripts/explain-qualify` distinguishes intact fixtures from a recorded quality pass. `--require openai` also requires that candidate's passing receipt. Ordinary verification runs offline.

Before executing a metered run, record the owner's authorized provider, cases, existing credential scope, request limit and USD ceiling. The research runner accepts these bounds only on explicit execution. No assessment key is an application setup path. A started attempt records request reservations before dispatch. If interrupted, keep the entire incomplete directory and account for its possible spend before authorizing another attempt. Keep raw synthetic answers under the ignored digest directory.

After a complete run, `Scripts/explain-qualification-review packet --provider openai --review .local/blind-a` prepares the anonymous packet and rubric. Give reviewers only the reviewer directory. The receipt subcommand binds verdicts to the reviewed source and answer, preserves minor omissions and checks every required fact. Put complete negative outcomes under `Qualification/Explain/rejected/`; passing quality receipts belong in `Qualification/Explain/receipts/`, named by configuration digest. Use the same held-out ticket report for the anonymous local Kokoro depth/style listening round, including both profile examples. The historical listening pack used a different prompt.

## Deviations

- The plan left the smaller product output bound to qualification. Selected 4,096 output tokens for the 3,000-word maximum and pinned standard OpenAI service tier for comparable cost and latency. A non-natural termination fails the candidate. The measured corpus and human gates still determine admission.
- Review found that the first scorer rejected every omission. The frozen required-fact sheet distinguishes essential facts from incidental detail. Both are accounted for in each receipt. A changed observed model or fixture digest now invalidates the receipt. Complete negative reviews have a durable sanitized export independent of admission. The actual paid entrypoint rebuilds and checks the candidate before allocating evidence or reading a credential.
- The frozen model, account research and documentation do not determine whether any given key has access. The offline suite measures request and receipt integrity. The metered run below supplies separate quality evidence.

The integration owner retains this worktree and its task-local synthetic requests, model/vendor copies and build products while Phase 1 is open. The primary checkout owns the original assessment resources. Revisit the task copies at the requested post-integration cleanup. Neither fixture work nor ordinary verification needs a database or persistent task service.

## First OpenAI product run, 2026-11-20

Juan approved 83 synthetic requests with the existing OpenAI assessment credential and a US$2.14 model-usage ceiling. The standard-tier runner reserved US$2.13602875 at most, issued exactly 83 requests and observed 83 natural completions on `gpt-6.1-terra`. This figure bounds model charges. The runner did not collect an invoice or token-usage total. No other provider was called.

| Cohort | Blind factual pass / fail / uncertain | Answers missing required facts | Middle shortening misses | Passed all per-answer checks |
| --- | --- | --- | --- | --- |
| Original 70 | 48 / 21 / 1 | 18 | 3 of 26 | 37 |
| Held-out 13 | 8 / 5 / 0 | 11 | 0 of 11 | 2 |

The causes overlap. Some answers gave a reason the source did not establish or changed a limit on what was known into a claim that an event had never happened. Three Middle metaphors used 38, 46 and 35 words for sources of 33, 40 and 31 words respectively. All six 3,000-word cases finished and retained the three distant exceptions; four still failed factual review on other claims. Three independent blind readers reviewed 14, 34 and 35 answers against the original rubric. The portable rejection receipt reconciled all 83 labels, hashes and fact sheets. Candidate `f02279dfbe1ff11187dfdfac9280ab099a6ca64311aa30d95e7e29568ac7debd` is ineligible. The phase gate requires 70/70 factual passes.

The tested source commit is `cd72660f238cf0c60af3fc367ec4f453756264d2`. Its complete offline suite passed 17 checks. To reproduce the negative score, run `Scripts/explain-qualify --record-outcome --config Qualification/Explain/candidates/openai.json --receipt Qualification/Explain/rejected/f02279dfbe1ff11187dfdfac9280ab099a6ca64311aa30d95e7e29568ac7debd.json` with this candidate's config. Raw run records are in the worktree's ignored `.local/explain-qualification/openai/` under the candidate digest. Review packets are in `.local/blind-a/`. The integration owner rendered seven anonymous synthetic WAVs (335 seconds total) with local Kokoro. The player is `.local/explain-listening/player/index.html`; its key is outside the player. The renderer exited. Retain the synthetic recordings and task-owned voice store through owner review and preserve them before worktree cleanup. A listening verdict is outstanding and cannot admit this rejected candidate.
