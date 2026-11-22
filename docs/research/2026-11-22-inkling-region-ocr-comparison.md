# Inkling recognized three more words. Keep Apple Vision for Read Region.

On 22 November 2026, Cáptalo’s Vision reader and Inkling 2 Mini transcribed the same two synthetic PNGs offline on a 96 GiB M5 Ultra. Inkling reproduced all 128 reference words, including numbers and punctuation. Vision made three word substitutions. Both followed the intended column order and kept the timetable’s routes, departures and prices together. These two samples establish a real advantage on one page, with too little coverage to estimate accuracy on other documents.

## What a listener would experience

| Fixture | Vision word edits | Inkling word edits | Vision time to first speech-ready audio | Inkling time to first speech-ready audio |
| --- | ---: | ---: | --- | --- |
| Two columns, 104 words | 3 | 0 | 27.30 s on the first request; 0.38 and 0.31 s on follow-up | 36.11 s with weights loaded |
| Ferry timetable, 24 words | 0 | 0 | 0.37 s on the initial run; 0.35 and 0.33 s on follow-up | 10.62 s with weights loaded |

On the two-column page, Vision rendered “nineteen” as “nineteer,” “Echo.” as “cho.” and “the captain” as “le captain.” Its repeated transcripts were identical. The 27.30-second first request is a user-relevant slow observation. The cause and its frequency on end-user machines remain unknown. Prioritise measuring fresh-install and first-use Vision latency before promising uniformly fast startup.

The main comparison used one fresh helper per route and one request per image in the order shown, with the same prewarmed local Kokoro Heart voice. Timing began at PNG submission and ended when Kokoro supplied the first audio buffer containing signal. The complete transcript went to the voice, as in the current region reader. Screen dragging, screenshot capture, device playback and physical speaker onset were outside the measurement. For Vision the recognition stage alone took 27.16 and 0.27 seconds. A second Vision helper read each image twice to investigate the slow first request. Inkling loading was excluded from the table: launching its process and preparing the model added 15.18 seconds. Even with a hypothetical text-streaming implementation, Inkling produced its first final text only after 30.67 and 8.43 seconds, respectively.

## What the installer and machine would carry

| Resource | Current Vision + Kokoro reader | Original Inkling + Kokoro route |
| --- | --- | --- |
| OCR assets distributed by Cáptalo | 0 additional bytes. Recognition uses macOS Vision. | 19,555,785,477 additional bytes for weights and metadata, excluding the inference runtime. |
| Voice models | 95,331,935 bundled bytes | Same voice assets |
| Peak process memory footprint on this Mac | 0.79 GB for the helper running production Vision recognition and Kokoro (0.82 GB in the follow-up) | 25.97 GB for the Inkling worker; 0.83 GB for the separate Kokoro helper |
| Peak MLX allocation during OCR | Inapplicable | 22.73 GB on the two-column page; 21.99 GB on the table |

Process footprint is Darwin’s lifetime peak from `/usr/bin/time -l`. It includes setup. Individual process peaks and MLX allocation overlap and cannot be added to derive a system-wide requirement. The Vision helper figures exclude work macOS may perform in other processes. GB is decimal. No measurement was made on a lower-memory Mac. The Inkling process footprint on the Studio alone exceeded the installed RAM of a 16 GiB machine. Treating this configuration as the default would ask every user to carry the extra storage and working set for an accuracy gain seen on just one fixture.

## Decision and evidence

Keep Vision as the default. The first-use delay and three transcription errors are worth following up on the current reader. When evaluating a cheaper correction or smaller OCR model, keep this page as a regression test, include new screenshots representative of actual failures, and compare transcription, ordering, **first-use and repeat** speech latency, download size and footprint on a lower-memory Mac. A candidate that delivers the same words with lower resource demands serves more users.

The reference comes from the strings and layout in [the fixture renderer](../../Scripts/make-ocr-fixtures.swift). Scoring used minimum token insertions, deletions and substitutions after whitespace normalization, preserving case and punctuation, followed by a check of reading order and row bindings. Vision used the project’s [production recognizer](../../Packages/CaptaloOCR/Sources/CaptaloOCR/VisionRecognizer.swift) and document ordering. Inkling used the verified original [checkpoint and pinned MLX runtime](../../Qualification/Explain/model-pilots/inkling-six-spec.json), actual pixel embeddings, greedy decoding, effort zero, a fresh context and a 4,096-token limit per image. The fixed prompt asked for exact transcription in reading order without commentary. Both outputs reached natural end on the first attempt. The model received only the PNG and the instruction.

The primary checkout retains the fixed protocol, helpers’ source, complete transcripts, reference, scores, process logs and model/fixture hashes in `.local/inkling-ocr-compare/`. The benchmark changed no app behavior.
