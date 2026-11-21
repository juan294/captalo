# Explain own-key implementation handoff

On 2026-11-20 Juan authorized all five phases of 2026-11-20-explain-own-key.md, followed by local integration, worktree cleanup and signed installation. The implementation branch is `implement/explain-own-key` at `/Users/juan/code/captalo-explain-own-key`, based on local develop `24e13d91b47de383e4918b2092bce9d3d6b35b06`. The optional project overlay at `.rpi/project/rpi-implement.md` is absent. Stock rpi-implement applies.

## Phase 1 evidence

| Candidate or gate | Disposition |
| --- | --- |
| Original corpus | Verified original IDs, settings, UTF-8 source bytes, historical fact lists and rubric for all 70 cases. The manifest identifies the original files and the promoted inputs. |
| Held-out coverage | 13 adult cases cover matched report number, actor and exception changes, three depths, four styles, ordinary and professional backgrounds, an embedded source instruction and a conflicting profile. Two learner fixtures exercise exclusion from the metered request set. |
| First frozen request sets | The Swift serializer emits 83 eligible synthetic requests for each configuration. The fixture manifest SHA-256 is `4376d4b02fb5e80627fcf7342e5b9c0658c1c4d0ee8237cb9f52163bf6e480d3`. See the versioned candidate JSON for the instruction, its digest, the whole request-set digest, model and options. |
| First OpenAI adult candidate | Candidate SHA-256 `f02279dfbe1ff11187dfdfac9280ab099a6ca64311aa30d95e7e29568ac7debd`. The offline price bound is US$2.13602875 for 83 requests. Rejected after the authorized metered run and blind semantic review below. |
| First Anthropic adult candidate | Candidate SHA-256 `cff7b97459a15469e24a76e9ba0e8654b672dbbf8e9288c941a070b2dca0b12a`. US$4.117668 for 83 requests under standard pricing. Separate spend authority and qualification are pending. |
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

The tested source commit is `cd72660f238cf0c60af3fc367ec4f453756264d2`. Its complete offline suite passed 17 checks. To reproduce the negative score, run `Scripts/explain-qualify --record-outcome --config Qualification/Explain/candidates/openai.json --receipt Qualification/Explain/rejected/f02279dfbe1ff11187dfdfac9280ab099a6ca64311aa30d95e7e29568ac7debd.json` at rejection commit `36c97d9`, or supply the archived config with the same digest on the tuning branch. Raw run records are in the worktree's ignored `.local/explain-qualification/openai/` under the candidate digest. Review packets are in `.local/blind-a/`. The integration owner rendered seven anonymous synthetic WAVs (335 seconds total) with local Kokoro. The player is `.local/explain-listening/player/index.html`; its key is outside the player. The renderer exited. Retain the synthetic recordings and task-owned voice store through owner review and preserve them before worktree cleanup. A listening verdict is outstanding and cannot admit this rejected candidate.

## Offline tuning candidate

The first run failed the zero-error requirement. Product integration stays on hold. The new OpenAI instruction explicitly preserves the distinction between an observation, permission, reported evidence and absence of knowledge. It asks the model to keep unconnected statements separate and fit a requested comparison inside the summary budget. Both candidate request builders now supply the exact original word count alongside the existing target. This changes both request-set hashes. Anthropic has received no requests.

OpenAI tuning configuration `489244ae1ff19c6e0001bbc47da09fddd8ab6d4ffb9375487016d0e83ace2128` has a six-case preview bound of US$0.170285. The selection contains the three Middle metaphor length misses (email, legal and minutes), Simple Plain textbook, Middle Metaphors handover, and Simple Plain document3000. These six original-corpus cases exercise compression, unsupported causal links, knowledge claims and long-document fidelity. The held-out cohort is excluded from tuning. The revised full 83-case bound is US$2.21823750. Neither a tuning attempt nor a clean qualification run follows from the first run's exhausted 83-request authority.

For the six-case preview use the arguments below. By default the command reads the frozen synthetic requests locally. The case selector limits a tuning run to original-corpus IDs and stores any paid evidence under a separate digest. A tuning run cannot produce the 83-case qualification receipt.

```sh
Scripts/explain-qualification-run openai \
  --case main-email-middle-metaphors --case main-legal-middle-metaphors \
  --case main-minutes-middle-metaphors --case main-textbook-simple-plain \
  --case main-handover-middle-metaphors --case main-document3000-simple-plain
```

The historical OpenAI instruction and request-set hash are preserved under `Qualification/Explain/rejected/configurations/` with the first configuration digest as the filename. That archive and its sanitized case receipt refer only to the rejected instruction. Local development remains on the implementation worktree. A new passing 83-case quality receipt and the owner's listening result are required to start Phase 2.

Independent review reproduced the 83 digest bindings, all verdict joins, the cohort counts and the six-case ceiling. Review found that a held-out ID could enter a tuning request. A red regression exposed that path. The corrected check rejects held-out IDs before allocating run evidence or dispatching, while keeping them in full qualification. Simplification reused the original input count in serialization, the same selector in offline previews and paid dispatch, and the existing receipt scorer for current-fixture historical records.

## Six-case OpenAI tuning result, 2026-11-21

Juan authorized six OpenAI tuning requests with the existing assessment credential and a fresh US$0.18 ceiling. The runner sent the six named original cases exactly once at source commit `fba38aee0539a538055e9171c4fa058761675fad`. All six completed naturally. The model-usage reservation was US$0.170285; actual billed spend was not measured. Verified the authorization, wire bytes, answer hashes, observed model, attempt count and complete ledger. One independent reviewer judged the blinded answers against their source and rubric. The evidence under `Qualification/Explain/tuning/` binds the six judgments to configuration `489244ae1ff19c6e0001bbc47da09fddd8ab6d4ffb9375487016d0e83ace2128` and subset `1b366b2821e591542701a1eb4676f5889809453e2133241235d787fdf2439ea0`. Raw synthetic answers and the blind key stay in the ignored worktree evidence through tuning review.

| Tuning case | Source words | First answer | Revised answer | Revised judgment |
| --- | ---: | ---: | ---: | --- |
| Email, Middle Metaphors | 33 | 38 | 27 | Faithful statements; lost Tuesday's **only** and the promise of **one** update. |
| Hall agreement, Middle Metaphors | 40 | 46 | 40 | Failed fidelity, completeness and length. “Before booking” shifts the deadline from the booked occasion to making a reservation. |
| Minutes, Middle Metaphors | 31 | 35 | 28 | Passed. Omission of the preliminary discussion is incidental under the frozen oracle. |
| Cups, Simple Plain | 46 | 32 | 24 | Faithful statements; lost the equal starting amounts of water. |
| Archive handover, Middle Metaphors | 32 | 30 | 28 | Passed. The revised answer preserves what the label establishes. |
| Long room register, Simple Plain | 3,000 | 184 | 183 | Passed. All required facts and all three distant exceptions were covered. |

Five answers passed blind factual review and three passed all applicable checks. All four Middle answers got shorter than the first run; three were strictly shorter than their sources. The three previous length misses became two passes and one tie on length. This six-case diagnostic has no held-out, listening or product admission result. Both paid authorizations are exhausted. Integration and installation await an accepted Phase 1.

## Next offline instruction candidate

OpenAI candidate `ae05abebd7d2604697586c36d1e78a8ed6d2f313aac36bf79a7b75dee7259f3b` directs the model to keep the source wording where a synonym would change a fact, deadline, condition or type of evidence. It asks for compression through removal of repetition and filler, and includes the comparison in the Middle word budget. Independent review restored the explicit short-sentence requirement at Simple depth. The instruction contains no case-specific answers. The same six original-corpus cases have a preview bound of US$0.16571. A clean 83-case run at these settings has a preview bound of US$2.15495. A fresh metered authorization is required. The Anthropic snapshot is byte-identical to the preceding offline revision.

For any future multi-run authorization, reserve each run's entire preview before dispatch, deduct prior reservations from the approved total and enforce both request and dollar ceilings on the next invocation. An interrupted attempt keeps its reservation. Admit a full run only after a clean tuning round. Product acceptance still requires a clean full run and the owner's listening verdict. The six-case evidence remains reproducible against its source commit and stored receipt after the tuning candidate changes.

## Bounded OpenAI tuning and conditional qualification, 2026-11-21

Juan authorized at most two six-case tuning rounds and one clean 83-case qualification run conditional on all six tuning cases passing, within a total of 95 requests and US$2.50. The assessment credential and original six synthetic tuning cases are the only pilot inputs. Each invocation checks the aggregate local reservation ledger before dispatch and runs with its own exact request and model-usage bound.

Round one used implementation commit `264de88` and configuration `ae05abebd7d2604697586c36d1e78a8ed6d2f313aac36bf79a7b75dee7259f3b`. Six attempts completed naturally with a total reservation of US$0.16571. Blind review marked five factually faithful; all six retained the required facts. Four passed every scoring check. The minutes summary tied the source at 31 words. The long answer described the other rooms' recordkeeping using a phrase that implied the specially described rooms did not follow that practice. The source does not establish where those rooms keep their sheets. The email and minutes answers also lacked a recognizable requested comparison. The lack of a comparison is a style observation separate from the blind factual score. The scorer and evidence join verified the six recorded source, wire and answer identities. The sanitized tuning receipt is stored under its configuration digest.

Round two's OpenAI instruction groups repeated facts without extending them to unspecified items. In Middle, it asks for the outcome first and includes the chosen illustration inside the word budget. All depth and style requirements remain present; the model, decoding options, output ceiling, fixtures, scorer and Anthropic candidate are unchanged. An intermediate offline draft would have left too little budget for a clean full run; redundant instruction wording was removed before freezing configuration `193ac7aad8e461cf5c130cb404bac2a5b905ed39f302e9bd7676454ada721d9a`. Its six-case reservation is US$0.16466750 and its conditional full-run bound is US$2.14052875. The combined worst-case reservation for all 95 requests is US$2.47090625. The dispatch and score helpers reject optimized Python so their authorization and evidence assertions remain active.
