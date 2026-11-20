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

### M5. The render draws the panes without the recorder and without scrolling (phase 2)

- Plan said: the render and the live panel use the same views, and the pane body is a scroll view.
- Found: `ImageRenderer` draws no AppKit view and no scroll view content.
- Chose: the environment value `panelIsRender` (false by default, true only in `--render-panel`) swaps `KeycapRecorder` for its `KeycapsLabel` and draws the pane top-aligned and clipped, so content taller than the pane cuts the footer in the image. The live panel scrolls.
- Why: an image with a blank scroll area proves nothing. `read-all-notices` (every notice at its longest) is about 16 pt taller than the pane: all notices are readable in the image and the footer is cut, which is the overflow the live scroll view handles.

### M6. Captions changed from the mockup (phase 2)

- The shortcut captions are "Select text, then press" and "Press, then drag on screen": the mockup's longer texts wrapped to two lines beside the keycaps.
- The Voice caption is "Play a sample or choose a voice. A sampled voice becomes the voice in use, from the next reading.": the existing `playSample` also selects the voice, and this plan changes no state method.
- The unset-shortcut hint says "click Record" (it said "click the field"): the control is now a button named Record (review finding 11).

### M7. Smaller differences from the phase 2 design (review finding 1)

- The render uses `ImageRenderer` at scale 2, not an `NSHostingView` with a bitmap rep. `Scripts/panel-render-check` reads the PNG header itself, not `sips`, so its tests run on any host.
- The probe posts its key events with `NSApplication.postEvent`, and it starts each recording through `KeycapRecorderController.begin()`, the function the keycap button calls. It sends no mouse event, so the button's hit area is an owner check in phase 3 (check 5).
- The probe has a fifth step: a Tab press while idle must not give the hidden field the keys. Idle, the field refuses the first responder (review finding 6).
- Fewer files than the unit list: the rail, header and footer are in `PanelRootView.swift` with `PanelActions`; `SpeedControl` is in `ReadPane.swift`; the switch style is in `PanelComponents.swift`; the render command and the probe are in `PanelDebugCommands.swift`. The tab binding is named `tab`.
- `--render-panel` writes to the directory it is given and does not check that it is under `.local/build/panel-render`; `make panel-render` always passes that path and removes only `*.png` there.
- The phase 2 units were done by one implementer in sequence; no batch worktrees were used.

## Phase 2 evidence

- Entry probe, Debug build of the worktree, 2026-11-20 (final run, after the review fixes):

```text
panel-recorder-probe: ok   1 a click on the keycaps makes the recorder the first responder
panel-recorder-probe: ok   2 a key-down stores the shortcut, calls onChange once and shows keycaps again
panel-recorder-probe: ok   3 Esc shows keycaps again and keeps the stored shortcut
panel-recorder-probe: ok   4 losing the first responder shows keycaps again
panel-recorder-probe: ok   5 Tab while idle does not give the hidden recorder the keys
panel-recorder-probe: ok   cleanup: the probe's defaults key is gone
panel-recorder-probe: passed
```

  The owner's `KeyboardShortcuts_readSelection` and `KeyboardShortcuts_readRegion` values were read before and after the first run and were unchanged.
- `make panel-render`: 16 images at 880 x 1040. The implementer viewed `read-ready-dark`, `read-all-notices-light`, `read-all-notices-dark`, `voice-ready-dark`, `setup-permission-missing-dark` and `setup-recording-requested-light`.
- Independent review (fresh context, read-only; viewed 12 images and ran a hue scan over all 16): no blockers, 6 should-fix, 10 nits. No amber or orange in any image. No setting, notice or recovery action of `SettingsView` is missing. Fixed: 4 (overflow now top-aligned), 6 (idle field refuses focus; window observed from the start; Tab step), 7 (`panelIsRender`, safe default), 8 (`rm -f *.png`), 11, 13, 14, 15, the Voice card border and the rail dot position from 5. Recorded: 1 and 2 (M5 to M7). Left as is: 3 (the switch knob is white in both appearances), the other small differences in 5 (12.5 pt "In use", `textPrimary` for the active rail item, title weight), 9 (the recording field covers part of the caption; owner check), 10 (comment added), 12, 16.
