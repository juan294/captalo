# Plan: monochrome popover

- Date: 2026-11-20.
- Workflow: `rpi-plan`. Planning only; no product code, dependency, signing or remote state was changed while writing it.
- Repository: `juan294/captalo`, branch `develop` at `f0eec26`, worktree `/Users/juan/code/captalo`, clean before this plan was written.
- Phase files: [phase 1](2026-11-20-monochrome-popover-phases/phase-1.md), [phase 2](2026-11-20-monochrome-popover-phases/phase-2.md), [phase 3](2026-11-20-monochrome-popover-phases/phase-3.md).
- Mockup sources: [mockup directory](2026-11-20-monochrome-popover-mockup/) (six `.dc.html` artboards). The rendered canvas is the owner's private artifact `https://claude.ai/artifact/SQjDh6RMVnhmp9GXxAWUpH`.

## Objective

Replace the grouped system form in the menu-bar panel with the approved monochrome design: a left icon rail (Read, Voice, Setup, Quit), one focused pane per section, a status pill, and a privacy footer. Every setting, notice and recovery action of the current panel stays reachable. No reading, capture, speech or OCR behavior changes.

## Controlling inputs

- `AGENTS.md`, [briefing](../briefing.md), [core reader plan](2026-11-15-captalo-core-reader.md) (owner decisions 8 and 12) and its [notes](2026-11-15-captalo-core-reader-notes.md) (D22, D30, D34, D36, D37), `.rpi/policy.json`, `.rpi/rules/testing.md`.
- Project overlay: `.rpi/project/rpi-plan.md` does not exist. No overlay or declared override applies.
- Source read for this plan: `Captalo/UI/Settings/SettingsView.swift`, `Captalo/UI/Settings/StatusItemController.swift`, `Captalo/App/CaptaloAppState*.swift`, `Captalo/App/CaptaloApplicationDelegate.swift`, `Packages/CaptaloCore/Sources/CaptaloCore/Shell/*.swift`, `Scripts/shell-audit`, `.github/workflows/ci.yml`, and `RecorderCocoa.swift`, `Shortcut.swift` and `Recorder.swift` of the pinned KeyboardShortcuts 3.1.0.

## Decisions in force

Owner decisions of 2026-11-20 (this plan):

| # | Decision | Detail |
|---|---|---|
| P1 | Layout | The four dark artboards (`Main`, `Voice`, `Setup`, `SetupAttention`): rail, pane, pill, footer. Panel content is 440 × 520 pt. |
| P2 | Colour | Monochrome: white, greys, and green only for positive state ("Ready", "Installed", "All set", "Allowed", the voice in use, a switch that is on). No amber or orange in the panel. |
| P3 | Shortcut control | Keycaps show the shortcut. A click swaps the library's `RecorderCocoa` into the same slot while it records. The library's conflict alerts stay the only conflict path. If the phase 2 entry probe fails, work stops for an owner decision. |
| P4 | Container | The panel stays an `NSPopover` (D36). The arrow stays. The owner checks the arrow's shade on the first signed install. |
| P5 | Appearance | The panel follows the macOS light and dark appearance. The dark palette is the approved mockup; the light palette is in `MainLight` and `SetupAttentionLight`. |
| P6 | Render command | A DEBUG-only launch argument writes PNGs of every panel state in both appearances to `.local/`. It joins `make verify` as a local check. Hosted CI is not changed. |

Planner choices inside those decisions (routine; recorded for review):

- Voice names shown to the user are derived from the voice ID: the part after the first underscore, capitalized (`af_heart` gives "Heart"). The ID stays visible in small monospaced type.
- The missing-permission state uses no warning colour (the owner did not ask for one). The orange text of the current region and voice notices (`SettingsView.swift:70`, `:76`) becomes primary text with a small warning glyph.
- The Voice row on the Read pane and the rail both switch tabs; this is one navigation action (set the selected tab), reached from two controls.
- The app icon (`Captalo/Logo.icon`) keeps its gradient (D37). Out of scope.

Earlier decisions that still bind: all settings stay in the panel and the panel opens when setup is missing (decision 12, D36); Screen Recording and the region shortcut stay optional (decision 8); `PrivacyLog` is the only logging API; no new fallback layers.

## Palette (checkable against the mockup sources)

| Token | Dark | Light | Used for |
|---|---|---|---|
| `ground` | `#17171A` | `#FFFFFF` | Pane background |
| `rail` | `#111113` | `#F4F4F5` | Rail background |
| `hairline` | `#26262B` | `#E4E4E7` | Rail edge, footer rule |
| `card` | `#202024` | `#F7F7F8` | Cards, segmented track |
| `cardBorder` | `#2C2C31` | `#E4E4E7` | Card and track border, row divider |
| `textPrimary` | `#F2F1EE` | `#17171A` | Titles, values |
| `textSecondary` | `#A6A6AE` | `#5C5C66` | Captions, inactive rail items, footer |
| `segmentText` | `#C9C9CF` | `#3A3A40` | Unselected speed steps |
| `control` | `#2B2B31` | `#E9E9EC` | Icon tiles, neutral pill; active rail item uses `#2B2B31` / `#E4E4E7` |
| `keycap` | `#2B2B31` | `#FFFFFF` | Keycaps, secondary buttons |
| `controlBorder` | `#3C3C43` | `#D4D4D9` | Keycap and secondary button border; switch-off track uses `#3C3C43` / `#C9C9CF` |
| `inverseFill` / `inverseText` | `#F2F1EE` / `#17171A` | `#17171A` / `#FFFFFF` | Selected speed, primary button, play button of the voice in use |
| `positive` | `#4CD08A` | `#1F9D57` | Status dot, switch-on track |
| `positiveText` | `#6BDDA0` | `#157A45` | "Ready", "Allowed", "In use" |
| `positiveTint` | `#4CD08A` at 12% | `#1F9D57` at 12% | Positive pill background |
| `positiveBorder` | `#6BDDA0` at 55% | `#1F9D57` at 55% | Border of the voice in use |
| `attentionBorder` | `#8E8E96` | `#6B6B73` | Outline of the card that needs action |

Geometry (from the artboards): rail 72 pt; rail item 56 pt wide, radius 10; pane padding 20; section gap 16; card radius 12; keycap 28 pt, radius 7; speed track 44 pt high; footer 44 pt; title 19 pt semibold; body 14 pt semibold with 12 pt captions.

## Design

The view layer splits into a pure model, pure views and one live adapter, so the render command and the tests see the same states as the user.

```
CaptaloCore/Panel (pure, tested)          Captalo/UI/Panel (SwiftUI)                Captalo/App
PanelModel.make(PanelInput) -> PanelModel  PanelRootView(model, actions)             CaptaloAppState.panelInput
PanelTab, PanelPill, VoiceDisplay,         RailView, ReadPane, VoicePane, SetupPane   CaptaloAppState.panelActions
ShortcutKeycaps, ReadingPreferences label  PanelTheme (palette by colorScheme)        StatusItemController hosts LivePanelView
                                           KeycapRecorder (keycaps + RecorderCocoa)   PanelRenderCommand (DEBUG)
```

- `PanelModel` decides every piece of text and state the panes show: the pill of each tab, the rail attention dot, the tab to open on, the notices and their actions. The views only draw it. Phase 1 fixes this contract with tests.
- The live panel builds `PanelInput` from `CaptaloAppState` on every state change. The render command builds `PanelInput` from fixtures. Both pass through the same `PanelModel.make` and the same views.
- `PanelActions` is a struct of closures (set speed, set voice, play sample, open settings, quit, and so on) that the live adapter binds to the existing `CaptaloAppState` methods. No state method changes its behavior.
- Each open of the panel selects `model.initialTab`: the tab that holds the first required missing item, else Read.

Where every current element goes:

| Current element | New place |
|---|---|
| Read selection recorder (`SettingsView.swift:13`) | Read pane, first card, `KeycapRecorder` |
| Shortcut notice, three variants (`CaptaloAppStateSettings.swift:43`) | Read pane, caption under the shortcut cards (always shown, as today) |
| Speed slider (`SettingsView.swift:21`) | Read pane, six-step segmented control |
| Voice picker and sample buttons (`SettingsView.swift:96`, `:103`) | Voice pane, one card per voice: play button, name, "Use" or "In use" |
| Voice states other than ready (`CaptaloAppStateVoice.swift:60`, `:68`) | Voice pane: status text and the repair button; pill "Preparing" or "Needs attention" |
| Accessibility row (`SettingsView.swift:30`) | Setup pane, Permissions |
| Launch at login, its text and "Open Login Items" (`SettingsView.swift:46`) | Setup pane, General |
| Read region recorder (`SettingsView.swift:54`) | Read pane, second card, `KeycapRecorder` |
| Screen Recording row, "Quit and reopen" (`SettingsView.swift:65`) | Setup pane, Permissions |
| Region failure notice (`SettingsView.swift:70`) | Read pane, under the Read region card |
| Last voice error (`SettingsView.swift:76`) | Read pane, notice above the cards |
| Quit | Rail, bottom |
| (new) | Footer: "Speech and OCR run on this Mac" |

## Phases

| Phase | Result | Gate |
|---|---|---|
| 1. Panel model | `CaptaloCore` decides all panel state and text, with tests | `make verify` |
| 2. Panel views and render command | The new views exist beside the old panel and render to PNG in both appearances | `make verify` including the new `panel-render` check; reviewer compares PNGs with the mockup |
| 3. Wire-in | The popover hosts the new panel; `SettingsView` is deleted; owner checks on a signed install | `make verify`; owner checks |

Phases run and are accepted in order. Phase 2 has `[batch-eligible]` units (see its file). Working branches stay local; the integration owner merges into `develop` locally. No push, release or CI change is part of this plan.

## Success criteria

Automated (all through `make verify`, sequential):

- `PanelModelTests`, `VoiceDisplayTests`, `ShortcutKeycapsTests` and the added `ReadingPreferencesTests` cases pass in debug and release.
- `panel-render` writes exactly the expected PNG set (every fixture in dark and light) at 880 × 1040 px, exits 0, and fails when a file is missing or has another size.
- `shell-audit` still passes: `NSPopover`, `NSStatusItem` and `NSStatusBar` appear only in `StatusItemController.swift`.
- The 15 existing checks stay green.

Manual:

- Phase 2 (reviewer or integration owner): each PNG matches its artboard in layout and palette; the fixture with every notice shows all text without clipping.
- Phase 3 (owner, signed install by the integration owner): the list in [phase 3](2026-11-20-monochrome-popover-phases/phase-3.md), which repeats the D36 checks and adds the appearance switch, the keycap recorder, and the popover arrow.

## Stuck states and recovery

No new blocking state is added except the recorder slot (row 9). Rows 1 to 8 are existing states that the redesign must keep visible.

| # | State | Who sees what | How it ends | Proof |
|---|---|---|---|---|
| 1 | Accessibility not granted | The panel opens on Setup; the Accessibility card has the attention outline and the "Open Accessibility Settings" button; pill "1 step left"; dot on the Setup rail item | The user grants it; the next open refreshes the row (`StatusItemController.swift:62`) | `PanelModelTests.accessibilityMissingOpensSetup`; fixture `setup-permission-missing` |
| 2 | Voice damaged, failed, install failed, or bundle invalid | The panel opens on Voice; status text and "Reinstall voice" or "Retry" (none for an invalid bundle, whose text says to reinstall Cáptalo); dot on Voice | The repair button; or reinstalling the app | `PanelModelTests.voiceStatesShowRepair` (one case per state); fixture `voice-damaged` |
| 3 | Voice still preparing | Voice pane shows a progress indicator and "Preparing local voice..."; pill "Preparing" | Automatic when preparation ends | `PanelModelTests.checkingVoiceIsPendingNotMissing` |
| 4 | Read shortcut not set, or rejected as a duplicate | The panel opens on Read; the caption gives the instruction or the rejection text; the keycap slot shows "Record" | The user records a shortcut | `PanelModelTests.readShortcutNoticeVariants`; fixture `read-shortcut-unset` |
| 5 | Shortcut set but taken by another app (the library reports nothing, D34) | The caption "If this shortcut does nothing, another app may use it; choose another." is always shown | The user records another shortcut | `PanelModelTests.readShortcutNoticeVariants` |
| 6 | Screen Recording missing or just requested | Setup pane: "Allow" button; after a request, the reopen text and "Quit and reopen" | The user allows it, then reopens | `PanelModelTests.screenRecordingRequestedOffersReopen` |
| 7 | Region failure notice, or last reading stopped with a voice error | The panel opens on Read; the notice text is shown in full | The next successful reading clears it (existing behavior) | `PanelModelTests.noticesSurfaceOnRead`; fixture `read-all-notices` |
| 8 | Launch at login needs approval, is unavailable, or failed to register | Setup pane: the row's text and "Open Login Items" | The user follows the text | `PanelModelTests.loginItemRowCarriesTextAndAction` |
| 9 | (new) The keycap slot is in recording mode and the user clicks away, presses Esc, or closes the panel | The slot returns to keycaps with the stored shortcut | Automatic: the slot follows the recorder's first-responder state, and a closed panel resets it | Phase 2 entry probe steps 3 and 4; owner check in phase 3 |
| 10 | (new) Notices are longer than the 520 pt pane | The pane scrolls; nothing is cut off | Automatic | Fixture `read-all-notices` (manual comparison); the pane content is a scroll view |
| 11 | (new) The render command cannot render | `make panel-render` exits non-zero with the missing file names | The developer reads the message | `Scripts/tests` case for a missing or wrong-size PNG |
| 12 | Menu-bar icon hidden by a full menu bar (D36 residual) | Unchanged: the panel does not open | Unchanged; out of scope | None added |

## Consumer sweep

No shared function, type, cache or fixture changes what it returns or stores. One file is deleted and two constants change value. Commands run on `f0eec26`:

- `grep -rn "SettingsView\|StatusItemController" Captalo Scripts Makefile docs/release docs/briefing.md`: `SettingsView` is used only by `StatusItemController.swift:26` (covered, phase 3). `StatusItemController` is used by `CaptaloApplicationDelegate.swift:7`, `:11`, `:12`, `:28` (unchanged API) and named in `Scripts/shell-audit:4`, `:30` (unchanged; the file keeps its name).
- `StatusItemController.width` and `.height` (`StatusItemController.swift:10`, `:13`) are read only by `SettingsView.swift:86` (covered, phase 3).
- `ReadingPreferences.speedIndex(of:)` is called by `SettingsView.swift` and by `ReadingPreferences.snap` (kept; the new control calls `setSpeed` with a step value).
- `shortcutNotice`, `regionFailureNotice`, `repairLabel`, `statusText`, `loginItem`: read only by `SettingsView.swift` today. Phase 3 moves each read into `panelInput`; the properties stay.
- `AGENTS.md:48` states "13 of the 15 `make verify` checks". Phase 2 changes it to 16 in the same commit that adds the check. `.github/workflows/ci.yml` is not touched (Sutura owns it).

## Risks

- **Recorder swap (P3).** `RecorderCocoa` is a final `NSSearchField` subclass and its active-state notification is internal. The swap relies on `window.makeFirstResponder` and on observing the window's first responder. The phase 2 entry probe decides; failure stops the phase.
- **Popover arrow shade (P4).** The arrow is drawn by the system material, not by the panel. INFERRED: in dark appearance it is close to `ground` but not identical. Owner check in phase 3.
- **Render fidelity.** The render command draws SwiftUI views offscreen; the live recorder field is an AppKit view and is rendered only in its keycap state. The recording state is checked by the probe and by the owner.
- **Probe and defaults.** The entry probe writes and removes one key, `KeyboardShortcuts_captaloPanelProbe`, in the app's defaults domain. It touches no other key.

## Handoff

- Objective and scope: this file. Accepted decisions: P1 to P6. No continuation across phases is authorized; each phase stops for acceptance.
- Base: `develop` at `f0eec26`. This plan, its phase files and the mockup directory are uncommitted in `/Users/juan/code/captalo`.
- Evidence limits: the mockup was never rendered by the planner; the artboards and the palette table are the specification. No Swift was compiled for this plan. Claims about KeyboardShortcuts come from reading the 3.1.0 source in `.local/build/DerivedData/SourcePackages/checkouts/KeyboardShortcuts`.
- Next: `rpi-implement` phase 1 in a worktree from `develop`. Entry condition: this plan accepted by the owner, including the light palette (artboards 5 and 6).
- No local task service or database is allocated by any phase. The render command writes only under `.local/build/panel-render/`.
