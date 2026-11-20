# Phase 2: Panel views and render command

Parent: [monochrome popover plan](../2026-11-20-monochrome-popover.md).

## Goal

The new panel exists as SwiftUI views in `Captalo/UI/Panel/`, drawn from `PanelModel`, and renders to PNG in dark and light. The popover still hosts the old `SettingsView`; nothing the user sees changes yet.

## Entry conditions

- Phase 1 accepted.
- **Entry probe (decision P3), run before any other task.** Build the minimal `KeycapRecorder` and the DEBUG launch argument `--panel-recorder-probe`. The probe opens one window, uses the probe-only shortcut name `captaloPanelProbe`, and exits 0 only when all four steps hold:
  1. A click on the keycap slot makes the embedded `RecorderCocoa` the window's first responder.
  2. A synthetic key-down of ⌃⌥⇧F19 sent through `NSApp.sendEvent` stores the shortcut, calls `onChange`, and the slot shows keycaps again.
  3. After a second click, a synthetic Esc returns the slot to keycaps with the stored shortcut unchanged.
  4. After a third click, `window.makeFirstResponder(nil)` returns the slot to keycaps.
  The probe then removes the defaults key `KeyboardShortcuts_captaloPanelProbe` and asserts it is gone. Record the output in this phase's evidence. If any step fails, stop and report to the owner with the failing step; do not build another recorder.
- The probe mode starts before `prepareVoice()` in `CaptaloApplicationDelegate.swift`, so it never claims the voice store and never exits as a second instance.

## Design

```
@ KeycapRecorder(name, keycaps, onChange) : NSViewRepresentable host + SwiftUI keycaps
ctx: KeyboardShortcuts.RecorderCocoa (3.1.0), window first responder (KVO)
pre: mounted in a key-capable window
do:
  1. write keycaps (or "Record" when empty) as a button
  2. on click: write recording = true, then makeFirstResponder(recorder)
  3. on recorder onChange: emit onChange(shortcut), write recording = false
  4. on first responder leaving the recorder: write recording = false
br: makeFirstResponder returns false -> recording stays false (keycaps stay)
fx: KeyboardShortcuts stores the shortcut (library path, unchanged)
risk: the library's alert for a conflicting shortcut is a sheet on the panel window (D36)
```

The `RecorderCocoa` instance stays in the view tree at all times (zero opacity when idle), so focus never depends on mounting order.

```
@ PanelRenderCommand.run(outputDirectory) -> exit code
ctx: DEBUG only; launch argument --render-panel <dir>; NSHostingView, bitmap rep; no voice, no shortcuts registered
pre: <dir> is under .local/build/panel-render
do:
  1. lookup fixtures (name -> PanelInput, selected tab)
  2. compute PanelModel.make(input) per fixture
  3. write <name>-dark.png and <name>-light.png at 2x (880 x 1040 px)
  4. emit one line per file; validate the count
fail: a render or write error -> message naming the fixture, exit 1
```

Fixtures (each rendered dark and light, 16 files):

| Fixture | Tab | Matches |
|---|---|---|
| `read-ready` | Read | `Main.dc.html`, `MainLight.dc.html` |
| `voice-ready` | Voice | `Voice.dc.html` |
| `setup-all-set` | Setup | `Setup.dc.html` |
| `setup-permission-missing` | Setup | `SetupAttention.dc.html`, `SetupAttentionLight.dc.html` |
| `read-shortcut-unset` | Read | stuck state 4 |
| `read-all-notices` | Read | stuck states 7 and 10 (voice error, longest region notice, duplicate rejection) |
| `voice-damaged` | Voice | stuck state 2 |
| `setup-recording-requested` | Setup | stuck states 6 and 8 (reopen text, login item needs approval) |

Other rules:

- `PanelTheme` holds the palette table of the main plan, selected by `@Environment(\.colorScheme)`. Views take colours only from `PanelTheme`; no literal colour in a pane file.
- `PanelRootView(model:actions:selectedTab:)` is 440 × 520 pt. The pane body is a `ScrollView` (stuck state 10); the rail and footer do not scroll.
- Icons are SF Symbols close to the artboard glyphs: `speaker.wave.2` (Read), `waveform` (Voice), `slider.horizontal.3` (Setup), `power` (Quit), `text.cursor` and `viewfinder` (shortcut cards), `lock` (footer), `play.fill`, `checkmark`. The rail logo is the existing `MenuBarGlyph` template image at 26 pt.
- Every control is a real `Button` or `Toggle` with an accessibility label; the keycap button's label is "Change the Read selection shortcut" (or region) plus the spoken shortcut.
- `Makefile`: `panel-render` builds the unsigned Debug app, runs the command into `.local/build/panel-render/`, and calls `Scripts/panel-render-check` (file names, count, pixel size via `sips -g pixelWidth -g pixelHeight`). `.rpi/policy.json` gains the check `panel-render` after `app-build-release`. `AGENTS.md:48` changes "13 of the 15" to "13 of the 16" and lists `panel-render` as local. `.github/workflows/ci.yml` is not changed.
- `Scripts/shell-audit` is not changed. The new files use none of its forbidden names.

## Tasks and units

1. Entry probe and minimal `KeycapRecorder` (one owner; blocks everything else).
2. Unit 2A, shell (one owner, first): `PanelTheme.swift`, `PanelRootView.swift`, `RailView.swift`, shared components (`PanelCard`, `StatusPill`, `Keycap`, `PanelButtonStyles`), `PanelActions.swift`.
3. After 2A is merged locally, three units with no file overlap:
   - Unit 2B `[batch-eligible]`: `ReadPane.swift`, `SpeedControl.swift`, final `KeycapRecorder.swift`.
   - Unit 2C `[batch-eligible]`: `VoicePane.swift`.
   - Unit 2D `[batch-eligible]`: `SetupPane.swift`, `PanelSwitch.swift`.
4. Unit 2E (one owner, after 2B to 2D): `PanelRenderCommand.swift`, `PanelFixtures.swift`, `Scripts/panel-render-check` with tests in `Scripts/tests/`, Makefile target, policy entry, `AGENTS.md` line.
5. Independent review against the artboards and the palette table, repair, simplify, `make verify`.

At most three implementers at once. One integration owner merges units locally; no working branch is pushed.

## Acceptance

Automated:

- `make verify` passes 16 of 16, including `panel-render`.
- `Scripts/tests` proves `panel-render-check` fails for a missing file and for a wrong pixel size.
- The entry probe output (four steps passed, key removed) is recorded.

Manual (reviewer or integration owner; the PNGs are viewed, not only counted):

- `read-ready`, `voice-ready`, `setup-all-set` and `setup-permission-missing` match their artboards in layout, spacing and palette, in both appearances.
- `read-all-notices` shows every notice in full.
- No amber or orange appears in any PNG.
