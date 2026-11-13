# Cáptalo release procedure

This is the single release procedure for Cáptalo. Native `rpi-release` delegates to it. Repository setup is not a release. Juan owns publication, signing, provider, and rollback decisions.

## Present readiness

The project is a public fork with an inherited Sotto Xcode target and local speech engine. No Cáptalo binary has been released. There is no application test target, signed packaging pipeline, or candidate-bound runtime evidence yet. The setup check/build can pass while release readiness remains **BLOCKED**. Do not manufacture `xcodebuild test` success or a coverage percentage.

Machine-readable selection and gaps are recorded in `.rpi/release-profile.json`. Before the first app release, the product plan must supply executable application checks and the evidence analyzer described below. Installing RPI does not implement them.

## Adaptation profile

| Area | Cáptalo decision |
| --- | --- |
| Product | Native Swift/SwiftUI/AppKit macOS app; macOS 15+, Apple silicon primary target |
| Repository | Public, `juan294/captalo`; upstream `Shreysid/Sotto` |
| Branches | `develop` integration; `main` production; merge-commit promotion |
| Build | Xcode `Sotto.xcodeproj`, scheme `Sotto`, pinned SwiftPM FluidAudio dependency |
| Artifact | Exact macOS app bundle with version, source commit and cryptographic digest |
| State | Local preferences, model cache, permissions and clipboard; no application database |
| Network | Build/model assets during explicit setup; speech and future OCR must work offline |
| Release owner | Juan |
| Rollback | Restore the previously verified app bundle with owner authorization; preserve preferences/models unless a migration recovery contract explicitly permits changes |
| Hosted CI | None configured at bootstrap; Sutura owns future routing |
| Wave A | Mandatory: fixed candidate, nonempty passing evidence, required miss blocks, tag last |
| Wave B | Selected for app runtime releases because a persistent background app accesses cross-app text/clipboard and global hotkeys; one independent round per candidate. Not selected for setup/document-only changes. |
| Waves C–H | Not selected as infrastructure: no multi-tenant backend, payment flow, deployment fleet, or combinatorial release system. Targeted desktop regressions and real-Mac evidence remain required. Reassess on material scope change. |

## Required ordering

1. Confirm the exact release scope with Juan. Confirm clean candidate files, integration/production refs, upstream origin, release baseline and retained-resource state. Do not publish working branches.
2. Freeze the candidate commit and dependency/model identities. Build the candidate locally using the selected full Xcode. Capture the bundle identity and digest. Signing credentials, notarization and distribution destinations must be explicitly established; they are not configured by setup.
3. Run local checks sequentially. Use `.rpi/policy.json` and `.rpi/scripts/rpi-verify.py` for the declared repository suite. Before any app release, add the actual automated app tests and coverage reporting to the declared selection. No required failure or skip may be converted into a pass.
4. Exercise the exact candidate on a real Mac with synthetic fixtures: selected text in Rex, a browser, selectable PDF and document editor; empty/failed selection; clipboard preservation; pause/stop/repeat; long-passage completion; permissions denied then granted; focus preservation; offline speech; and accepted voice quality. Once OCR ships, include selected-region capture, scanned PDFs, reading order and capture permission recovery. Record unsupported apps rather than claim universal coverage.
5. Run one fresh-context Wave B charter for runtime releases. Try repeated actions, errors and recovery, interruption, a second app/session, locale/device changes, copy versus result, downstream state, and whether the resulting behavior should exist. Report each maneuver as PASS, FAIL or N/A with reason. Repair S1/S2 findings and verify those repairs; S3/S4 require an owner-approved known-issue disposition.
6. Analyze the exact candidate's evidence with a tested analyzer. It must reject zero passes, missing/failed/skipped required probes, mismatched commit/bundle digest, missing cleanup, and missing required real-Mac or charter evidence. The analyzer is a first-release prerequisite and is not present at bootstrap. A prose checklist cannot substitute for it.
7. Present source and bundle identity, automated results, runtime evidence, privacy/offline evidence, known issues, signing/distribution status and rollback artifact to Juan. Obtain the authorization required for the concrete publication action.
8. Promote the verified tree with a merge commit, confirm its identity, then create the release tag last through `rpi-release`. Never tag an unverified merge result. Publish only the authorized artifact/destination and inspect the exact resulting release. No rerun/re-push debugging loop.

## Evidence and rollback

Keep raw logs, screenshots, fixture captures and audio under ignored `.local/` or `.rpi/local/`; redact any shared report. Curated release summaries may live under `docs/release/`. Each result names the candidate commit, bundle digest, environment, time, command or procedure, outcome and cleanup disposition.

A broken reading workflow, clipboard data loss, privacy violation or permission failure after distribution requires stopping rollout and presenting the exact rollback artifact and scope to Juan. Preserve failure evidence and user data. Restore only after the required authorization; never delete shared caches or reset permissions as a blanket repair.
