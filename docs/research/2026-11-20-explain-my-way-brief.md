# Design Brief: Explain it my way

> Brainstormed on 2026-11-20 with the owner. No project overlay exists at `.rpi/project/rpi-brainstorm.md`, so the stock `rpi-brainstorm` procedure applied without overrides.

## Problem

Cáptalo reads visible text aloud, from a selection or from a screen region, and the owner finds that useful as it is. A full read is often more than the listener needs or not the form the listener understands best. Someone who reads emails, documents and LLM output in terminals and editors all day frequently wants the content explained at a chosen depth and in a manner that suits them, for example in plain words for a non-technical person, with real-life examples, or as a metaphor. Today the only choices are to hear everything as written or to paste the text into a separate assistant, which leaves the Mac and breaks the flow.

The owner sees the same mechanism serving learners: a 13-year-old who struggles with a textbook passage, a lawyer or accountant reading technical output, a person who learns visually and wants the content described as a picture.

## Goal

A second action, on its own shortcuts, that captures the same text as a read and speaks an explanation shaped by the listener's settings, with all processing on the Mac.

This moves the product promise from "If I can see it, I can hear it" toward "understand what you see, in the way that works for you". The existing read stays.

## Scope

**In:**

- Two new user-chosen shortcuts with fixed meanings: "Explain selection" and "Explain region". They sit next to the two existing read shortcuts.
- Listener settings in the menu-bar panel (hybrid model, option C):
  - A depth slider, from the simplest wording ("explain it like I am 5") to a detailed explanation. The default is the middle position, a concise summary.
  - A short style list: Plain, Real-life examples, Metaphors, Paint a picture.
  - One free-text "About me" line, where the listener states background, age, profession or a playful theme.
- One local language model as the engine, selected by a bake-off before the plan.
- Wait handling: a signature chime of about 1 second plays at once on the key press and always plays in full. The menu-bar glyph shows activity while the model works. Speech starts when the chime has ended and the first sentence is ready, and the rest is generated during playback.
- The chime as a sound asset: very pleasant, in the character of meditation sounds, made so that repeated daily use does not tire the listener. The Spoken Letter recordings are the owner's reference for a signature sound. They were not inspected during this brainstorm.

**Out:**

- Any cloud model, including an opt-in one under the user's own key. Cáptalo is the local option for privacy.
- Rephrasing or rewriting text for tone. macOS already does this.
- Languages other than English for input and speech. The voice decision in force is English only.
- Saved profiles that the user switches between. One set of listener settings exists at a time.
- Any transcript or text view of the explanation.
- A chime on the read shortcuts. Reads start almost at once and stay as they are.
- A mode switch that changes what the existing read shortcuts do.

**Backlog (recorded, not part of this effort):**

- "What is asked of me": speak only the requests, decisions, deadlines and open questions in an email or agent report.
- Explain a single word, idiom, error message or code line in its context.
- Outline first: the skeleton of a long document, one line per heading.
- Listenable read: a faithful read prepared for the ear, where code blocks, paths, hashes, URLs and tables are named and skipped. This is an improvement to the existing read, not a new mode.
- Skeptic: what the text claims without evidence or leaves out.
- Translation. Speaking Spanish needs a Spanish voice.
- Ask by voice: a spoken follow-up question about the selection.
- An option to turn the chime off, which the owner named as a possible revenue opportunity. No business model was decided.

## Constraints

- All text, OCR, language-model and speech processing stays on the Mac. No network connection during capture, generation or speech. Captured and generated text is not retained on disk or in logs. `PrivacyLog` remains the only logging API for app code.
- One code path per action and no fallbacks without approval. The feature ships with one engine, not a chain of engines.
- A model download, if the chosen engine needs one, is an explicit one-time setup operation started by the user, as with the own-voice model.
- The app stays nearly invisible: no Dock icon, no floating window, settings in the menu-bar panel only.
- macOS 26 minimum, Swift, SwiftUI and AppKit, with pure logic in `Packages/CaptaloCore`.
- The current silence rule for a failed or empty capture stays in force for the read shortcuts. How an explain shortcut behaves on an empty capture is for the plan to define, because the chime plays on the key press.
- Clipboard, focus and permissions are preserved exactly as the capture layers do today.

## Chosen Approach

**One "explain" action driven by listener settings.** The owner chose a single new action whose result depends on who the listener is and how they learn, in preference to several task-specific modes with one shortcut each. The task-specific modes went to the backlog. Reason: the settings give many combinations from one mechanism and one pair of shortcuts, and they match the product idea of a tool that adapts to how a person understands.

**Settings model: hybrid (C).** Rejected: fixed dials only (A), because fixed lists of backgrounds never cover everyone, and free text only (B), because results would depend entirely on how well the model follows free instructions and nothing would be one click away. The hybrid keeps the common choices testable and lets the free line cover professions, ages and playful themes. The app therefore ships no preset named after a third party's franchise.

**Local only.** Rejected: local by default with an opt-in cloud model. It would give the best quality and long-text handling, and it would break the privacy position.

**Engine by bake-off.** Two candidates: Apple's on-device model through the Foundation Models framework in macOS 26, and a downloaded open model run with MLX. The comparison below is from memory and was not verified in this session; the assessment must verify it.

| | Apple on-device model | Downloaded open model |
|---|---|---|
| User setup | None when Apple Intelligence is on | One-time download of several GB |
| Availability | Only Macs with Apple Intelligence enabled | Any Apple silicon Mac with enough memory |
| Long text | Small context window, chunking needed | Larger window, depends on the model |
| Control | Changes with OS updates, has its own content guardrails | Pinned version, a license to track |

The bake-off runs 10 to 15 synthetic texts (an email, an agent report, a legal paragraph, a textbook passage, a long document) through both candidates at three slider positions and two styles. The owner listens and judges. Faithfulness to the source is pass or fail, and time from key press to first spoken word is measured. One engine wins and goes into the plan. Rejected: choosing either engine now without listening evidence. The own-voice engine was chosen by the same method.

**Shortcuts: two new ones (A).** Rejected: a Read or Explain switch for the existing shortcuts (B), because a hidden state can make the app speak a metaphor when a read was expected, and without a transcript that is hard to notice. Rejected: selection only at first (C), because terminal text that needs the region rectangle is one of the main cases.

**Wait handling: short fixed chime, glyph activity, first-sentence start.** Rejected: silence until speech, because a long gap feels like a failure and invites a second key press. Rejected: a chime of about 3 seconds, because it forces that wait on every use even when the answer is ready sooner. Not chosen for now: a short mark followed by a soft sustained bed. Rule for revisiting: if the bake-off shows typical waits well above 2 seconds, reconsider the bed.

## Success Criteria

The numbers in items 4 and 5 were proposed during the brainstorm and the owner accepted them without change. The bake-off may show that they need adjustment, which would be an owner decision.

1. **Faithfulness.** On the bake-off text set, the spoken explanation states no fact, number, name or instruction that the source does not contain. Any invented detail fails that sample. Metaphors and examples are allowed when they are framed as comparisons.
2. **The settings change the result audibly.** For the same text, the owner can tell the leftmost, middle and rightmost slider positions apart by ear, and can tell each style apart, without knowing which setting was used.
3. **"About me" is respected.** With "I am not technical" in the field, an agent report is explained without unexplained jargon. With a profession in the field, a comparison comes from that field at least once.
4. **Time to first spoken word.** At most 3 seconds from the key press for a text of up to 300 words on the owner's Mac. The chime starts at once on the key press.
5. **Long text.** A selection of 3,000 words produces a complete explanation with no silent truncation. Above the supported limit, the app says so in one spoken sentence and does not explain part of the text as if it were the whole.
6. **Privacy.** Capture, generation and speech work with the network disabled, and no network connection is attempted. The captured text and the generated text are not written to disk or to logs.
7. **The existing read is unchanged.** The two read shortcuts behave exactly as they do today, with no chime.
8. **The chime.** It plays in full on every explain, lasts about 1 second, and the owner judges it pleasant after a week of repeated use.
9. **Owner verdict.** After one week of the owner's own use on real emails, documents and agent output, the owner still uses the feature and judges it helpful for understanding.

## Open Risks

- **Errors are hard to notice by ear.** The listener hears the explanation and cannot see it. A metaphor or a themed retelling moves further from the source than a summary does, so an invented detail can pass unnoticed. Criterion 1 exists for this reason, and a small local model may fail it.
- **Neither engine may be good enough.** If both candidates fail faithfulness or the listening verdict, the feature as designed is not buildable locally today. That outcome stops the effort and returns the decision to the owner.
- **Engine facts are unverified.** The Foundation Models availability rules, context size and guardrail behaviour, and the size, memory use and license of a suitable open model, are remembered and not checked.
- **Memory and disk.** A downloaded language model runs next to the Kokoro and own-voice speech models. Behaviour on an ordinary Mac is unknown.
- **Long text.** Chunking can lose the thread between parts or repeat content. The 3,000-word criterion may not be reachable with the Apple model.
- **Free-text "About me" is an instruction channel.** The model may follow it poorly, or text inside a captured document may act as instructions to the model. The plan needs a position on both.
- **Chime fatigue and timing.** A sound on every use can become tiring despite its character, and when the model is faster than the chime, the chime adds delay.
- **Empty capture.** The chime plays on the key press, before the app knows whether a capture succeeded. The behaviour for a failed capture is undefined.
- **Revenue from removing the chime** is an idea, not a decision. Charging to remove a sound can read as hostile to users, and the product has no payment mechanism or business model on record.
- **Product position.** The feature widens Cáptalo from a reader to an explainer. The briefing and the copy ("Escúchalo. Cáptalo.") describe a reader.

## Next steps

1. `rpi-assess`: verify the engine facts against primary sources and run the bake-off with the owner's listening verdicts.
2. `rpi-plan`: write the phased plan from this brief and the assessment result.
