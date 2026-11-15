# Notes: Cáptalo core reader implementation

Plan: `2026-11-15-captalo-core-reader.md` (revision 4, accepted 2026-11-15). Implementation session of 2026-11-15, `/rpi-implement` with the owner instruction "all phases, no stopping, when you're done merge to develop and prune the tree(s)".

- Worktree: `/Users/juan/code/captalo-core-reader`, branch `feat/core-reader`, created from `develop` at `5788d4c`.
- Overlay: `.rpi/project/rpi-implement.md` does not exist. No overlay or declared override applies.
- Authority: local commits and a local merge into `develop` only. No push, PR, release, signing-account change or publication.

## Deviations

### D1. Signing identity not created (phase 1, task 6)

- Plan said: `make signing-setup` runs the first automatic-signing build with `-allowProvisioningUpdates`, which creates the Apple Development certificate for the Personal Team; then `make install` and first launch.
- Found: `security find-identity -v -p codesigning` reports 0 valid identities. No local provisioning profile or Xcode preference names the Personal Team ID (the only profiles on disk are expired 2016 profiles of another organization). The session's permission classifier denied the `xcodebuild -allowProvisioningUpdates` call as an account-changing action.
- Chose: implement `make signing-setup` (accepts `TEAM=<id>`), `Scripts/signing-identity` and `Scripts/install` completely, test them with captured output and temporary directories, leave `DEVELOPMENT_TEAM` empty, and do not install or launch.
- Why: creating a certificate in the owner's Apple account is an account change that needs the owner's explicit go-ahead in this session. Everything that depends on the fixed signed install (task 6, the manual criteria, permission survival in phases 2 and 5, the matrix, listening) stays pending until the owner runs `make signing-setup TEAM=<Personal Team ID>` or authorizes it.

### D2. Build-info inputs come from `make` (phase 1, task 4)

- Plan said: a Run Script phase writes `build-info.json` (commit, dirty flag, configuration, UTC time) into Resources before signing.
- Found: the target enables `ENABLE_USER_SCRIPT_SANDBOXING`, and a sandboxed script cannot read the Git directory (a worktree's `.git` also points outside the source root).
- Chose: `make` passes `CAPTALO_COMMIT` and `CAPTALO_DIRTY` as build settings; `Scripts/write-build-info` declares its script input and output and stays sandboxed. A plain `xcodebuild` call outside `make` records `"commit": "unknown"`. The install record takes commit and dirty flag from the installed bundle's `build-info.json` only.
- Why: one source for the installed commit, with script sandboxing kept on (the first candidate turned sandboxing off; the simplify pass replaced that).

### D2a. `make install` reuses `make build` (phase 1, task 4)

- Plan said: `make install` resolves the identity, builds signed, stages, verifies and replaces.
- Chose: `make install` runs `signing-check` (`Scripts/signing-identity`), then the same `build` recipe as `make build CONFIG=…`, then `Scripts/install --app <built app>` for staging, verification, replacement and the record. Install state (record, staging, rollback copy, install logs) lives in the main checkout's `.local/build/`, found through the Git common directory, so every worktree sees one record.
- Why: one build definition (simplify review), and one install record for the one fixed path (phase 1 review, finding 6).

### D3. RPI installation update to v2.2.0 (verification step 2)

- Plan said: step 2 is `rpi-distribution.py check`.
- Found: the check failed on `develop` before any change, because the local cc-rpi source moved to v2.2.0 (`4325825`) while the installation recorded v2.1.0.
- Chose: a reviewed update plan whose only operations were `.rpi/distribution.json`, `.rpi/manifest.json` and one new baseline, applied as its own commit (`7f7737a`).
- Why: the gate must pass, and the update changes no skill, rule or instruction body.

### D4. Removed tracked upstream `xcuserdata` (phase 1, task 1)

- Found: `Sotto.xcodeproj/xcuserdata/shreysid.xcuserdatad/…/xcschememanagement.plist` was tracked although `.gitignore` excludes `xcuserdata/`.
- Chose: delete it in the rename commit. Added `__pycache__/` to `.gitignore` for the script tests.

### D5. Pasteboard calls stay on the main actor (phase 2 design)

- Plan said: the clipboard transaction runs off the main thread where the pasteboard API permits, checked against Apple documentation.
- Found: the NSPasteboard, `changeCount` and `NSPasteboardItem.data(forType:)` pages (sosumi.ai mirror, read 2026-11-15) say nothing about threads, and nothing about promised-data blocking or failure.
- Chose: the transaction's pasteboard calls run on the main actor; waits are non-blocking `Task.sleep` polls.
- Why: without documented permission, the conservative reading is main-thread use. A synchronous promised-data provider can still block the main thread during the snapshot; the elapsed-time check after materialization aborts such snapshots before Copy, and the matrix records provider time.

### D6. Plan verification step 3 needs `DEVELOPER_DIR`

- Plan said: `swift test --package-path Packages/CaptaloCore`.
- Found: the machine's developer directory is Command Line Tools, whose SwiftPM cannot resolve `.macOS(.v26)`.
- Chose: the Makefile exports `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (overridable); policy steps call `make test-core-debug` and `make test-core-release`.

### D7. A failed clipboard restore leaves the clipboard empty (phase 2)

- Plan said: stuck-state row "Clipboard restore fails: the clipboard holds the source app's copied text".
- Found: NSPasteboard requires `clearContents()` before `writeObjects`, so when the restore write fails the clipboard is already empty (phase 2 review, finding 6).
- Chose: keep one restore path (clear, then write) and correct the plan's stuck-state row; `restoreFailureDoesNotSpeak` now models the clear and asserts the empty clipboard.
- Why: there is no API that replaces pasteboard contents atomically. This case is silent and logged (`PrivacyLog.restoreFailed`); it stays within the accepted clipboard limitation (decision 9).

### D8. Chromium retry re-queries the focused element (phase 2)

- Plan said: set `AXManualAccessibility` once per app launch, retry step 1.
- Chose: after the write, re-query the focused element up to 5 times, 40 ms apart (200 ms bound), and probe it each time.
- Why: Chromium builds its tree asynchronously; the element captured before the write may not expose the selection (phase 2 review, finding 4, inferred). The once-per-PID rule is unchanged.

## Phase 1 handoff (2026-11-15)

- Candidate: branch `feat/core-reader`, commits `a000427` (rename), `7f7737a` (cc-rpi v2.2.0), `6eb0b4a` (foundation), `556c148` (review repairs) and the simplify commit that carries this note. `make verify` (8 checks: whitespace, rpi-installation, core tests debug and release, unsigned Debug and Release builds, log-audit, script-test) passed on the simplify candidate; evidence in the worktree's ignored `.rpi/local/verification.json`.
- Tests: 13 CaptaloCore tests (chunker characterization, PrivacyLog), 18 script tests.
- Mutation checks (run once, 2026-11-15): first-chunk minimum 45 to 40 fails `firstChunkTargets45To110Characters`; first-chunk hard length 110 to 150, later minimum 80 to 90, and disabling the 240 word split each fail the chunker suite.
- Independent review: one fresh-context reviewer. Findings and dispositions: (1) blocker, `.SHELLFLAGS` ignored by GNU Make 3.81: fixed, with a script test that runs a failing `xcodebuild` stub; (2) weak characterization tests: fixed, mutations above; (3) install error handling and logs: fixed; (4) bundle-ID check before quit, relaunch after rollback: fixed; (5) `signing-setup` without a team: fixed, it now explains how to set the team; (6) per-checkout install record: fixed (main checkout state); (7) record the real signing authority: fixed (`codesign -dv` Authority); (8) log-audit patterns: fixed; (9) exhaustive PrivacyLog test: fixed; (10) leftover Sotto names in notices and the release playbook: fixed; `docs/index.html` (upstream marketing page) left for the owner; (11) `DEVELOPER_DIR` for step 3: recorded as D6.
- Simplify pass (four reviewers: reuse, simplification, efficiency, altitude). Applied: one `xcb` Makefile macro; install reuses `make build` (removes the duplicate build and shell quoting); build-info via build settings with sandboxing on; one commit source in the record; removed the unused install-path override and log-audit exception list; shared helpers (`info_plist`, `codesign_field`, `write_json`, `poll_until`); `Duration` division for milliseconds; test helpers. Skipped: the team plumbing (the owner must still supply the team once); the second deep `codesign --verify` after the move (the phase spec requires both); lazy `PrivacyLog` rendering (one allocation per event); `git status --untracked-files=no` (untracked files are part of the dirty flag).
- Not done, blocked by D1: task 6 (signed install, first launch, the after-launch shared-cache record), the real-path install replacement check (covered by temp-directory tests), and all manual criteria. Shared-cache record before first launch: `~/.cache/fluidaudio` absent at 2026-11-15T06:23Z (`.local/build/evidence/phase-1.json` in the worktree).
- Team ID and designated requirement: not available until signing setup.
- Setup DerivedData (`.local/setup/DerivedData`, main checkout): retained; removal needs owner authorization.
- Phase 2 entry: the automated phase 2 work proceeds under the owner's all-phases instruction. Its manual gates (Accessibility grant, matrix, permission survival) need the signed fixed install first.
