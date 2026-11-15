# Phase 4: Shell

Parent: [Cáptalo core reader plan](../2026-11-15-captalo-core-reader.md).

## Goal

Cáptalo runs as an invisible background agent: no Dock icon, no menu-bar item, no popover. One small settings window appears only when the app is opened again or when required setup is missing. The shortcuts are the user's own.

## Entry conditions

- Phase 3 accepted.
- Adding KeyboardShortcuts (`https://github.com/sindresorhus/KeyboardShortcuts`, latest release at entry; 3.1.0 on 2026-11-15) pinned by exact revision is approved.
- **Entry probe (review R11):** read the pinned KeyboardShortcuts source and record whether it reports registration failure (for example the result of its Carbon `RegisterEventHotKey` call) to the caller. The stuck-state disclosure in the main plan depends on this answer.

## Design

```
@ SetupState.evaluate(env) -> SetupState
ctx: pure; env = {voice: VoiceInstallState, axTrusted, readShortcutSet, readShortcutActive?, screenRecording?, regionShortcutSet?, lastReadingError}
do:
  1. required items in order: voice, accessibility, read shortcut
  2. optional items (owner decision 8): screen recording, region shortcut; never make state .needsSetup
  3. return .ready(optionalMissing) or .needsSetup(requiredMissing)
br: .needsSetup -> settings window on launch, on a failed press, on reopen
br: .ready -> launch silent; window only on reopen
```

- `INFOPLIST_KEY_LSUIElement = YES`. Remove `setActivationPolicy(.regular)` (`Sotto/App/SottoApplicationDelegate.swift:14`) and `MenuBarExtra` (`Sotto/App/SottoApp.swift:13`). The app delegate owns one settings `NSWindow`.
- `applicationShouldHandleReopen` shows the settings window (assessment §7).
- Settings window contents: "Read selection" recorder; voice picker with sample; speed; launch at login; required permission rows; an optional section (Screen Recording and the region recorder, added in phase 5); last voice error; Quit.
- Shortcuts: `Name.readSelection` with no default. A custom validation rejects a binding identical to the other Cáptalo shortcut. The recorder's built-in checks cover system shortcuts and the app's own menu only (KeyboardShortcuts 3.1.0 `RecorderCocoa.swift`, review R11). The UI text does not promise more.
- Launch at login: `SMAppService.mainApp`. The row reflects `.enabled`, `.notRegistered`, `.requiresApproval` (with a button for `SMAppService.openSystemSettingsLoginItems()`) and `.notFound`, plus any register error shown as text.
- Delete: Studio window and views, pronunciation code, Stats code and timers, `WaveStatusIconAnimator`, `SottoMenuBarView`, popover status strings, and `pauseForVoiceApps` with its observer (`Sotto/App/SottoApplicationDelegate.swift:147-167`).
- Persist speed and voice in `UserDefaults` (baseline §6). The defaults store is injected, and tests use `UserDefaults(suiteName:)` with a unique name that is removed afterwards.
- Swift 6 language mode for the app target.

## Tasks

1. Entry probe (above). Record the result in this phase's evidence.
2. TDD `SetupState`, `ShortcutValidation` and `LoginItemState` mapping in `CaptaloCore`.
3. Delete the old UI and its state in one delete-only commit, checked by building.
4. Add the settings window, KeyboardShortcuts and launch at login.
5. Rerun the phase 2 probe matrix for the six mandatory apps plus Visual Studio Code (the no-selection case), because the shell and the Swift 6 migration touched the capture path's callers. Rerun `make offline-test`.

## Success criteria

### Automated (`make verify`)

- [x] `SetupStateTests`: `missingReadShortcutRequiresSetup`, `untrustedRequiresAccessibility`, `damagedVoiceListedFirst`, `allRequiredPresentIsReady`, `missingScreenRecordingDoesNotRequireSetup`, `lastVoiceErrorShownButDoesNotBlockReady`.
- [x] `ShortcutValidationTests.identicalBindingsRejected`.
- [x] `LoginItemStateTests`: each `SMAppService.Status` value maps to its row text and action. A register error maps to a visible message.
- [x] Code search finds no `MenuBarExtra`, `setActivationPolicy(.regular)`, `RegisterEventHotKey` (in Cáptalo code), `pronunciationRules`, `wordsSpoken`, `pauseForVoiceApps` or `Studio` in `Captalo/`.
- [ ] (Built Debug and Release products print `true`, checked by `make shell-audit`; installed app pending signing, D1) `PlistBuddy -c "Print :LSUIElement"` on the installed app prints `true`.
- [x] The Release build passes in Swift 6 mode with no new warning suppressions.

### Manual

- [ ] Fresh-state check on the fixed identity (review R7), with `make defaults-backup` and `make defaults-restore`:
  1. Quit Cáptalo through the install record. Confirm that no process with the app's executable path runs.
  2. `defaults-backup` records whether the `com.thecreativetoken.captalo` domain exists. If it exists, it exports it to a backup file in `.local/shell/` named with the UTC time, flushes the file to disk and verifies it by re-reading it. Only then does it delete the domain.
  3. Launch: the settings window opens. Record a shortcut and close the window: later launches show nothing.
  4. Quit again. `defaults-restore` restores the latest backup (or deletes the domain if it was absent before), then compares the restored values with the backup.
  5. Keep the backup until that comparison passes. `defaults-restore` is idempotent, so an interrupted check is finished by running it again.

  Only this domain is touched.
- [ ] While running, nothing appears in the Dock, the menu bar or Cmd+Tab.
- [ ] Opening Cáptalo from Spotlight shows the settings window. Quit exits the process.
- [ ] Stop gesture: a press with a new selection reads it. Pressing again with the same text, or with nothing selected, stops. A press while idle with nothing selected is silent.
- [ ] The source app keeps focus and key status throughout. The settings window never steals focus during a reading.
- [ ] Launch at login: toggle on, log out and in, and the app is running. If approval is required, the row shows the approval step and its button works.
- [ ] Shortcut registration failure or conflict: the row shows the text that matches the entry-probe result.
- [ ] The phase 2 matrix rerun results match phase 2 (any regression blocks acceptance).

## Handoff to phase 5

The KeyboardShortcuts revision and entry-probe result, the defaults keys, the matrix rerun file, and confirmation that the defaults backup was restored.
