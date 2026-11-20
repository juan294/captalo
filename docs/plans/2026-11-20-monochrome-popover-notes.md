# Notes: monochrome popover

Plan: `2026-11-20-monochrome-popover.md`. Owner acceptance on 2026-11-20 with continuation across phases 1 to 3, then a local merge into `develop` and removal of the worktree. Project overlay: `.rpi/project/rpi-implement.md` does not exist; no overlay or declared override applies.

Worktree: `/Users/juan/code/captalo-wt-popover`, branch `feat/monochrome-popover`, from `develop` at `2c1e74b`. Its `.local/models` is a copy of the main checkout's verified voice files (no download); `Scripts/fetch-models` verifies the copy against the manifest.

## Deviations

### M1. The voice texts moved without a forwarding extension (phase 1)

- Plan said: move `statusText` and `repairLabel` to `CaptaloCore` and keep the app extension as a forward until phase 3.
- Found: a member with the same name in the app module and in `CaptaloCore` is ambiguous or calls itself.
- Chose: the app extension in `CaptaloAppStateVoice.swift` is deleted in phase 1. The only reader, `SettingsView.swift`, imports `CaptaloCore` and reads the moved members unchanged.
- Why: the forward cannot compile. The main plan's consumer sweep line "the properties stay" is true for `shortcutNotice`, `regionFailureNotice` and `loginItem` only.

### M2. Static labels stay in the views (phase 1 review, finding 12)

- Plan said: the model decides every piece of text.
- Found: the phase 1 pane models carry state and state-dependent text only. Labels that never change ("Allowed", "Use", "In use", "Record", "Launch at login", section titles, captions, the footer) have no model field.
- Chose: the model decides state and every text that depends on state; fixed labels are literals in the views.
- Why: a fixed label has no state to test, and the render check shows it.

### M3. Small differences from the phase 1 file list (review findings 1 to 3)

- `ReadingPreferences.label(for:)` and the `VoiceInstallState` texts are in `Panel/PanelText.swift`, and the label tests are in `SpeedLabelTests`, not in the files the plan named. The factory is `PanelModel.make(_:)`. `PermissionRow.detail` is not optional (every row has one).

### M4. The Fn modifier is a keycap (phase 1 review, finding 5)

- Plan said: four modifier glyphs.
- Found: KeyboardShortcuts 3.1.0 writes Fn as a globe glyph with a text variation selector.
- Chose: `ShortcutKeycaps` treats the globe (with and without the selector) as a modifier (`functionModifierIsItsOwnKeycap`).

## Phase 1 evidence

- TDD: `PanelModelTests.swift` was written first and failed to compile ("cannot find 'PanelInput' in scope") before the model existed.
- Independent review (fresh context, read-only): no blockers; 4 should-fix, 6 nits. Fixed: finding 5 (M4), finding 8 (rejection with the shortcut unset), finding 9 (`eachNoticeAloneRaisesTheReadDot`), finding 7 (pills are three stored values with an exhaustive switch), finding 11 (`offStepSpeedSelectsTheNearestStep`). Recorded as deviations: findings 1 to 4 and 12 (M1 to M3). Accepted as is: finding 6 (the voice error has two inputs; the phase 3 adapter sets both from `lastReadingError`), finding 10 (the login row is a pass-through; its variants are tested in the existing login item tests).
- Known behavior, by plan: while the voice is still preparing, the Read pill says "Ready" (`SetupState` treats a checking voice as pending).
