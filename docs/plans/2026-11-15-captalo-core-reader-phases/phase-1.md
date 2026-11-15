# Phase 1: Foundation and identity

Parent: [Cáptalo core reader plan](../2026-11-15-captalo-core-reader.md).

## Goal

Every later runtime test runs on the final app identity at one fixed path, under a stable designated requirement. Builds and tests run with one command each. No user-visible behavior changes in this phase except names.

## Entry conditions

- Plan accepted. `develop` is at `362f9ea` or a reviewed descendant, and the working tree is clean.
- The owner has added an Apple Account in Xcode > Settings > Accounts (free Personal Team). If not, tasks 1-5 still run, task 6 stops at signing with the disclosure, and the phase cannot be accepted.
- `brew install xcbeautify` is approved.

## Entry note (2026-11-15, after plan acceptance)

- An Apple Account record exists in Xcode (`DVTDeveloperAccountManagerAppleIDLists`, one identifier), but `security find-identity -v -p codesigning` still reports 0 valid identities. Xcode creates the Apple Development certificate on the first automatic-signing build with `-allowProvisioningUpdates`.
- Adjustment: `make install` cannot resolve the identity before any signed build has run. Add a one-time `make signing-setup` that runs that first signed build with `-allowProvisioningUpdates`, then checks `Scripts/signing-identity`. `make install` keeps its identity check, and its no-identity message also names `make signing-setup`. The team ID is read from the build settings after that first build.
- xcbeautify 3.2.1 was installed with Homebrew (owner-approved).

## Tasks

### 1. Rename Sotto to Cáptalo (one dedicated commit)

- `git mv Sotto.xcodeproj Captalo.xcodeproj`; `git mv Sotto Captalo`. Update the synchronized root group path (`project.pbxproj:20`), the target and product names (`:71`, `:75`, `:14`), the product reference, and the entitlements path.
- Rename Swift types and files from the `Sotto*` prefix to `Captalo*`. This is mechanical, with no logic edits.
- Product name `Captalo`; `INFOPLIST_KEY_CFBundleDisplayName = Cáptalo` (`:281`, `:326`).
- Logger subsystem and queue labels become `com.thecreativetoken.captalo` (`Sotto/Services/SpeechController.swift:6`, `:11-14`).
- UI strings "Sotto" become "Cáptalo". Studio stays until phase 4.
- Keep `LICENSE`, `docs/upstream/`, `assets/`, `Demo/`, `design/` and `Logo.icon`. In `THIRD_PARTY_NOTICES.md`, change "Sotto uses" to "Cáptalo, derived from Sotto, uses".

### 2. Identity and build settings

- `PRODUCT_BUNDLE_IDENTIFIER = com.thecreativetoken.captalo` (`:290`, `:335`).
- `DEVELOPMENT_TEAM` = the owner's Personal Team ID, replacing `8P96S63H2N` (`:172`, `:236`, `:265`, `:310`). Leave it empty and record the gap if no account exists yet.
- `MACOSX_DEPLOYMENT_TARGET = 26.0` (`:191`, `:249`, `:288`, `:333`). Keep Hardened Runtime on and the sandbox off.
- Add a shared scheme `Captalo.xcodeproj/xcshareddata/xcschemes/Captalo.xcscheme` (no shared scheme exists today).

### 3. `Packages/CaptaloCore`

```
@ CaptaloCore package scaffold
ctx: SwiftPM local package, swift-tools 6.2, macOS 26, Swift 6 mode, Swift Testing
pre: no AppKit UI, no FluidAudio
do:
  1. write Package.swift (library CaptaloCore, test target CaptaloCoreTests)
  2. move SpeechChunker.swift unchanged into Sources/CaptaloCore/Text, make API public
  3. write characterization tests from the current chunker rules (baseline §4)
  4. write PrivacyLog (typed events: enums, counts, durations)
  5. add XCLocalSwiftPackageReference + product dependency to the app target
risk: hand edit of pbxproj; verify with clean Debug and Release builds
```

- Characterization tests: `firstChunkTargets45To110Characters`, `laterChunksFlushAtSentenceEndAbove80`, `hardLimit240SplitsAtComma`, `newlinesBecomeSpaces`, `spaceInsertedAfterPeriodBeforeUppercase`, `singleTokenOver240StaysWhole` (rules at `Sotto/Services/SpeechChunker.swift:8-11`, `:26-49`, `:54-66`, `:80-108`, `:118-137`). Phase 3 replaces the chunker, and these tests then change deliberately.
- `PrivacyLogTests.eventsRenderOnlyEnumNamesAndNumbers`: covers the current event cases. It narrows leakage through this API only (review, smaller items).
- Log audit, added to `make verify` as `make log-audit`: a code search under `Captalo/` for `print(`, `NSLog(`, `os_log(` and `Logger(` outside `PrivacyLog` must return nothing. Inherited speech logging is converted, or recorded as an explicit exception until phase 3 rewrites it.

### 4. Makefile, scripts and tooling

```
@ make install CONFIG=Debug|Release (default Debug)
ctx: Scripts/signing-identity (parses `security find-identity -v -p codesigning`), codesign, ditto, .local/build/ (install-staging/, install-previous/)
do:
  1. resolve identity via Scripts/signing-identity (input injectable: file of captured output)
  2. build CONFIG signed into .local/build/DerivedData | xcbeautify (set -o pipefail); a Run Script phase writes build-info.json (commit, dirty flag, CONFIG, UTC time) into the app's Resources before Xcode signs
  3. ditto the finished bundle into an empty .local/build/install-staging/Captalo.app; codesign --verify --strict --deep on the staged copy
  4. quit only the recorded task-owned process: PID from .local/build/install-record.json whose executable path is /Applications/Captalo.app/Contents/MacOS/Captalo
  5. replace, never merge: if /Applications/Captalo.app exists and its bundle ID is com.thecreativetoken.captalo, move it to .local/build/install-previous/ (replacing the older rollback copy); move the staged bundle to /Applications/Captalo.app
  6. codesign --verify --strict --deep on the installed copy; record designated requirement and CONFIG
  7. print previous install record (commit, worktree, CONFIG); write new record outside the bundle; open app; record new PID
br: no identity -> exit 2 with Xcode Accounts message
br: a Captalo process runs that is not in the record -> stop and report; do not kill
br: staged verification fails -> exit non-zero; installed app untouched
br: installed-copy verification fails -> move the rollback copy back to /Applications/Captalo.app, verify it, exit non-zero; do not open the new build
br: /Applications/Captalo.app exists with another bundle ID -> stop and report; touch nothing
fail: any step -> exit non-zero, log in .local/build/logs/ (named by target and UTC time)
```

The rollback copy stays in `.local/build/install-previous/` until the next successful install replaces it. Phase 3's performance gate uses `make install CONFIG=Release`. Both configurations use the same bundle ID and Apple Development identity, so they share one designated requirement. Phase 1 records this.

- Other targets: `build` (Debug, signed), `build-unsigned` (Debug and Release, `CODE_SIGNING_ALLOWED=NO`), `test` (CaptaloCore debug and release), `log-audit`, `verify` (the full sequential suite), `run`.
- If xcbeautify is missing, `make` stops with "Install xcbeautify: brew install xcbeautify" and does not fall back to raw output.
- Only the integration owner runs `make install`. Worktree implementers never install to `/Applications`.

### 5. Instructions and policy

- `AGENTS.md`, project-owned section only: new names and paths, the `make` commands, the fixed install path and the install-ownership rule, plus two new rules:
  - "No fallbacks without approval. One code path per action. A new fallback layer needs an owner decision recorded in a plan. The capture layers approved in the core reader plan are not ad-hoc fallbacks."
  - "Apple documentation: use https://sosumi.ai through web fetch; send only public API names."
- `.rpi/policy.json`: replace `macos-build` with the plan's steps 3-4 plus `log-audit`, in the same commit as the Makefile.
- `README.md:27-28` and `docs/development/resource-lifecycle.md` "Build and inspection": new commands, the new DerivedData path, and the install record.
- Run the RPI installation check after the `AGENTS.md` edit. The managed root instructions measured 7,655 of 8,192 bytes at setup.

### 6. Signed install and first launch

- Before the first launch, record the state of the real `~/.cache/fluidaudio` (absent on 2026-11-14 per baseline §7): exists or not, listing and modification times. Store it in `.local/build/evidence/phase-1.json`.
- `make install` and launch. The inherited behavior should still work. **Do not download** the Kokoro model (that is phase 3).
- After launch, record the same cache state again. The inherited check (`Sotto/Services/SpeechControllerKokoro.swift:11`) may create an empty `~/.cache/fluidaudio`. If it was absent before and is empty now, it is a task-created resource. Record it, and remove it at phase acceptance only if it is still empty and no other process uses it.

## Success criteria

### Automated

- [x] `make verify` passes all steps, with a nonzero number of passing tests in debug and release.
- [x] Mutation check, run once and recorded: changing the first-chunk minimum from 45 to 40 makes `firstChunkTargets45To110Characters` fail.
- [x] `xcodebuild -showBuildSettings -scheme Captalo` reports the new bundle ID and deployment target 26.0.
- [x] `grep -rn "Shreysid\|8P96S63H2N" Captalo Captalo.xcodeproj` returns nothing.
- [x] The `Scripts/signing-identity` test with the captured "0 valid identities found" output exits 2 and prints the message. With a captured one-identity output, it returns that identity.
- [ ] (Pending signing, D1; unit-tested over temporary directories) Install replacement check: install a build containing an extra resource file, then a build without it. The file is absent from `/Applications/Captalo.app`, and the installed copy passes strict verification. Run once and record.
- [x] `python3 .rpi/scripts/rpi-verify.py` runs the new suite and passes.

### Manual

- [ ] After `make install` and after `make install CONFIG=Release`, `codesign --verify --strict --deep /Applications/Captalo.app` succeeds on the installed copy. `codesign -dv` shows the Apple Development identity and `Identifier=com.thecreativetoken.captalo`. `Contents/Resources/build-info.json` names the installed commit and configuration.
- [ ] The app launches from the fixed path. The UI shows "Cáptalo". Quit works.
- [ ] A rebuild with a source change (for example a log message), then `make install`, gives the same designated requirement (`codesign -d -r-`), and so does a Release install. Permission survival itself is tested in phase 2, because no permission is granted in this phase.

## Handoff to phase 2

Record the Team ID, the designated requirement, the install record path, the shared-cache before and after records with their disposition, and the setup DerivedData disposition. Removing the setup DerivedData needs owner authorization and a check that no Xcode process uses it.
