# Notes: monochrome popover

Plan: `2026-11-20-monochrome-popover.md`. Owner acceptance on 2026-11-20 with continuation across phases 1 to 3, then a local merge into `develop` and removal of the worktree. Project overlay: `.rpi/project/rpi-implement.md` does not exist; no overlay or declared override applies.

Worktree: `/Users/juan/code/captalo-wt-popover`, branch `feat/monochrome-popover`, from `develop` at `2c1e74b`. Its `.local/models` was a copy of the main checkout's verified voice files (no download); `Scripts/fetch-models` verified the copy against the manifest. No task service or database was allocated.

## D40. The menu-bar panel was redesigned (owner decisions P1 to P6, 2026-11-20)

- The grouped form is replaced by a rail (Read, Voice, Setup, Quit), one pane per section, a status pill and a footer, 440 x 520 pt, monochrome with green for positive state only, in the system's light or dark appearance. The container is still the `NSPopover` of D36.
- `CaptaloCore/Panel/PanelModel.swift` decides the pills, the rail dots, the tab a newly opened panel shows and every state-dependent text. `Captalo/UI/Panel/` draws it. `CaptaloAppState.panelInput` and `.panelActions` connect it to the unchanged state methods.
- Shortcuts show as keycaps; a click swaps in the library's `RecorderCocoa` in the same place until recording ends, so the library's conflict alerts stay the only path that stores a shortcut.
- D30 is partly closed: `make panel-render` draws eight panel states in both appearances to `.local/build/panel-render/` and is the 16th `make verify` check (local only). It does not draw the live recorder field or the popover itself.

## Deviations

### M1. The voice texts moved without a forwarding extension (phase 1)

- Plan said: move `statusText` and `repairLabel` to `CaptaloCore` and keep the app extension as a forward until phase 3.
- Found: a member with the same name in the app module and in `CaptaloCore` is ambiguous or calls itself.
- Chose: the app extension in `CaptaloAppStateVoice.swift` was deleted in phase 1.
- Why: the forward cannot compile.

### M2. Static labels stay in the views (phase 1 review, finding 12)

- Plan said: the model decides every piece of text.
- Found: the pane models carry state and state-dependent text only.
- Chose: fixed labels ("Allowed", "Use", "In use", "Record", "Launch at login", section titles, captions, the footer) are literals in the views.
- Why: a fixed label has no state to test, and the render check shows it.

### M3. Small differences from the phase 1 file list (review findings 1 to 3)

- `ReadingPreferences.label(for:)` and the `VoiceInstallState` texts are in `Panel/PanelText.swift`, and the label tests are in `SpeedLabelTests`. The factory is `PanelModel.make(_:)`. `PermissionRow.detail` is not optional.

### M4. The Fn modifier is a keycap (phase 1 review, finding 5)

- Plan said: four modifier glyphs.
- Found: KeyboardShortcuts 3.1.0 writes Fn as a globe glyph with a text variation selector.
- Chose: `ShortcutKeycaps` treats the globe as a modifier (`functionModifierIsItsOwnKeycap`).

### M5. The render draws the panes without the recorder and without scrolling (phase 2)

- Plan said: the render and the live panel use the same views, and the pane body is a scroll view.
- Found: `ImageRenderer` draws no AppKit view and no scroll view content.
- Chose: the environment value `panelIsRender` (false by default, true only in `--render-panel`) swaps `KeycapRecorder` for its `KeycapsLabel` and draws the pane top-aligned and clipped, so content taller than the pane cuts the footer in the image. The live panel scrolls.
- Why: an image with a blank scroll area proves nothing. `read-all-notices` (every notice at its longest) is about 16 pt taller than the pane: all notices are readable in the image and the footer is cut, which is the overflow the live scroll view handles.

### M6. Captions changed from the mockup (phase 2)

- The shortcut captions are "Select text, then press" and "Press, then drag on screen": the mockup's longer texts wrapped to two lines beside the keycaps.
- The Voice caption is "Play a sample or choose a voice. A sampled voice becomes the voice in use, from the next reading.": the existing `playSample` also selects the voice, and this plan changes no state method.
- The unset-shortcut hint says "click Record" (it said "click the field"): the control is now a button named Record.

### M7. Smaller differences from the phase 2 design (phase 2 review, finding 1)

- The render uses `ImageRenderer` at scale 2. `Scripts/panel-render-check` reads the PNG header itself, not `sips`, so its tests run on any host.
- The probe posts its key events with `NSApplication.postEvent`, and it starts each recording through `KeycapRecorderController.begin()`, the function the keycap button calls. It sends no mouse event, so the button's hit area is an owner check.
- The probe has a fifth step: a Tab press while idle must not give the hidden field the keys. Idle, the field refuses the first responder.
- Fewer files than the unit list: the rail, header and footer are in `PanelRootView.swift` with `PanelActions`; `SpeedControl` is in `ReadPane.swift`; the switch style is in `PanelComponents.swift`; the render command and the probe are in `PanelDebugCommands.swift`.
- `--render-panel` writes to the directory it is given; `make panel-render` always passes `.local/build/panel-render` and removes only `*.png` there.
- One implementer did the phase 2 units in sequence; no batch worktrees were used.

### M8. A requested Screen Recording permission opens Setup (phase 3 review, finding 3)

- Plan said: optional items never change the opening tab or raise a dot.
- Found: a region press without Screen Recording opens the panel (owner decision 8). With the plan's rule it opened on Read, with a "Ready" pill and no dot, while the "Allow" and "Quit and reopen" controls were on Setup. The old form showed them at once.
- Chose: while Screen Recording was requested and is not granted, Setup has a dot and is the opening tab when nothing required is missing (`requestedScreenRecordingOpensSetup`). A Screen Recording permission that was never requested still changes nothing (`optionalItemsNeverRaiseADot`). The pills do not change.
- Why: stuck state 6 must be visible where the panel opens.

### M9. Smaller differences from the phase 3 design (phase 3 review, findings 1, 4, 6)

- The size is `PanelMetrics.width` and `.height`; `StatusItemController.width` and `.height` are removed. The selected tab is held by `PanelSelection`, owned by `StatusItemController`.
- The recorder is ended in `popoverWillClose`, while the panel still has its window.
- The opening tab is chosen when the panel opens. A state that arrives while the panel is already open (for example a voice that fails after launch) adds the rail dot and does not move the user to another tab.

## Evidence

Phase 1 (commit `63a4336`):

- TDD: `PanelModelTests.swift` was written first and failed to compile ("cannot find 'PanelInput' in scope") before the model existed.
- Independent review (fresh context, read-only): no blockers; 4 should-fix, 6 nits. Fixed: 5 (M4), 7, 8, 9, 11. Recorded: 1 to 4 and 12 (M1 to M3). Accepted as is: 6 (the voice error has two inputs; the adapter sets both from `lastReadingError`), 10 (the login row is a pass-through).
- `make verify`: 15 of 15 passed on `63a4336`.

Phase 2 (commit `017f00d`):

- Entry probe, Debug build of the worktree, final run after the review fixes:

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
- `make panel-render`: 16 images at 880 x 1040. The implementer viewed six of them; the reviewer viewed 12 and ran a hue scan over all 16 (no amber or orange).
- Independent review (fresh context, read-only): no blockers, 6 should-fix, 10 nits. No setting, notice or recovery action of `SettingsView` is missing. Fixed: 4, 6, 7, 8, 11, 13, 14, 15, and the Voice card border and rail dot position from 5. Recorded: 1 and 2 (M5 to M7). Left as is: 3 (the switch knob is white in both appearances), the other small differences in 5 (12.5 pt "In use", `textPrimary` for the active rail item, title weight), 9, 10, 12, 16.
- `make verify`: 16 of 16 passed on `017f00d`.

Phase 3:

- Independent review (fresh context, read-only): no blockers, 2 should-fix, 8 nits. Parity with the deleted `SettingsView` was confirmed control by control. Fixed: 3 (M8), 6, 7, 9. Recorded: 1 and 4 (M9). Kept: 8 (`SetupState.showsVoiceError` and `SetupEnvironment.lastReadingError` have no reader in the app now; they stay with their test). Open for the owner check: 5 and 10 (below).
- `grep -rn "SettingsView" Captalo Scripts` returns nothing.
- `make verify`: 16 of 16 passed on `041efa3`. The merge into `develop` has the same tree as `041efa3`, so the result covers it; only this notes file changed after it.

## Known limits (owner checks on the signed install)

Nothing in this plan ran the live popover: opening, the appearance switch, the recorder inside the popover and the close path are proven only by source review, the probe (a plain window) and the renders. The ten checks of `2026-11-20-monochrome-popover-phases/phase-3.md` are the proof, with these additions:

- Check 5: after the ⌘Q conflict alert, the slot shows the old keycaps. The old recorder resumed recording after the alert; the new one probably ends it (INFERRED, review finding 5).
- Check 5: while a shortcut records, the field covers part of the caption beside it.
- A region press without Screen Recording opens the panel on Setup (M8).
- The popover arrow's shade beside the panel, in both appearances (decision P4).

## Handoff

- Objective and scope: the plan, all three phases, completed locally and merged into `develop` with a merge commit. Nothing was pushed, released or installed, and `.github/workflows` is unchanged.
- The worktree `/Users/juan/code/captalo-wt-popover` and the branch `feat/monochrome-popover` were removed after the merge. Its 16 renders and three verify logs are kept in the ignored `.local/monochrome-popover-evidence/` of the main checkout.
- Next action: the owner checks above on a signed install (`make install CONFIG=Release`, integration owner).
