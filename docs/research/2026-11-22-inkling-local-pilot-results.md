# Inkling 2 Mini missed Cáptalo’s local Explain gate

**Decision, 22 November 2026. Stop this configuration.** The original, three-pass Inkling 2 Mini passed **1 of 6 passages on each of three attempts per passage (3/18)**. The cup experiment was its only complete, faithful pass. Four short answers changed or blurred a source claim. All three attempts on the long register ended without any final text. Even the fastest short answer took 23.9 seconds to reach a sentence ready for speech with the model loaded.

## Blind verdict

Two independent AI readers scored 18 opaque items. The integration owner verified the exact archived Terra and Sol answer bytes against both the whole-file digests and the tracked per-answer receipts. Within each passage, the three Inkling answers were byte-identical, including the three empty register answers. Each distinct answer was shown once. A private map carried the verdict back to all 30 occurrences (18 Inkling, six Terra and six Sol). The repeats demonstrate repeatability on this runtime. They give no estimate for unseen passages or changed facts.

| Passage | Source / answer words | What the listener would hear | Quality |
| --- | ---: | --- | --- |
| Reading room email | 33 / 32 | “Volunteers enter Tuesday only” restricts volunteers to Tuesdays. The source restricts Tuesday entry to volunteers. The answer also drops when Mira sends the update. | Fail |
| Hall agreement | 40 / 37 | The caretaker must **receive** written notice by the deadline. “Later cancellations have no fee amount” also leaves a listener unsure whether later cancellation is free. The agreement leaves that amount unspecified. | Fail |
| Cup experiment | 46 / 23 | The uncovered cup had less water after one day. Temperature went unmeasured and the cause remained unknown. | Pass |
| Committee minutes | 31 / 30 | “Only east door gets blue paint” treats the work as settled. The committee only approved paint for that door. | Fail |
| Archive handover | 32 / 31 | “Outcome: not reviewed yet” claims no review took place. The source says the FIRST REVIEW label describes the next stage and cannot establish whether a review took place. | Fail |
| Room register | 3,000 / 0 | The model reached the token cap while still reasoning. The listener received none of the required facts. | Fail |

Of the 15 nonempty attempts, three passed literal fidelity and twelve failed. All 15 ended naturally, matched the requested style, and all four Middle answers were shorter than their source. The blank register item received a literal pass for introducing no claims. It failed completion, coverage and style on all three attempts. No passage failed solely because of length.

The two readers agreed on all scoring fields for 14 of the 18 distinct items. A third independent reader settled the four disagreements before unblinding and retained the agreed fields and fact indices. Across the 12 historical controls, all adjudicated fidelity, coverage, ambiguity, near-verbatim and style judgments matched the archived judgments. The fresh readers independently called out the Terra minutes answer for turning approval into an outcome. Historical overall scores were Terra 4/6 and Sol 4/6. Only the six Inkling passages enter its numerator.

The run ends here. The 83-case qualification remains reserved for a candidate that passes all six on all repeats and shows viable short-input timing. Its held-out variants change a number, an actor and an exception. The prompt stayed frozen. Distribution rights, ordinary-Mac suitability and native shortcut-to-audio testing were deferred under the agreed decision rule.

## Time to speech-ready text

The product target is three seconds from shortcut to first audible word for inputs up to 300 words. All 15 loaded short attempts already exceeded that limit before a complete sentence was available. Starting from an unloaded process also missed on all five short passages. The short sources were 31–46 words. No native shortcut, OCR or speaker playback was timed.

| Passage | Source words | Loaded seconds to first complete sentence, attempts 1 / 2 / 3 | Cold seconds to first sentence, attempt 1 |
| --- | ---: | --- | ---: |
| Reading room email | 33 | 108.9 / 109.1 / 104.0 | 118.7 |
| Hall agreement | 40 | 120.2 / 117.7 / 112.2 | 128.3 |
| Cup experiment | 46 | 66.1 / 67.5 / 69.2 | 73.1 |
| Committee minutes | 31 | 143.6 / 129.9 / 130.4 | 152.3 |
| Archive handover | 32 | 27.0 / 24.8 / 23.9 | 35.2 |
| Room register | 3,000 | No final text on any attempt | No final text |

The register used 4,094 reasoning tokens and two channel markers on each attempt. The 4,096-token cap stopped it after 155.7, 149.1 and 170.4 seconds from submission. None of the three answers communicated the Alder opening condition, the Oak board exception or the Flint closure. A blank answer supplies no evidence about whether the model would have misstated these facts.

## Download and memory

The original weights occupy 19,526,019,168 bytes. Ten tokenizer and configuration files bring the model download to **19,555,785,477 bytes (19.56 GB, 18.21 GiB)**. These are artifact sizes. The Python environment, speech assets and transport overhead are separate.

With Kokoro synthesizing throughout, peak MLX allocation was **24.07 GB** (22.42 GiB) on the register. The largest process-lifetime resident high-water mark for an Inkling worker was **14.84 GB**. Across model startup and inference, the largest sampled simultaneous worker-plus-Kokoro RSS was 13.64 GB. The voice process alone measured 1.03 GB at the post-warm-up baseline. These measures overlap and use different accounting. They cannot be summed into a minimum Mac memory specification.

The host was an M5 Ultra with 96 GiB, macOS 27.2.1. Host-wide swap was already 20,638 MiB before the model launched and reached 22,862 MiB. Free memory was 55% at baseline and reached a low of 29%. Other processes were running. Kokoro produced sustained 24 kHz PCM for 14,312 completed utterances. Verified synthesis intervals covered at least 99.91% of each request and included every observed first sentence. An independent sandbox connection control was killed and its local computation control passed.

## Reproduction

The original three-pass checkpoint and quantization were used with the pinned MLX-LM implementation, greedy decoding, effort zero, a 4,096-token cap and a fresh KV cache for every attempt. Each passage began in a new worker. Each worker loaded once. Cold timings include process launch and load, with a potentially warm file cache. The 18 loaded timings start at request submission. The output observer counted generated tokens by their channel and never sent reasoning text to Kokoro. The concurrent voice synthesized neutral sentences so its load was present even while Inkling was reasoning.

The tracked specification binds the original model digest and runtime commit. The implementation notes record the environment lock and smoke-test repair. The integration owner retains the original snapshot, pinned runtime, answer files, telemetry, blind labels, all votes and gate receipts in the primary checkout under `.local/inkling-six/`. The temporary speech stores, generated helper binary and measured processes were released. These private records can reproduce the verdict offline. The next retention review is the owner's next local model evaluation. [Candidate specification](../../Qualification/Explain/model-pilots/inkling-six-spec.json) · [Frozen protocol](../plans/2026-11-22-inkling-pilot-protocol.md) · [Implementation notes](../plans/2026-11-21-inkling-local-pilot-notes.md) · [Numerical receipt](../../Qualification/Explain/model-pilots/inkling-six-v1.json)
