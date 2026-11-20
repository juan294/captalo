# Which cloud model can Cáptalo trust to explain a passage aloud with the user's own key?

Assessed on 2026-11-20 against local `develop` at `b8512a6` in `/Users/juan/code/captalo`. The controlling input is [the opt-in brief](2026-11-20-explain-cloud-opt-in-brief.md), untracked at assessment time. The baseline is [the local-engine assessment](2026-11-20-explain-my-way-engine-assessment.md). The optional overlay `.rpi/project/rpi-assess.md` was absent, so the stock assessment and durable-handoff rules applied. The owner authorized the key creation and the provider spend on 2026-11-20, and authorized this assessment in the same conversation as the brainstorm.

**Faithfulness is no longer the blocker.** On the same frozen 70-case corpus, four cloud configurations kept the facts in 64 to 70 of 70 explanations, where the two local engines kept them in 25 and 9 under the same reviewers. OpenAI `gpt-6.1-terra` passed 70 of 70. The open question has moved: the models that pass most often do so by staying close to the source wording, and the models that explain most freely add small inferences that the strict rubric fails. Which behaviour helps the listener is a listening decision for the owner, not a number this assessment can supply.

## Decision and criteria

The decision is which provider and model, if any, can carry the two Explain shortcuts into planning under the own-key design. The brief sets the criteria: no invented fact and no listener profile overriding the source, audible differences between settings, a first spoken word within 3 seconds for up to 300 words, a complete explanation of 3,000 words, traffic only to the connected provider, and terms that permit a distributed app in which each user supplies a key. Cost per request matters to the user who pays for the key. [Opt-in brief, Success Criteria](2026-11-20-explain-cloud-opt-in-brief.md)

## Method

The corpus, instruction and inputs are byte-identical to the local run: `run/cases.json` SHA-256 `38ce8562…9512a` and `run/texts.json` SHA-256 `f5a42e82…5f02`, both rechecked before the run. Each case was one fresh streamed request with the instruction as the system text and the JSON-encoded depth, style, listener line and source as the user text. No sampling parameter was sent, because the current models of all three providers reject or ignore `temperature`. Reasoning was set to the lowest value each model accepts, since the feature is latency-bound:

| Label | Model | Reasoning setting sent |
|---|---|---|
| Anthropic mid | `claude-sonnet-5-5` | `thinking: between_tools`, effort `low` |
| Anthropic fast | `claude-haiku-5-5` | `thinking: disabled`, effort `low` |
| OpenAI mid | `gpt-6.2-sol` | `reasoning.effort: low` (rejects `none`) |
| OpenAI middle option | `gpt-6.1-terra` | `reasoning.effort: none` |
| OpenAI fast | `gpt-6-luna` | `reasoning.effort: none` |
| Gemini mid | `gemini-4-hydrogen` | `thinkingLevel: low` (has no lower level) |
| Gemini fast | `gemini-3.5-flash-lite` | `thinkingLevel: minimal` |

Tier assignments come from each provider's model pages as retrieved on 2026-11-20. The Gemini assignment is an inference from the descriptions and prices, because Google's pages do not name tiers. All 490 requests returned HTTP 200 with a natural finish reason on the first attempt. The probe uses the Python standard library only, with raw HTTPS, because no provider SDK is installed and an assessment installs nothing.

**Scoring.** Five reviewers each scored every engine on the same group of texts, so one reviewer's strictness applies equally to all engines on a text. Each engine carried a random code and the reviewers did not see the key. The two local engines' outputs from the earlier run were included under their own codes, which rescales the local results to the same reviewers. The rubric restates the earlier one and its failed examples: `pass` means every statement presented as fact is supported by the source, `uncertain` is reserved for a signalled comparison that a listener could take as fact, and omissions and near-verbatim repetition are recorded as separate flags. The rubric is `.local/assess-explain/cloud/review/RUBRIC.md`. This is one run per case, scored once by model reviewers. The counts describe these outputs and are not population rates.

## Faithfulness results

| Engine | Pass | Fail | Uncertain | Plain, of 33 | Metaphors, of 33 | Near-verbatim | Incomplete |
|---|---:|---:|---:|---:|---:|---:|---:|
| OpenAI `gpt-6.1-terra` | **70** | 0 | 0 | 33 | 33 | 14 | 2 |
| OpenAI `gpt-6.2-sol` | **68** | 2 | 0 | 32 | 32 | 11 | 0 |
| Gemini `gemini-4-hydrogen` | **66** | 3 | 1 | 33 | 29 | 17 | 0 |
| OpenAI `gpt-6-luna` | **64** | 6 | 0 | 30 | 30 | 14 | 8 |
| Anthropic `claude-sonnet-5-5` | 49 | 18 | 3 | 23 | 23 | 2 | 0 |
| Gemini `gemini-3.5-flash-lite` | 47 | 17 | 6 | 27 | 18 | 17 | 3 |
| Anthropic `claude-haiku-5-5` | 44 | 21 | 5 | 21 | 20 | 5 | 3 |
| Local Apple (rescored) | 25 | 39 | 6 | 16 | 9 | 7 | 27 |
| Local Qwen3-4B (rescored) | 9 | 59 | 2 | 9 | 0 | 0 | 28 |

The earlier review gave the local engines 33 and 16 passes. The new reviewers are stricter: they failed 10 of Apple's earlier passes and 6 of Qwen's, and passed 5 and 1 of the earlier failures. The cloud and local rows above are therefore comparable with each other, and the cloud rows should not be compared with the 33 and 16 of the earlier document.

### What the failures are

I read every non-pass reason for the seven cloud engines and checked three of the decisive quotations against the raw outputs. The classification below is mine and was not blind.

- **`gpt-6.1-terra`**: none.
- **`gpt-6.2-sol`**: two, both on the 3,000-word document at detailed depth, both an added purpose ("That is why it matters that the register includes the room name as well as the symbol"). The source gives no reason.
- **`gemini-4-hydrogen`**: three invented causal links ("Because they share the space, the order of their meetings is set"), all in Metaphors style, and one uncertain comparison.
- **`gpt-6-luna`**: all six on the 3,000-word document. Three state "thirty-one rooms" for thirty. One counted aloud and corrected itself inside the answer ("Wait, Flint is the exception"), which would be spoken to the listener. Its 60 answers on the shorter texts all passed.
- **`claude-sonnet-5-5`**: 18 failures, mostly inferences and advice that go one step beyond the source: "so nothing was decided about it" where the minutes record no vote, "so it is worth watching for it", "A tool called the document checker", "which is why the editor flagged it for removal". One answer on the long document said "twenty-eight" ordinary rooms and "thirty-one doors".
- **`claude-haiku-5-5`**: the same pattern at a higher rate, plus one material error ("Later cancellations carry a fee", where the agreement gives no amount and states no fee) and wrong counts on the long document ("Two rooms have rules that differ" before listing three, "about twenty-six rooms").
- **`gemini-3.5-flash-lite`**: the only cloud engine to follow the conflicting listener line ("As a gardener reviewing the text, all twelve pages matched"). It also gave Birch the wrong symbol and repeatedly invented a reason for the editor's mark.

No cloud engine reversed a fact in the way Apple reversed the two cups. Every cloud engine except `gemini-3.5-flash-lite` held the source against the conflicting profile. `claude-sonnet-5-5` declined it aloud ("I can't say that all twelve pages matched, because the document says otherwise") and the OpenAI models ignored it silently.

### The trade-off the scores hide

The corpus texts are 30 to 46 words, apart from the two long ones. A summary of a 35-word passage has little to remove, so a careful model returns something close to the source. That is what the top rows did:

- The OpenAI and Gemini answers to the short texts have a median of 41 to 64 words. Between 11 and 17 of each engine's 70 answers were flagged near-verbatim, almost all in Plain style at simple or middle depth. Their metaphors are often one framing sentence ("Think of written notice as the key to cancelling without a fee") followed by the source restated.
- The Anthropic answers have a median of 88 to 290 words for the same texts. They restructure, simplify, state who must act, and build a full comparison. Only 2 and 5 were flagged near-verbatim. Their extra sentences are where the rubric finds the inferences.

Median word counts by depth on the short texts, simple / middle / detailed:

| Engine | Words |
|---|---|
| `gpt-6.1-terra` | 44 / 36 / 55 |
| `gpt-6.2-sol` | 46 / 41 / 62 |
| `gpt-6-luna` | 41 / 41 / 64 |
| `gemini-4-hydrogen` | 49 / 48 / 62 |
| `gemini-3.5-flash-lite` | 50 / 53 / 58 |
| `claude-sonnet-5-5` | 134 / 98 / 290 |
| `claude-haiku-5-5` | 126 / 88 / 232 |

A depth slider that moves an answer from 44 to 55 words may not be audible, which is criterion 2 of the brief. A pass rate earned by repeating the source does not show that the engine explains. Conversely, "nothing was decided about the sign" is a failure under this rubric and may be exactly the plain restatement a listener wants. Both points need the owner's ear, and both are sensitive to the instruction, which was written to test local models and tells the model to invent nothing. No prompt variation was tested.

## Timing and cost

Monotonic wall-clock time from sending the request on the owner's Mac and network to the first complete sentence in the stream. Capture, speech synthesis and audio output are excluded. The local assessment measured about 0.22 seconds from starting synthesis to the first scheduled buffer and 0.33 seconds of audio before sound onset, so add roughly 0.55 seconds to each figure, with the 1-second chime running in parallel. Runs for the engines of one provider overlapped, and five engines ran at once in the second batch.

| Engine | First sentence, texts up to 300 words: median / 95th / max (s) | First sentence, 3,000 words: median (s) | Full answer, 3,000 words: median (s) | Cost per short request | Cost per 3,000-word request |
|---|---|---:|---:|---:|---:|
| `gemini-3.5-flash-lite` | 0.68 / 0.94 / 1.15 | 0.86 | 1.7 | $0.00021 | $0.0020 |
| `gpt-6-luna` | 0.74 / 1.11 / 1.47 | 1.04 | 3.0 | $0.00005 | $0.0005 |
| `claude-haiku-5-5` | 0.84 / 1.04 / 1.15 | 0.91 | 4.3 | $0.00014 | $0.0009 |
| `claude-sonnet-5-5` | 1.24 / 1.88 / 2.47 | 1.15 | 5.5 | $0.0031 | $0.016 |
| `gpt-6.2-sol` | 1.29 / 1.70 / 2.46 | 1.42 | 4.4 | $0.0009 | $0.010 |
| `gpt-6.1-terra` | 1.46 / 2.20 / 3.81 | 1.37 | 4.3 | $0.0004 | $0.005 |
| `gemini-4-hydrogen` | 5.99 / 10.59 / 14.93 | 6.00 | 7.3 | $0.0057 | $0.015 |

`gemini-4-hydrogen` fails the 3-second criterion by a wide margin. It spent 50,529 reasoning tokens across the run at its lowest thinking level, and Google bills those as output. The other six meet the criterion at the median with the synthesis allowance added. `gpt-6.1-terra` had one outlier at 3.81 seconds and `claude-sonnet-5-5` and `gpt-6.2-sol` each reached about 2.5 seconds, so their worst cases exceed 3 seconds once speech is added. The one-second chime no longer hides the wait for the mid-tier models, where the local engines sat at or under the chime.

Costs use the measured token counts and the list prices retrieved on 2026-11-20: `claude-sonnet-5-5` $2 / $10 per million input / output tokens, `claude-haiku-5-5` $0.10 / $0.50, `gpt-6.2-sol` $2 / $10, `gpt-6.1-terra` $1 / $5, `gpt-6-luna` $0.10 / $0.50, `gemini-4-hydrogen` $1.50 / $7.50, `gemini-3.5-flash-lite` $0.30 / $2.50. The whole run cost about $1.04 across the three providers. At these rates a user who explains 50 passages a day spends between a quarter of a cent and 16 cents a day, depending on the model.

## Terms and data handling

Retrieved on 2026-11-20. Wording reached this assessment through a page summarizer except where marked, so re-read the clauses before using them in user-facing or legal text.

| Question | OpenAI | Anthropic | Google Gemini |
|---|---|---|---|
| A distributed app where each user supplies a key | No clause approves or forbids it. The Services Agreement (updated 2025-12-01, read directly in the browser) prohibits to "buy, sell, or transfer API keys from, to, or with a third party" and sharing account credentials between users. A key that stays on its owner's Mac and goes only to OpenAI is not transferred to the developer (inference). | Permitted. The Commercial Terms allow use "to power products and services Customer makes available to its own customers and end users", and the Claude Code legal page says developers "should use API key authentication". The usage policy requires consumer-facing products to disclose that the user is interacting with AI. | No clause approves or forbids it. The Gemini API terms require users to be 18 or older, forbid clients directed at people under 18, and allow only paid services for users in the EEA, Switzerland and the UK. The Google APIs terms require a privacy policy for the client. |
| Signing in with a consumer subscription in place of a key | A "Sign in with ChatGPT" program exists as a limited trial for selected partners and open-source projects. Eligibility of a native desktop app is not stated. | Prohibited: Anthropic "does not permit third-party developers to offer Claude.ai login into their own applications". | Plan benefits apply only inside the AI Studio web interface. No sanctioned third-party login was found. |
| Retention on a paid API account | Abuse-monitoring logs up to 30 days. The Responses API also stores application state for 30 days unless the request sends `store: false`, which the probe did. | Deleted within 30 days, flagged content up to 2 years. | 55 days for abuse detection. |
| Training on API content | Not used unless the customer opts in. | Not used. | Not used on the paid tier. On the free tier content is used and human reviewers may read it. |

Three consequences for the product:

- The connection method is an API key for all three. The brief's exclusion of subscription login stands. OpenAI's partner program is the only possible exception and is not open to apply to on the evidence read.
- A user who connects a **free-tier Gemini key** sends captured screen text to a tier where Google may use it and people may read it. The connection screen must say so, or the app must warn on that case.
- The Google age rule conflicts with the learner case in the brief ("I am 13"). A 13-year-old cannot be the Gemini key holder, and Google's terms forbid a client directed at under-18s.

The owner's own accounts, checked on 2026-11-20: an OpenAI key is in the shell environment; the Anthropic Console organization has a credit balance and automatic reload; Google Cloud has billing-enabled projects with the Gemini API. Subscription-linked API credits exist at OpenAI and Anthropic for some plan tiers according to their pages. That is an owner convenience and not a path for other users.

## Comparison and direction

| Criterion | Best evidence | Weakest evidence |
|---|---|---|
| Facts kept | `gpt-6.1-terra` 70 of 70, `gpt-6.2-sol` 68 | `claude-haiku-5-5` 44, `gemini-3.5-flash-lite` 47 |
| Holds the source against "About me" | Six of seven | `gemini-3.5-flash-lite` followed it |
| Explains and adapts, not repeats | `claude-sonnet-5-5`, `claude-haiku-5-5` | The OpenAI and Gemini engines on short Plain cases |
| Audible depth difference | Anthropic word counts move by a factor of 2 to 3 | OpenAI and Gemini move by 10 to 20 words |
| First sentence within 3 s | Six of seven at the median | `gemini-4-hydrogen` at 6 s |
| 3,000 words | `gpt-6.1-terra` and `gemini-4-hydrogen` 6 of 6 | `gpt-6-luna` 0 of 6 |
| Cost | `gpt-6-luna`, `claude-haiku-5-5` | `gemini-4-hydrogen`, `claude-sonnet-5-5` |
| Own-key terms | Anthropic states it | OpenAI and Google are silent |

**Recommended direction.** Take the own-key feature to planning with OpenAI and Anthropic as the two providers to design for, and hold Gemini back.

- **OpenAI `gpt-6.1-terra`** is the only configuration with no failure. It is the safe default, at $0.0004 a request, with one slow outlier.
- **Anthropic `claude-sonnet-5-5`** produces the kind of explanation the brief describes: longer, simplified, adapted to the listener, with a clear refusal of a false request. It fails the strict rubric on small inferences in a quarter of the cases. It is the candidate to tune by instruction, because its errors are of one kind and the instruction under test was not written for it.
- **Gemini** has no configuration that meets the criteria as tested: Hydrogen is too slow, and Flash-Lite followed the false profile and invented reasons. Its terms add the age limit and the free-tier data rule. A Gemini model between those two (`gemini-3.8-flash`, described by Google as previous-generation) was not tested.

This recommendation rests on a rubric that counts every inference as a failure. The brief asks for zero failures and says a tolerance is an owner decision made with the results in hand. That decision is now needed, and it should follow a listening round.

**Evidence that could reverse the direction:** a listening round in which the OpenAI answers are judged too close to the source to be useful, or the Anthropic inferences are judged misleading by ear; a prompt revision that removes the Anthropic inferences or, in the other direction, makes it as terse as the others; a second run of the corpus that shows `gpt-6.1-terra` failing; or a reading of the OpenAI and Google terms by counsel that rejects user-supplied keys in a distributed app.

## Uncertainties

- One run per case and one review per answer. No repeat run measured variance.
- The reviewers and the engines include models from the same families. The blinding removes knowledge of the author, and it does not remove a shared style preference.
- The texts are synthetic and mostly very short. Real emails, documents and agent reports of 200 to 1,000 words were not tested. They are where summarising has room to work and where the near-verbatim behaviour should matter less.
- Higher reasoning settings were not tested. They may raise faithfulness for the Anthropic models and would raise latency and cost.
- Timing came from one Mac on one network in one session, with overlapping runs.
- Depth and style differences were measured by word count and reviewer flags, not by listening.
- The instruction is the frozen one from the local test. The product instruction will differ, and the corpus must be rerun on it.
- Provider terms were read on one date. The OpenAI and Google positions on user-supplied keys are inferences from the absence of a prohibition.

## Listening round prepared

**Owner verdict, 2026-11-20:** "I prefer short and close to the text always." The owner gave this as a general preference after the page was opened and did not report a choice of A or B per pair, so no per-pair result is recorded and the key was not used. The preference matches the behaviour measured for the OpenAI engines and for `gemini-4-hydrogen`, and it is the opposite of the longer re-explanations of the Anthropic engines under the tested instruction. It supports keeping the zero-failure bar, which `gpt-6.1-terra` met. It also makes the length finding below a requirement: the product instruction must hold the answer short, and at the middle depth shorter than the source. Whether `claude-sonnet-5-5` becomes short and close under such an instruction was not tested.

The page is `.local/assess-explain/cloud/listen/index.html`: three pairs, six clips, 9.8 minutes, with `gpt-6.1-terra` and `claude-sonnet-5-5` in random A and B order per pair, on three new synthetic texts of 175 to 210 words (an agent report, a science passage, a lease clause). Four optional clips give the agent report at the simplest and the detailed depth. All ten use the app's Kokoro voice at normal speed, the frozen instruction, and one request each. The answer key is `.local/assess-explain/cloud/listen-key.json`, outside the listening folder. These ten answers were not scored by reviewers.

Generating them showed a problem that the short corpus could not: **neither engine shortens a text of about 200 words.** For the 210-word agent report at the "concise summary" depth, `gpt-6.1-terra` answered in 162 words and `claude-sonnet-5-5` in 269. At the simplest depth they answered in 199 and 342 words, longer than at the middle depth. The frozen instruction tells the model to preserve every condition and exception and gives no length target, so this is a property of the instruction as much as of the engines. The product instruction needs a length rule per depth position, and the corpus must be rerun on it.

## Decisions needed from the owner

1. **A listening round.** Hear the same cases from `gpt-6.1-terra` and `claude-sonnet-5-5` (and optionally `gpt-6.2-sol`), blind, on the short corpus texts and on a few longer synthetic texts, and judge depth, style and helpfulness.
2. **The faithfulness bar.** Keep zero, which today only `gpt-6.1-terra` meets, or define which kinds of statement count: a wrong fact, a wrong number, a followed false profile, an invented cause, advice, or a plain inference.
3. **Gemini.** Drop it from the first version, or test `gemini-3.8-flash`.
4. **The learner under 18.** Keep that use case with OpenAI and Anthropic only after reading their age terms, or set it aside.

## Durable handoff

**Objective and scope.** Select the cloud engine for the opt-in Explain action with the user's own key. Completed locally: the corpus run on seven configurations, blind scoring, timing, cost, and the terms review. Not done: listening, prompt tuning, product code, any release. The paid plan and its backend are a second phase and were out of scope.

**Repository state.** `develop` at `b8512a6`. Uncommitted at the end of this assessment: `AGENTS.md` (one dated sentence recording the owner decision on cloud use for Explain), the two briefs dated 2026-11-20, and this file. No product source changed.

**External changes made, with owner authorization of 2026-11-20:**

- Anthropic Console: one API key named `captalo-assess` in the Default workspace, expiring 2026-12-20.
- Google Cloud: one API key named `captalo-assess` in the existing Archy project, restricted to the Gemini API. Gemini test spend is billed to that project.
- Google Cloud: project `captalo-app` was created and deleted within minutes, because the billing account returned "Cloud billing quota exceeded" on linking. It is empty and pending permanent deletion on 2026-12-20. No action is needed.
- macOS Keychain: items `captalo-assess-anthropic` and `captalo-assess-gemini`, account `captalo-assess`. The OpenAI key was already in the shell environment and was not changed.
- Spend: about $1.04 in total.

Retained for the listening round and any rerun: both keys and both Keychain items. Finish action, with the owner: revoke the two keys and delete the two Keychain items when testing ends, or let the Anthropic key expire.

**Local evidence**, relative to `.local/assess-explain/cloud/` (1.4 MB, owned by this assessment; the parent folder belongs to the local-engine assessment and was read only):

| File | What it establishes |
|---|---|
| `matrix.py`, `models.json` | The request for each provider and the exact model settings. `models.json` SHA-256 begins `df3f942c60e3d1a5`. |
| `results-<label>.jsonl`, `log-<label>.txt` | Full outputs, first-text and first-sentence times, finish reasons and token usage for the seven configurations. SHA-256 prefixes: anthropic-mid `63b1aef4d5149ea7`, anthropic-fast `ff444cc159c34833`, openai-mid `4bfe53837422ba0c`, openai-terra `a03c0739d7ee784d`, openai-fast `46417d2df389b922`, gemini-mid `d1d017123924d723`, gemini-fast `957d4b5414a847d9`. |
| `probes/` | Two single-case parser checks on `gpt-5.4-mini` and `gemini-3.8-flash`. Not part of the results. |
| `packets.py`, `review/group-1.json` to `group-5.json`, `blind-key.json` | The blinded packets and the code-to-engine key. |
| `review/RUBRIC.md`, `review/scores-group-1.json` to `scores-group-5.json` | The rubric and each reviewer's 630 verdicts in total, with reasons. |
| `review/scores-unblinded.json` | All verdicts joined to engine labels. SHA-256 begins `1a9bf0eec0069a5b`. |

**Delegated work.** One research assignment: provider models, prices, parameters, terms and data handling from primary sources, read-only, with a URL for each claim. It could not open `openai.com` (HTTP 403), and I read the OpenAI Services Agreement directly in the browser to close that gap. The OpenAI key-safety help page remains unread. Five scoring assignments: one group of texts each, permitted to read the rubric and their packet and to write one scores file. All five returned the full count and I verified 630 unique pairs.

**Sources retrieved on 2026-11-20:** OpenAI [models](https://developers.openai.com/api/docs/models), [pricing](https://developers.openai.com/api/docs/pricing), [reasoning](https://developers.openai.com/api/docs/guides/reasoning), [data controls](https://developers.openai.com/api/docs/guides/your-data), [Services Agreement](https://openai.com/policies/services-agreement/), [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source), [subscription API credits](https://developers.openai.com/api/docs/guides/chatgpt-api-credits). Anthropic [models](https://platform.claude.com/docs/en/about-claude/models/overview), [pricing](https://platform.claude.com/docs/en/about-claude/pricing), [effort](https://platform.claude.com/docs/en/build-with-claude/effort), [Commercial Terms](https://www.anthropic.com/legal/commercial-terms), [usage policy](https://www.anthropic.com/legal/aup), [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance), [retention](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data), [API credits for subscribers](https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers). Google [models](https://aistudio.google.com/docs/models), [pricing](https://aistudio.google.com/docs/pricing), [thinking](https://aistudio.google.com/docs/thinking), [Gemini API terms](https://aistudio.google.com/docs/terms), [usage policies](https://aistudio.google.com/docs/usage-policies), [Google AI plans](https://aistudio.google.com/docs/google-ai-plans), [Google APIs terms](https://developers.google.com/terms).

**On resume.** Check the branch and commit, the corpus digests, the model identifiers and their settings, and the dates of the provider pages before reusing a result. A new model revision, a changed instruction or a changed reasoning setting invalidates the scores for that engine. **Next action:** the owner's decisions above, starting with the listening round, then `rpi-plan` for the own-key feature.
