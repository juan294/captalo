# Use the personal voice for reading

Use the existing selection and region actions, including the merged global shortcuts. Snapshot the accepted engine choice and speed when captured content becomes a reading, as the current session factory does. A voice change while a region is being selected therefore applies to that region. Update readiness checks in CaptaloAppStatePlayback.swift:14,31 and CaptaloAppStateRegion.swift:11 to check the chosen engine. Preserve each capture action’s permission checks. Keep the built-in voice ID separate from the personal profile. Existing preferences validate identifiers against the Kokoro manifest. Existing installations should open with the same selected built-in voice. [Reading preferences](../../../Packages/CaptaloCore/Sources/CaptaloCore/Shell/ReadingPreferences.swift#L31)

At the speech session factory, use the selected engine with the existing ReadingSession, TextPreparer and single AVAudioSink. Feed the engine a sentence or existing bounded part of a long sentence at a time. Keep the current 0.30-second sentence pause and additional 0.35-second paragraph pause. Add neither pause inside a split sentence. Return complete 24 kHz mono units to the existing scheduler. A helper stream's first PCM chunk can precede the app's first playable unit. [Speech session factory](../../../Captalo/Services/Speech/SpeechService.swift#L50) · [Queue and pauses](../../../Packages/CaptaloCore/Sources/CaptaloCore/Reading/ReadingSession.swift#L209)

```
@ readWithVoice(request, preferences) -> playback
pre: request still owns capture
do:
  1. snapshot the engine, profile and speed
  2. validate readiness for that engine
  3. synthesize each existing unit and validate its request identity
  4. enqueue audio on the shared sink
fail: unavailable selected profile -> disclose the problem and offer a new choice
```

Honor all six existing speed settings. Where the model lacks native speed, time-stretch synthesized units with pitch preservation before queueing and account for the resulting duration. Test that a single component applies speed. Keep pauses governed by the reader's existing timing. Preserve Stop during capture, generation and playback, stale-reply suppression, device-change recovery and subsequent requests. Close a stuck worker and release its resources. Use the Phase 2 preview ownership tests as regression controls. Allow built-in reading independently of repair or download of the optional model.

**Automated acceptance.** Use a delayed synthetic engine and a capturing sink to test both capture paths, a preview interrupted by Read, Stop followed by new Read, deletion during generation, empty/invalid audio, a worker crash and recovery, speed changes on the next reading, and changing voice during pending region capture. A broken Kokoro installation must allow an otherwise ready personal voice to read. Extend the existing stop and speed cases at ReadingSessionTests.swift:347,361,410. Compare unit order, count, boundaries and PCM duration at each speed. Use the existing Kokoro tests as the regression oracle. Run make verify.

**Native acceptance.** Read known selected text and an OCR fixture in the accepted voice, stop during speech, then start a new reading in a built-in voice. Check a change of output device. Observe no late audio from the stopped reading. Watch the helper exit and its memory release after switching away.

**Work split.** Playback, queue, selection and cancellation changes share one owner to preserve ordering.
