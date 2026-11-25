# Cáptalo release procedure

This is the single release procedure for Cáptalo. Native `rpi-release` delegates to it. Repository setup is not a release. Juan owns publication, signing, provider, and rollback decisions.

## Present readiness

The project is a public fork with a renamed Cáptalo Xcode target and inherited local speech engine. Three betas are published as GitHub pre-releases: `v1.0.0-beta.1` (commit `bb97faa`, build 1), `v1.0.0-beta.2` (commit `aa8e817`, build 2) and `v1.0.0-beta.3` (commit `867634e`, build 3). Each is a DMG signed with Developer ID and notarized by Apple. All three were packaged by hand; the evidence is in ignored `.local/distribution/`. There is no packaging script yet, and no production release. [CHANGELOG.md](../../CHANGELOG.md) records each release. Automated tests cover `Packages/CaptaloCore`, `Packages/CaptaloSpeech` and `Scripts/` only; there is no app UI test target, signed packaging pipeline, or candidate-bound runtime evidence yet. The [core reader acceptance inventory](2026-11-25-core-reader-acceptance.md) records what is proven and what is open. The setup check/build can pass while release readiness remains **BLOCKED**. Do not manufacture `xcodebuild test` success or a coverage percentage.

Machine-readable selection and gaps are recorded in `.rpi/release-profile.json`. Before the first app release, the product plan must supply executable application checks and the evidence analyzer described below. Installing RPI does not implement them.

## Adaptation profile

| Area | Cáptalo decision |
| --- | --- |
| Product | Native Swift/SwiftUI/AppKit macOS app; macOS 26+, Apple silicon primary target |
| Repository | Public, `juan294/captalo`; upstream `Shreysid/Sotto` |
| Branches | `develop` integration; `main` production; merge-commit promotion |
| Build | `make verify` and `make install CONFIG=Release` around Xcode `Captalo.xcodeproj`, scheme `Captalo`, local `Packages/CaptaloCore`, pinned SwiftPM FluidAudio dependency |
| Artifact | Exact macOS app bundle with version, source commit and cryptographic digest |
| State | Local preferences, model cache, permissions and clipboard; no application database |
| Network | Build/model assets during explicit setup; speech and future OCR must work offline |
| Release owner | Juan |
| Rollback | Restore the previously verified app bundle with owner authorization; preserve preferences/models unless a migration recovery contract explicitly permits changes |
| Hosted CI | `.github/workflows/ci.yml` runs 13 unsigned checks on pushes and pull requests to `develop` and `main`; Sutura owns its routing. It is not release evidence |
| Wave A | Mandatory: fixed candidate, nonempty passing evidence, required miss blocks, tag last |
| Wave B | Selected for app runtime releases because a persistent background app accesses cross-app text/clipboard and global hotkeys; one independent round per candidate. Not selected for setup/document-only changes. |
| Waves C–H | Not selected as infrastructure: no multi-tenant backend, payment flow, deployment fleet, or combinatorial release system. Targeted desktop regressions and real-Mac evidence remain required. Reassess on material scope change. |

## Required ordering

1. Confirm the exact release scope with Juan. Confirm clean candidate files, integration/production refs, upstream origin, release baseline and retained-resource state. Do not publish working branches.
2. Freeze the candidate commit and dependency/model identities. Build the candidate locally using the selected full Xcode. Capture the bundle identity and digest. Signing credentials, notarization and distribution destinations must be explicitly established; they are not configured by setup.
3. Run local checks sequentially. Use `.rpi/policy.json` and `.rpi/scripts/rpi-verify.py` for the declared repository suite. Before any app release, add the actual automated app tests and coverage reporting to the declared selection. No required failure or skip may be converted into a pass.
4. Exercise the exact candidate on a real Mac with synthetic fixtures: selected text in Rex, a browser, selectable PDF and document editor; empty/failed selection; clipboard preservation; stop/repeat (Cáptalo has no pause); long-passage completion; permissions denied then granted; focus preservation; offline speech; and accepted voice quality. Once OCR ships, include selected-region capture, scanned PDFs, reading order and capture permission recovery. Record unsupported apps rather than claim universal coverage.
5. Run one fresh-context Wave B charter for runtime releases. Try repeated actions, errors and recovery, interruption, a second app/session, locale/device changes, copy versus result, downstream state, and whether the resulting behavior should exist. Report each maneuver as PASS, FAIL or N/A with reason. Repair S1/S2 findings and verify those repairs; S3/S4 require an owner-approved known-issue disposition.
6. Analyze the exact candidate's evidence with a tested analyzer. It must reject zero passes, missing/failed/skipped required probes, mismatched commit/bundle digest, missing cleanup, and missing required real-Mac or charter evidence. The analyzer is `Scripts/release-evidence`: `template --app <Captalo.app>` prints an evidence file bound to the exact bundle, and `check --app <Captalo.app> --evidence <file>` must exit 0. Keep the filled file under ignored `.local/`. The required probes and charter maneuvers are listed in the script; removing one needs an owner decision. Run it in a clean checkout of the candidate commit, with that commit's `.rpi/local/verification.json`. It does not replace the version, signature, model identity and application-test gates of the other steps. A prose checklist cannot substitute for it.
7. Present source and bundle identity, automated results, runtime evidence, privacy/offline evidence, known issues, signing/distribution status and rollback artifact to Juan. Obtain the authorization required for the concrete publication action.
8. Promote the verified tree with a merge commit, confirm its identity, then create the release tag last through `rpi-release`. Never tag an unverified merge result. Publish only the authorized artifact/destination and inspect the exact resulting release. No rerun/re-push debugging loop.

## Versions

Owner decision 2026-11-23: every release, beta or production, sets its version automatically through `Scripts/set-version`, and the menu-bar panel footer shows it.

| | Production | Beta |
| --- | --- | --- |
| Version | `X.Y.Z` | `X.Y.Z-beta.N` |
| Tag | `vX.Y.Z` | `vX.Y.Z-beta.N` |
| Cut from | `main`, after a merge-commit promotion | `develop` |
| GitHub release | normal | `--prerelease` |
| Panel footer | `vX.Y.Z` | `vX.Y.Z beta N` |

`Captalo.xcodeproj/project.pbxproj` is the only version source. `Scripts/set-version <version>` writes `MARKETING_VERSION` (`X.Y.Z`, the bundle's short version), `CAPTALO_PRERELEASE` (`beta.N` or empty) and `CURRENT_PROJECT_VERSION` (the build number) into both app configurations. The build number goes up by one for each new version and is never reused, so macOS and testers can order any two builds. The script refuses a malformed version or one older than the project's. `Scripts/write-build-info` records `CAPTALO_PRERELEASE` in `build-info.json`, where the panel reads it.

`Scripts/set-version --check <version> --app <Captalo.app>` is a Wave A gate: the project and the exact candidate bundle must both carry the released version and build number. Cáptalo must not reuse the upstream Sotto tags `v0.1.0` and `v1.0.1` in origin. The step-by-step version procedure for `rpi-release` is `.rpi/project/rpi-release.md`.

Builds between releases carry the last release's version. The footer tooltip shows the commit, so a development build can still be told apart.

## Evidence and rollback

Keep raw logs, screenshots, fixture captures and audio under ignored `.local/` or `.rpi/local/`; redact any shared report. Curated release summaries may live under `docs/release/`. Each result names the candidate commit, bundle digest, environment, time, command or procedure, outcome and cleanup disposition.

A broken reading workflow, clipboard data loss, privacy violation or permission failure after distribution requires stopping rollout and presenting the exact rollback artifact and scope to Juan. Preserve failure evidence and user data. Restore only after the required authorization; never delete shared caches or reset permissions as a blanket repair.
