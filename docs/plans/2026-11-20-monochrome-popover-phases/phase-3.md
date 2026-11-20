# Phase 3: Wire-in

Parent: [monochrome popover plan](../2026-11-20-monochrome-popover.md).

## Goal

The menu-bar popover hosts the new panel. The old `SettingsView` is deleted. The owner accepts the result on a signed install.

## Entry conditions

- Phase 2 accepted, including the reviewer's comparison of the PNGs with the artboards.

## Design

```
@ CaptaloAppState.panelInput -> PanelInput
ctx: main actor; reads published state only
do:
  1. lookup setupEnvironment, voice list, voice, speed, loginItem, screenRecordingRequested
  2. lookup shortcut descriptions from KeyboardShortcuts.getShortcut(for:)
  3. lookup notices: shortcutRejection, regionFailureNotice, lastReadingError
  4. write PanelInput
fx: none
```

```
@ StatusItemController.present()
ctx: NSPopover, NSHostingController(LivePanelView)
pre: the icon is visible (existing guard, D36)
do:
  1. validate popover not shown and icon visible (unchanged)
  2. write state.refreshSetup() (unchanged)
  3. write selected tab = PanelModel.make(state.panelInput).initialTab
  4. emit activate + show + makeKey (unchanged)
fx: the panel opens on the tab that needs action
```

- `LivePanelView` observes `CaptaloAppState`, builds `PanelModel.make(state.panelInput)` in its body, and passes `state.panelActions`. It holds the selected tab; `StatusItemController` sets it on each open.
- `StatusItemController.width` and `.height` become 440 and 520. The comment about the grouped form's height (`StatusItemController.swift:11`) is replaced.
- The popover follows the system appearance (decision P5): no `appearance` is forced on the popover or its window.
- `popoverDidClose` also ends any recording state (stuck state 9) by resigning the first responder of the panel window.
- Delete `Captalo/UI/Settings/SettingsView.swift` and the forwarding `statusText` and `repairLabel` in `CaptaloAppStateVoice.swift`. `shortcutNotice` in `CaptaloAppStateSettings.swift:43` is deleted with its only reader; its three texts already live in `PanelModel` (phase 1).
- `StatusItemController.swift` stays in `Captalo/UI/Settings/` under its name, so `Scripts/shell-audit` needs no change.
- Docs: add notes D40 (this redesign: decisions P1 to P6, the probe result, the render command) to a new `docs/plans/2026-11-20-monochrome-popover-notes.md`. `docs/briefing.md:51` names only "the settings panel" and needs no change.

## Tasks

1. Add `panelInput`, `panelActions` and `LivePanelView`; switch `StatusItemController` to it; change the size.
2. Delete `SettingsView.swift` and the dead forwarding code; confirm with `grep -rn "SettingsView" Captalo` that nothing remains.
3. Independent review, repair, simplify, `make verify`.
4. Integration owner: local merge into `develop`, then `make install CONFIG=Release` for the owner checks. Worktree implementers do not run `make install`.
5. Write the notes file and the handoff.

## Acceptance

Automated:

- `make verify` passes 16 of 16.
- `grep -rn "SettingsView" Captalo Scripts` returns nothing.

Manual (owner, signed install):

1. A click on the menu-bar icon opens the new panel; a second click closes it (D36).
2. The panel opens at launch when setup is missing, and on reopen from Spotlight (D36).
3. Dark and light: switching the macOS appearance switches the panel; both match the artboards.
4. The popover arrow's shade is acceptable beside the panel in both appearances (decision P4). If it is not, that is a new owner decision, not a fix inside this phase.
5. Both keycap recorders record a new shortcut; Esc and a click elsewhere leave the old shortcut; the conflict alert still appears for ⌘Q (D36).
6. Recording the same shortcut for both actions shows the rejection text on the Read pane.
7. Each speed step and each voice takes effect from the next reading; the play button reads the sample.
8. With Accessibility revoked, the panel opens on Setup with the outlined card, and the button opens System Settings.
9. Launch at login switches on and off; Quit in the rail quits.
10. VoiceOver reads each rail item, pill and control with a meaningful label.

## Units

One unit; one owner. Files: `Captalo/UI/Settings/StatusItemController.swift`, `Captalo/UI/Panel/LivePanelView.swift`, `Captalo/App/CaptaloAppStatePanel.swift`, `Captalo/App/CaptaloAppStateVoice.swift`, `Captalo/App/CaptaloAppStateSettings.swift`, the deleted `SettingsView.swift`, and the notes document. The project uses file-system synchronized groups, so `Captalo.xcodeproj` needs no membership edit.
