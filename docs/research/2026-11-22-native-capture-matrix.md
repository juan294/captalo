# Read Selection in six Mac apps

All six mandatory sources delivered the selected test passage. Four met the 150 ms target for stopping with an empty selection. Rex took 1.095 s and Preview let the sentence finish. Pressing the shortcut again with the original selection still highlighted stopped speech in 19–51 ms across all six. These results apply to the installed Release on one Mac Studio.

## Measurements

Each start is the time from sending the configured Option+[ shortcut to the first speech-level sample at Cáptalo’s output. Cold means the first read after restarting Cáptalo with the models already installed. The driver waited at least four seconds after the new process appeared. A successful read requires the voice to be ready; an independent startup-ready timestamp was unavailable. Warm means another reading in the same process. Stop is the time from the second shortcut to the last observed speech sample. Values are individual observations unless a range is given.

| Source | Selected passage | Cold start | Warm start | Stop, same selection | Stop, empty selection |
| --- | --- | ---: | ---: | ---: | ---: |
| Rex Beta 0.1.0 (server preview.21) | Match | 1.535 s | 0.540–0.574 s on three rechecks | 51 ms | 1,095 ms |
| Safari 27.2 | Match | 1.440 s | 0.567 s | 43 ms | 66–74 ms |
| Google Chrome 157.0.8103.79 | Match | 1.426 s | 0.571 s | 19 ms | 34–43 ms |
| Preview 11.0, selectable PDF | Match | 1.419 s | 0.544 s | 45 ms | Played to the end |
| TextEdit 1.21 | Match | 1.438 s | 0.553 s | 38 ms | 56 ms |
| Microsoft Word 16.117, read-only document | Match | 1.431 s | 0.556 s | 37 ms | 9 ms |

The initial Rex warm press yielded neither a capture event nor speech. A second missing read occurred while gathering isolated audio controls. Three consecutive presses with an independently verified selection and settled focus then spoke in under 0.58 s. The missing presses remain unexplained. The range describes successful starts only.

The source app kept focus on the synthetic passage. Immediately around the canonical capture shortcut the clipboard checks agreed in all six sources. With no selection and the reader idle, all six produced zero speech-level samples during an observed two-second window and retained focus and clipboard. Preview reported a capture failure on this control.

## Why empty Stop failed

- In Rex the empty selection invoked its approved synthetic Copy. The Release logged nothing selected after 1.053 s and then stopped. Rex can report an empty accessibility selection for highlighted text. The accepted Copy policy waits up to one second for the terminal to respond. Treating every empty accessibility answer as a stop would discard real selections. [Rex decision](../plans/2026-11-15-captalo-core-reader-notes.md#d31-rex-selection-through-a-synthetic-copy-owner-decision-10-2026-11-19)
- In Preview the failure reproduced both on an empty PDF and after clicking to clear the highlight on the same text-bearing page. Copy returned no usable text and the Release logged a failed capture, followed by natural completion. Speech continued for 2.022 s and 1.246 s respectively. A failed capture currently keeps the previous reading alive. The reader needs affirmative evidence that the PDF highlight is empty before using this gesture to stop. [Capture handling](../../Packages/CaptaloCore/Sources/CaptaloCore/Capture/CaptureCoordinator.swift#L73) · [Playback handling](../../Packages/CaptaloCore/Sources/CaptaloCore/Request/RequestCoordinator.swift#L119)
- The next product decision is how users can reliably stop from either app. Repeating the shortcut on the still-highlighted passage already works in both. An explicit Stop action could bypass selection capture. Changing the Rex Copy window or treating every failed Preview Copy as an empty selection would also affect users trying to read a real selection.

## Replacing spoken text

Each app produced at least one switch in which the beginning matched the old sentence, the next speech matched an isolated recording of the new sentence, and the meter detected no returning old speech in the observation window. The new sentence began about 0.54–0.56 s after the replacement shortcut in the passing trials. Safari's accepted trial included a natural pause before the shortcut.

Two repeats fell short of a clean match. In the first Rex switch, the first 1.2 seconds matched the new sentence, then the audio observer missed about 93 ms of samples. Two fresh switches with independent controls passed. Chrome passed its first switch, but part of the second recording exceeded the sound-comparison error limit. Neither questionable trial proves that the old voice continued. In Rex, changing the selected text sometimes changed the clipboard before the shortcut. Separate before-and-after checks on both follow-up switches confirmed that the Cáptalo shortcut preserved what was on the clipboard when it was pressed.

The comparison used two isolated readings of each sentence. The original 20 ms comparison varied when the same recorded sound landed at different offsets inside a time bin. A follow-up anchored controls at speech onset and retained the stricter error limits. It accepted a known switch, rejected unchanged old audio and detected injected stale tails. Both analyses and the unsuccessful trials are retained. The initial Safari control selected the browser address field; the accepted run explicitly focused the local fixture page and verified the target selection before the shortcut.

## Test conditions and evidence

The installed Apple Development-signed Release was built from clean commit `cadd6b3`. The production reader and speech paths match the study base `d7c4863`. The host ran macOS 27.2.1 on an M5 Ultra with 96 GiB of memory. The installed app occupied 142 MiB on disk and its application-support directory occupied another 91 MiB on this machine. After the readings, macOS reported a **389 MiB physical memory footprint** for Cáptalo and a **710 MiB lifetime peak** for that process. This excludes the source apps. A first-install download and a lower-memory Mac were outside this run, so these figures do not establish a minimum RAM requirement.

The capture oracle used the same adapters as Release in a separate nonactivating process. It compared the whole selected passage with the canonical fixture after collapsing whitespace; the installed app recorded its own content-free capture and playback events. Word exposed its read-only page through its native Accessibility selection range. The original Preview fixture inserted a line break inside a word. The corrected generator wraps at word boundaries, and a regression test reads the actual PDF through PDFKit. The corrected PDF matched all 71 source tokens in live Preview. [Fixture generator](../../Makefile#L157) · [Regression test](../../Scripts/tests/test_capture_pdf.py#L17)

A private CoreAudio tap observed Cáptalo alone on the Mac Studio Speakers route at output volume 0.125. The detector used valid host timestamps and a −40 dBFS threshold; continuing callbacks provided silence coverage. No microphone or raw audio recording was used. This measures speech onset at the process output. It cannot establish physical speaker latency, subjective voice quality or pronunciation of every word.

The retained local evidence is in `.local/native-six-run/` (capture, timings, activity, event log and fixture checks), `.local/native-six-capture/` (adapter oracle), and `.local/native-six-audio/` (meter, speech comparison and controls). The existing clipboard exception applies: a foreign write during Copy or restoration, or a late Copy, can defeat ownership checks. This study only reports the observed test windows. [Accepted clipboard conditions](../plans/2026-11-15-captalo-core-reader.md#L58)

All task-created native fixture documents and the four scratch Rex sessions were closed. The original clipboard was restored. All 17 process-audio meters released their taps and private audio devices. The original Rex application regained focus and the installed Release remained running after the launch tests. No second Mac was tested because the primary acceptance run found two stop failures.
