# Phase 1: Panel model

Parent: [monochrome popover plan](../2026-11-20-monochrome-popover.md).

## Goal

`CaptaloCore` decides every state and every string the new panel shows. No app or view code changes in this phase; the current panel keeps working.

## Entry conditions

- The plan is accepted (decisions P1 to P6, light palette included).
- A worktree or local branch from `develop`.

## Design

New directory `Packages/CaptaloCore/Sources/CaptaloCore/Panel/`. All types are `public`, `Equatable` and `Sendable`. No AppKit, no SwiftUI.

```
@ PanelModel.make(input: PanelInput) -> PanelModel
ctx: pure; input = SetupEnvironment + voice list + selected voice + speed + shortcut descriptions + notices + LoginItemRow + screenRecordingRequested
pre: input.voices may be empty while the voice is not ready
do:
  1. compute setup = SetupState.evaluate(input.environment)
  2. compute pills: read, voice, setup (text + kind: positive, neutral, pending)
  3. compute attention dots per tab from setup.requiredMissing and notices
  4. compute initialTab: first required missing item's tab, else notices -> read, else read
  5. write pane models: ReadPaneModel, VoicePaneModel, SetupPaneModel
br: voice == .checking -> voice pill pending, never an attention dot
br: optional items missing -> no dot, no change of initialTab
fail: none; every input maps to a model
```

Tab of each required item: `voice` to Voice, `accessibility` to Setup, `readShortcut` to Read.

Pill text (exact):

| Tab | Condition | Text | Kind |
|---|---|---|---|
| Read | setup ready | "Ready" | positive |
| Read | any required item missing | "Needs setup" | neutral |
| Voice | `.ready` | "Installed" | positive |
| Voice | `.checking` | "Preparing" | pending |
| Voice | any other state | "Needs attention" | neutral |
| Setup | Accessibility granted | "All set" | positive |
| Setup | Accessibility missing | "1 step left" | neutral |

Screen Recording is optional (decision 8) and never changes the Setup pill.

Pane models:

- `ReadPaneModel`: `selection: ShortcutSlot`, `region: ShortcutSlot` (each `keycaps: [String]`, empty when unset), `shortcutNotice: String` (never empty; the three texts of `CaptaloAppStateSettings.swift:43` move here unchanged, selected by `readShortcutSet` and `shortcutRejection`), `voiceError: String?`, `regionNotice: String?`, `speedSteps: [SpeedStep]` (label, value, selected), `voiceName: String`.
- `VoicePaneModel`: `voices: [VoiceCard]` (id, display name, `inUse`), `status: String?` and `repairLabel: String?` for states other than ready. `statusText` and `repairLabel` move from the app extension (`CaptaloAppStateVoice.swift:60`, `:68`) into `CaptaloCore` as methods on `VoiceInstallState`; the app extension is deleted in phase 3 with its last reader.
- `SetupPaneModel`: `accessibility: PermissionRow`, `screenRecording: PermissionRow` (each `.allowed` or `.action(label:)`, plus optional `detail` and `secondaryAction`), `loginItem: LoginItemRow`.

Helpers:

```
@ VoiceDisplay.name(for id: String) -> String
do:
  1. parse the text after the first "_" (whole id when there is none)
  2. compute a capitalized first letter
br: empty result -> return id unchanged
```

```
@ ShortcutKeycaps.labels(description: String) -> [String]
ctx: description is KeyboardShortcuts.Shortcut.description, for example "⌥P" or "⌃⌥F5"
do:
  1. parse leading modifier glyphs (⌃ ⌥ ⇧ ⌘), one keycap each
  2. write the remainder as one keycap
br: empty description -> []
```

`ReadingPreferences.label(for speed: Float) -> String` returns two decimals and a multiplication sign: "1.00×".

## Tasks

1. Write failing tests first (`.rpi/rules/testing.md`): `PanelModelTests`, `VoiceDisplayTests`, `ShortcutKeycapsTests`, and label cases in `ReadingPreferencesTests`. The test names in the main plan's stuck-state table are required.
2. Implement the types until the tests pass.
3. Move `statusText` and `repairLabel` to `CaptaloCore` with tests for all six `VoiceInstallState` cases. Keep the app extension compiling by forwarding to the moved methods.
4. Independent review, repair, simplify, `make verify`.

## Acceptance

Automated:

- `make verify` passes 15 of 15.
- Required tests exist and pass in debug and release: `accessibilityMissingOpensSetup`, `voiceStatesShowRepair`, `checkingVoiceIsPendingNotMissing`, `readShortcutNoticeVariants`, `screenRecordingRequestedOffersReopen`, `noticesSurfaceOnRead`, `loginItemRowCarriesTextAndAction`, plus pill tests for every row of the pill table and `optionalItemsNeverRaiseADot`.

Manual: none.

## Units

One unit; one owner. Files: `Packages/CaptaloCore/Sources/CaptaloCore/Panel/*`, `Packages/CaptaloCore/Sources/CaptaloCore/Reading/VoiceInstallState.swift`, `Packages/CaptaloCore/Sources/CaptaloCore/Shell/ReadingPreferences.swift`, their tests, and `Captalo/App/CaptaloAppStateVoice.swift` (forwarding only).
