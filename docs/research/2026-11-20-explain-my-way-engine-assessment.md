# Which local engine can Cáptalo trust to explain a passage aloud?

Assessed on 2026-11-20 against local `develop` at `cadd6b3bdae509fa2a01dbbedec6c3f786b2251b` in `/Users/juan/code/captalo`. The owner-supplied design brief was an untracked input at assessment time, SHA-256 `fb6e06e285d6ab07b421064b9da20f9c88b9acaaaeb6e601d9781ea7987d40db`. The optional overlay `.rpi/project/rpi-assess.md` was absent. The stock assessment and durable-handoff rules applied.

**Hold engine selection.** Both candidates produced material factual errors on ordinary short texts. In a plain summary Apple switched which cup held less water. In a metaphor Qwen told a group it could cancel late without a fee, although the agreement gave no late-fee amount. A blind listening preference can establish which explanations are easier to follow. It cannot resolve either error. Preserve the existing reader and return the Explain decision to the owner before planning.

## Decision and criteria

The decision is whether one engine can carry both Explain shortcuts into planning. A spoken explanation that changes which person must act, drops a condition, or asserts an invented fact can leave a listener with the opposite understanding. The brief makes a single invention a sample failure. Speed and listener preference are separate criteria. The owner also requires audible differences between settings, faithful coverage of 3,000 words, local processing with no attempted connection or retained user text, and a first spoken word within three seconds for up to 300 words. The full one-second chime overlaps generation. Read keeps its existing behavior. [Design brief, lines 51–59 and 68–96](2026-11-20-explain-my-way-brief.md)

## What the reader can measure today

The verified source registers Read Selection and Read Region and prepares the voice at launch (`Captalo/App/CaptaloApplicationDelegate.swift:17` and `:24`). Selection reserves a request before capture (`Captalo/App/CaptaloAppStatePlayback.swift:32`). Region waits for the user's drag before OCR (`Captalo/App/CaptaloAppStateRegion.swift:29` and `:50`). Speech consumes an already formed reading and its units (`Captalo/Services/Speech/SpeechService.swift:50`). An explanation still arriving sentence by sentence has no corresponding entry point in that path. An older request can lose ownership to a newer one (`Packages/CaptaloCore/Sources/CaptaloCore/Request/RequestCoordinator.swift:109`). That boundary matters if generation continues during playback.

Cáptalo's typed log accepts counts, durations and enumerations. It distinguishes a scheduled buffer from one that played (`Packages/CaptaloCore/Sources/CaptaloCore/Logging/PrivacyLog.swift:6` and `:34`). A model's first token, its first complete sentence, synthesized audio samples and sound at the device are four different measurements. A region timing also contains time the user spends drawing. For later acceptance, record keydown, region release, first complete sentence and first audible speech on the same clock. Preserve the owner's keydown criterion and report the drag interval separately.

## Engine facts

| Decision factor | Apple Foundation Models | Qwen3-4B-Instruct-2507, MLX 4-bit |
|---|---|---|
| Setup and availability | Use the default **on-device** system model. Check availability at use time. Eligibility, disabled Apple Intelligence, locale and assets still preparing can prevent use. This Mac returned available. Apple manages assets. Its published macOS 27 storage figures cover Apple Intelligence as a whole. | The publisher supplies a non-thinking instruction model. The MLX conversion has 2,278,972,236 bytes of repository files, including a 2,263,022,417-byte tensor. An explicit user-initiated download is needed on a Mac without the weights. Apple Intelligence enablement is independent of this path. |
| Context | Input, instructions, conversation and output share the budget. The macOS 26 baseline is 4,096 tokens. This M5 Ultra on 27.2.1 reported 8,192. Hardware, OS model revision and actual tokenization matter. | The upstream configuration advertises 262,144 tokens. That is an architectural limit. KV cache, prefill, output budget, memory alongside Kokoro and time to first speech constrain a useful local limit. |
| Integration and maintenance | Native Swift, streaming snapshots, OS-owned updates. Input or generated output can trigger a guardrail error. A refusal can also arrive as ordinary text. An OS change warrants rerunning the corpus. | The pinned conversion and upstream weights declare Apache 2.0. Direct MLX Swift registers Qwen3 and has a macOS 14 package minimum, compatible on paper with this project's macOS 26 floor. The app would own asset integrity, license notices, setup, cancellation, memory and runtime updates. |
| Cost and control | No separately distributed app weights or per-request on-device API fee. No app-controlled pin of the system weights. | No paid inference service. The app can pin weights and tokenizer. Disk, download and support are real costs. A Python MLX result would still need verification using the shipped Swift build. |

Apple evidence was checked on 2026-11-20 against the installed SDK and the on-device runtime, plus Apple's documentation retrieved through Sosumi. The model is revision-dependent. Apple documents input and output safety checks separately from regional and asset availability. [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) · [Context size](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize) · [Generation safety](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output) · [Prompt changes across versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions) · [WWDC26 framework session](https://developer.apple.com/videos/play/wwdc2026/319/) · [Supported devices and storage](https://support.apple.com/en-us/121115)

Qwen evidence was checked on 2026-11-20. The conversion revision is `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`. The tensor's published SHA-256 is `2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f`. The Swift integration evidence is pinned separately at `6759555f2bd8f18c242102d73d149efde9f2f2e0`. [Upstream model card](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) · [Pinned MLX conversion](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/tree/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b) · [Swift architecture registry, line 67](https://github.com/ml-explore/mlx-swift-lm/blob/6759555f2bd8f18c242102d73d149efde9f2f2e0/Libraries/MLXLLM/LLMModelFactory.swift#L67) · [Swift package manifest, line 10](https://github.com/ml-explore/mlx-swift-lm/blob/6759555f2bd8f18c242102d73d149efde9f2f2e0/Package.swift#L10)

A cache inspection found Fluid-1 as well as a speculative-decoding assistant. A one-sentence synthetic smoke test of Fluid-1 ran while its terms were being checked. Its publisher requires permission for research or product use, so it was excluded from scoring and further runs. The assistant model requires a target model. Neither establishes Qwen's performance. [Fluid-1 publisher terms](https://huggingface.co/altic-dev/FluidIntelligence)

## Bake-off design

Eleven synthetic English texts covered a volunteer email, an agent's document check, a hall agreement, a classroom experiment, committee minutes, a quoted instruction in a poster, an inventory, a conditional schedule, an archive handover, a 300-word report and a 3,000-word document. The long document has thirty 100-word entries and three distinct exceptions at the start, midpoint and end. It tests coverage across distance. Its repetitive wording makes it an easier compression problem than a heterogeneous long document.

Each text was paired with simple, middle and detailed depth, each in Plain and Metaphors styles. Four extra agent-report prompts covered Real-life examples, Paint a picture, an accountant's background and a background asking the model to contradict the source. The main agent-report prompts specify a nontechnical listener. The committee prompts specify a gardener. All 70 prompts were frozen before the first matrix run. Each candidate receives the same English instruction and JSON-encoded source, profile, depth and style. Output must be speakable prose and illustrations must be signalled as comparisons. Every case starts a fresh session. The matrix is a single run per combination. Its counts describe these outputs only.

The fixture set has SHA-256 `f5a42e82686df71604a2407cb0d31ac7550849653030dce954de778a21725f02` and the full ordered prompt set has SHA-256 `38ce85624169459141baa3b3a0e190b43b8c190d72ab30338b618c776619512a`. The retained copies are `.local/assess-explain/run/texts.json` and `cases.json` in the primary worktree. The host was an Apple M5 Ultra with 96 GiB unified memory, running macOS 27.2.1 (26B131). This host cannot establish minimum-tier memory behavior or the output quality of the macOS 26 system model.

## Faithfulness results

All 140 requests returned text. Two reviewers each compared one engine’s outputs to the frozen source, followed by a cross-check of the decisive errors against the original text. A pass means the reviewer found no unsupported assertion. Material omissions and usefulness were assessed separately. An explicitly marked illustration can pass. When the illustration could be heard as a new source fact, the listener-facing case remains unpassed. The reviewers were aware of their engine, and the counts have no claim to population accuracy.

| Inputs | Apple passes | Qwen passes |
|---|---:|---:|
| Main matrix, 66 per engine | 31 | 15 |
| Additional style and profile tests, 4 per engine | 2 | 1 |
| Total confirmed passes, 70 per engine | **33** | **16** |

Apple had 37 scored failures. Qwen had 50 scored failures and four ambiguous metaphors. Those four are included among the 54 Qwen samples without a confirmed pass. Each engine also failed in Plain style, so restricting the conclusion to problems with metaphor would miss ordinary summary errors.

| Main fixture, six settings each | Apple passes | Qwen passes |
|---|---:|---:|
| Volunteer email | 6 | 1 |
| Agent report | 2 | 4 |
| Hall agreement | 4 | 0 |
| Classroom experiment | 2 | 4 |
| Committee minutes | 0 | 1 |
| Poster proof | 4 | 1 |
| Tile stock sheet | 5 | 2 |
| Map-room schedule | 0 | 0 |
| Archive handover | 2 | 1 |
| 300-word register | 3 | 1 |
| 3,000-word register | 3 | 0 |

On 3,000 words, Apple preserved all three exceptions, including their conditions and exclusivity, in three of six responses. Two of those three also passed faithfulness. One was effectively a verbatim read. Qwen mentioned all three exception topics in four of six responses. All six contained a material error. Its middle Plain response correctly located the exceptions at the beginning, middle and end, yet called the symbols unique when six symbols repeat across thirty rooms. All six Qwen runs ended at the model's end-of-sequence marker. Checking for truncation by token count alone would have missed these failures.

## What the outputs said

| Source and setting | Apple | Qwen |
|---|---|---|
| Two cups, middle depth, Plain | First said the covered cup held less, then said the uncovered cup did. The first sentence about the result reverses the observation. | Identified the uncovered cup and preserved uncertainty about the cause. |
| Hall agreement, simple, Metaphors | Turned cancelling a booking without a cancellation fee into leaving without paying. | Concluded twice that late cancellation carries no fee. The agreement specifies no amount. |
| Inventory, detailed, Metaphors | Gave the correct counts of sixteen and fourteen blue tiles, then said six tiles were missing. | Calculated the difference as two and said the cause was unknown. Its garden metaphor also described an unnoticed harvest, an image the source does not support as a literal cause. |
| Agent report, middle, Plain | Turned publication into putting the pages online. | Kept the ten matches, the two skipped pages, the missing captions, the required editor review and the publication boundary. |
| Same report, contradictory “About me” | Began by asserting all twelve pages matched. | Preserved the correct count initially, then asserted all twelve matched in content. |

The quoted cancellation instruction in the poster and the conflicting listener profile exercised two different trust boundaries. The profile failure occurred despite keeping the source and profile in separate JSON fields and explicitly instructing each engine how to treat them. The order of the invented claim also matters for streaming. Apple could speak a false count immediately. Qwen could speak a correct opening before introducing the contradiction at the end.

For the accountant profile, Apple used double-entry bookkeeping and Qwen used a financial auditor. Both therefore demonstrated that the profile can influence the comparison. Qwen made the editor responsible for approving entries even though the source only requires review. Apple's analogy replaced the explicit requirement to review before publication with a reference to closing the books. Two Apple settings on the 300-word report, simple Metaphors and middle Plain, returned exactly the same wording. Each changed one article in the source. A listener cannot distinguish that pair by its words. The blind round tests the other audible differences independently.

## Timing, capacity and privacy

These are monotonic wall-clock measurements from in-process request submission through the first punctuation-delimited sentence emitted by the model. They exclude capture, speech synthesis, audio-device latency and model setup. The first call remains in each distribution. Apple’s system service had been exercised by a smoke test, and Qwen's weights had been loaded once. Startup from a freshly booted Mac remains unmeasured.

| Main matrix, median (observed range), seconds | Apple | Qwen |
|---|---:|---:|
| First complete sentence, inputs up to 300 words, 60 cases | 0.820 (0.613–1.618) | 0.168 (0.103–0.604) |
| First complete sentence, exactly 300 words, 6 cases | 0.926 (0.725–1.543) | 0.360 (0.228–0.450) |
| First complete sentence, 3,000 words, 6 cases | 3.275 (2.905–4.330) | 1.533 (1.464–1.650) |
| Complete response, 3,000 words, 6 cases | 36.014 (9.628–81.883) | 3.254 (2.188–4.961) |

Apple used the on-device default model, greedy streaming, Swift 6.4 and SDK 27.0. Qwen used local MLX 0.32.3, mlx-lm 0.31.4.dev132 and Transformers 5.18.0. Eager Qwen load took 0.477 seconds in this run. Peak tracked MLX allocations reached 2.979 GB on the short main cases and 3.626 GB on the long ones. These counters exclude other processes and non-MLX allocations. The Apple client process excludes the OS inference service, so there is no comparable Apple RAM figure. Simultaneous generation with Kokoro and the optional own voice on a lower-memory Mac remains unmeasured.

The 3,000-word prompt fit this Apple model. Its 3,375–3,381 prompt tokens plus 125 instruction tokens would leave little output space in a 4,096-token session. A short summary could fit that remaining space. Apple's observed simple Plain response instead reproduced 3,000 words, correcting ten articles. Adequate input capacity alone predicts neither summary quality nor the space the reply needs. In a separate 9,000-word control the framework counted 10,204 total tokens against the 8,192-token limit and returned a typed `LanguageModelError.contextSizeExceeded` with zero response text. Cáptalo's spoken over-limit sentence still requires an Explain path. Qwen's six long replies all ended naturally within the 2,048-token harness output ceiling. Its advertised maximum context was not exercised.

The approved Qwen download verified all 13 files against the pinned revision. Subsequent generation ran with networking denied to the process, using a local model path and offline library settings. Python recorded zero observed network events in its audit. The denial does not enumerate every attempted native or system connection. The 70 Apple rows used the on-device API under ordinary host networking. The separate over-limit control ran with outbound denial on the client. Kokoro rendering used a separately isolated store and outbound denial. The host stayed connected. Synthetic text and clips were deliberately recorded for judging. End-to-end operation with the host offline, no connection attempts by dependent services, and no writes of real captured or generated text remain product-level acceptance checks.

### Speech readiness on this Mac

The benchmark rendered the exact first sentence from every response to an input of at most 300 words, including the four supplemental cases. It used Cáptalo's production Kokoro synthesizer and reading session, the installed Release model bundle, af_heart at 1×, a warm voice and a local PCM sink. Cases from the two engines were interleaved. The onset was the first 5 ms block at or above −40 dBFS RMS. The threshold measures sound energy. Identifying the first spoken word at the output device requires a separate playback measurement.

| Warm timing, 64 cases per engine, seconds | Apple | Qwen |
|---|---:|---:|
| Median time from starting synthesis to first scheduled buffer | 0.220 | 0.244 |
| Median offset within the audio to onset | 0.325 | 0.325 |
| Modeled onset with a full one-second chime, median / 95th percentile / max | 1.362 / 2.256 / 2.315 | 1.325 / 1.350 / 1.370 |

For each row the estimate takes the later of chime end and measured first-sentence completion plus synthesis to its onset-bearing buffer, then adds the measured PCM offset. All 64 rows per engine fell within three seconds in that model. Eight Apple rows and zero Qwen rows exceeded two seconds. The chime floor narrowed the median difference between engines to 37 ms. A selection taking time to capture, slow drawing, audio-device buffering, cold startup or concurrent generation and synthesis can change the result. No Explain shortcut or signature sound exists in the tested baseline. The three-second product criterion and the trigger for reconsidering the wait sound remain open.

## Owner listening and decision

**Owner verdict pending.** The model download was approved separately. No listener preference, depth ordering or style identification has been recorded. The local listening page is `.local/assess-explain/listen/index.html`. Start with **Compare settings** to order depth and identify styles without labels. **Same request, two explanations** pairs the same prompt across engines, with the source available to check a claim. Random clip IDs hide engine and settings. The complete pack has 140 recordings arranged in 70 matched pairs. Total audio is 2 h 37 min 45 s. The focused depth and style comparisons can be heard independently of the full library. Each recording uses the same Kokoro voice, rate and output format. All WAV hashes, source mappings and page paths were checked. A headless browser found all 140 local media URLs and decoded sample tracks. The answer key is kept outside the listening folder.

**Keep both tested configurations out of the plan.** Qwen offers faster generation, version pinning and ample input capacity. Apple avoids an app-managed download and produced more source-faithful samples in this run. Both made precisely the kind of error the listener cannot readily detect without a transcript. Neither the latency advantage nor the convenience addresses that failure. Automatic fallback would conflict with the one-engine decision in the brief.

Evidence that could change the decision would be a separately identified local configuration that preserves facts on the frozen cases and on fresh passages with changed numbers, roles and exceptions, including the conflicting-profile case. It would also need to explain the full long document at the requested depth and pass the owner's blind listening comparison. The owner can decide whether a further assessment is worthwhile. Narrowing the supported styles or changing the faithfulness threshold would change the accepted brief. Until then, the current reader remains the supported action.

The week-long real-use and chime-fatigue verdicts belong to a working feature. No product Explain action, finished chime, signed build change, audition of the own voice, real-user capture or release was part of this assessment. Empty Explain capture, spoken handling above the product limit, cancellation after partial generated speech, and preservation of read behavior through an eventual integration remain open.

## Durable handoff

The primary worktree holds the curated assessment. The local Graphify search identified selection and region entry points, which were then checked against the source at the stated commit. Three bounded investigations supplied Apple framework verification and judgments, MLX verification and judgments, and local Kokoro audio and timing. They used synthetic fixtures, locally installed runtimes and standalone assessment probes. Juan explicitly approved the 2.28 GB Qwen weight download. The application source, dependencies and machine settings were outside the change. No new dependency installation or serving endpoint was required.

The assessment owns `.local/assess-explain/` in the primary worktree. Retain the verified model snapshot, 91 MiB assessment voice store, frozen corpus, probe sources, result files, anonymous recordings and score key for Juan's listening decision and any rerun he authorizes. The reusable application model stores belong to their existing owners. All timed and rendering processes exited. The local listening pack occupies 454,424,394 bytes. Review disposal with Juan after the audition. For follow-up, check the current branch and source, the design-brief digest, corpus digest, model revision, host version and manifest before reusing results. A different system model, prompt, quantization or speech voice can invalidate the corresponding evidence. The Apple result JSONL SHA-256 is `1d5f11b97b77c50cae3a33eb04f4e63754f9a2ff972cdb0d73a38a062b11e528`. The Qwen result SHA-256 is `e8b44a5f0947e37d0985419c7f8e7fc5068215c8559b1848b569c44e9548147d`.

| Local evidence relative to `.local/assess-explain/` | What it establishes |
|---|---|
| `run/corpus.py`, `run/cases.json`, `run/texts.json` | Exact synthetic texts, order, profile data, instructions and combinations. |
| `apple/matrix.swift`, `apple/results.jsonl`, `apple/review.json`, `apple/limit-typed.log` | Apple streaming measurements and full outputs, per-row judgments, and typed over-context error with zero emitted snapshots. |
| `mlx/model-manifest.json`, `mlx/run.json`, `mlx/matrix.py`, `mlx/results.jsonl`, `mlx/review.json`, `mlx/python-network-audit.json` | Download identity, runtime and sampler, output, finish reasons, memory, per-row judgments and scoped network audit. |
| `speech/render.swift`, `speech/sentence-timing.swift`, `speech/measure.py`, `speech/first-PCM.jsonl` | Voice path and per-sentence warm audio measurements. |
| `listen/index.html`, `listen/audio/`, `speech/listen-audit.json`, `speech/blind-key.json` | Blind listening round, audio integrity and answer mapping. |
