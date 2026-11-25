# Core reader acceptance inventory

Issue: [#11](https://github.com/juan294/captalo/issues/11). Date: 2026-11-25. Procedure: [release playbook](release-playbook.md).

**Status: BLOCKED.** The automated suite passes on the build under test. The live checks have not run on it, and first install plus permission denial have no recorded result on a notarized DMG. The release decision is recorded separately from publishing, in the last section.

## Build under test

| Item | Value |
| --- | --- |
| Commit | `96c2cab439791b5ca19acc7553cd139c5d65490a`, clean |
| Installed app | `/Applications/Captalo.app`, Release, `1.0.0-beta.2` (build 2), Apple Development signature, `codesign --verify --deep --strict` passes |
| Mac | M5 Ultra, macOS 27.2.1 (26B131) |
| Published artifact | `Captalo-1.0-beta.2.dmg`, commit `aa8e817`, SHA-256 `ee60417e4e8ee788cfedff8fff08f1620663d9e97a592776fc8a08738cc4cbae`; the GitHub asset digest matches; Gatekeeper accepts it as Notarized Developer ID; the stapled ticket validates |

This build is used to find blockers. It is not the release candidate: setting the version and signing with Developer ID create a different artifact. The exact candidate still needs the identity, first-install, permission and real-Mac checks that the playbook binds to it.

Evidence labels: **candidate** means measured on `96c2cab`. **Carried** means measured on an earlier commit; the code changes since then are named. **Reported** means the owner reported it. **None** means that no record was found in `docs/` or the retained local evidence.

## Inventory

| # | Check | Evidence | Status |
| --- | --- | --- | --- |
| 1 | Full local gate | Candidate. `make verify` 2026-11-25: 18 of 18, tree identity unchanged. Core 275 tests (debug and release), speech 23 (debug and release), scripts 139 | PASS |
| 2 | Version in the bundle | Candidate. `Scripts/set-version --check 1.0.0-beta.2 --app /Applications/Captalo.app` exits 0 | PASS for this build |
| 3 | Completeness, structural | Candidate. Both voices: 13 of 13 units played once, in order. Device change replays one unit. No unit over 35 s | PASS |
| 4 | Completeness, by ear | None. The recognition round trip is not run (recognizer download not approved); the plan makes the ten-minute listening audit the gate | OPEN, owner |
| 5 | Offline speech, probe | Candidate. `offline-test`: no network attempt under the deny profile | PASS |
| 6 | Offline speech and OCR, installed app with Wi-Fi off | Partly, beta 2 on macOS 26.7.2: the first launch and the voice install (07:23:58) fell between two Wi-Fi power changes (07:23:03 and 07:25:38; off and then on is inferred). No reading or region was recorded while Wi-Fi was off | OPEN |
| 7 | Selected text in Rex, Safari, Chrome, Preview, TextEdit, Word | Carried from `cadd6b3` (2026-11-22): 6 of 6 matched, clipboard and focus kept. Since then: Stop, new default shortcuts, panel changes, Screen Recording recovery, request ordering in `RequestCoordinator`. [Matrix](../research/2026-11-22-native-capture-matrix.md) | OPEN, rerun |
| 8 | Missed presses in Rex ([#8](https://github.com/juan294/captalo/issues/8)) | Carried. Two presses with no capture event on 2026-11-22, unexplained. Reported 2026-11-23: selection reading stayed silent in one Rex pane while region reading worked; the trace showed that the simulated Copy left the clipboard unchanged | OPEN, known issue |
| 9 | Stop reading | Carried from `c5066dc`: shortcut and panel Stop in Rex and Preview, 12 to 31 ms, clipboard kept. [Notes](../plans/2026-11-22-stop-reading-notes.md) | OPEN, rerun with Control-Option-X |
| 10 | Stop with an empty selection | Carried. Rex stops after 1.1 s; in Preview the reading plays to its end. The dedicated Stop covers both | ACCEPTED, S3 known issue (owner, 2026-11-25) |
| 11 | OCR order, fixtures | `make ocr-probe`: two columns, ruled table, borderless terms, borderless table of sentences, ruled questions and answers. All five pass on macOS 27.2.1 and 26.7.2 with the A7 and A8 repairs. Before the repair the two-column fixture failed on 26.7.2 with the probe at `a799b40`; beta 2 and `96c2cab` have the same OCR sources (inferred for the apps) | PASS after A7 and A8, probe only |
| 12 | OCR order by ear, scanned PDF, code screenshot | None. Three Vision word substitutions are recorded in [#9](https://github.com/juan294/captalo/issues/9) | OPEN |
| 13 | Region capture on a notarized build | Reported. Beta 2, macOS 27.3 beta laptop, 2026-11-23: prompt on first press, read on the second press after the grant | PASS, one Mac |
| 14 | Focus and Esc after region capture, full-screen app, second display | None | OPEN |
| 15 | Playback recovery on an output change | Reported on `9b86dbc` (2026-11-19); probe passes on the candidate. On macOS 26.7.2 both recorded readings have `replays=0`, so they show no output change | OPEN, rerun |
| 16 | First install of a notarized DMG | Partly, beta 2 on macOS 26.7.2, a Mac with no Cáptalo app, support folder or preferences: SHA-256, ticket, Gatekeeper (Notarized Developer ID), signature and first launch pass; the voice files were installed. The app was copied with `ditto` and a download mark, so macOS ran it from an App Translocation path; a Finder drag was not tested. Crash reports: none | OPEN, repeat with a Finder drag |
| 17 | Accessibility denied, granted, revoked | Beta 2 on macOS 26.7.2: after the grant, two selection readings of 6 and 100 characters through Accessibility played to the end (first audio scheduled after 3.7 s cold and 1.0 s). A press without the grant is not logged, and no revoke was recorded. Reported by the owner on 2026-11-25: "It all worked great" | PARTLY, owner report |
| 18 | Screen Recording denied, then granted | Beta 2 on macOS 26.7.2: macOS permission checks at 07:29:41 to 07:30:29 and one app relaunch; no region capture or OCR event was recorded. Grant recorded on macOS 27.3 beta (row 13). Denial not recorded | OPEN |
| 19 | Permission survival across `make install` | Not recorded | OPEN |
| 20 | Shared FluidAudio cache untouched | Candidate. `~/.cache/fluidaudio` absent on 2026-11-25; no open network sockets in the running app; footprint 180 MB | PASS at the time of the check |
| 21 | Voice quality acceptance | Reported 2026-11-14 on generated samples: the owner confirmed `af_heart` and `af_bella` as "great" ([assessment](../research/2026-11-14-clean-eyes-reevaluation-assessment.md)). None on the installed app | OPEN for the candidate; the sample verdict stands |
| 22 | macOS 26 | Supported (owner, 2026-11-25). Beta 2 on macOS 26.7.2 (25G332, M4 Pro, 24 GB): installs, launches, reads selected text through Accessibility, no network sockets, shared FluidAudio cache absent, footprint 170 MB with a 516 MB peak. Probes there: both voices 13 of 13 units, also under a profile that kills the process on an outbound connection (the control kill was seen in the session; its output was not kept); OCR cancel and timeout pass; OCR order needed A7. Region OCR by shortcut, Stop, revoke and output change have no recorded event; the owner reported that all worked | PARTLY: repeat the unrecorded steps on the exact candidate |

## Findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| A1 | S4 | Both the installed build and the beta 2 DMG carry `com.apple.security.network.client`, from `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` in both app configurations. The app is not sandboxed, so the entitlement should have no effect (inferred). It contradicts the local-only promise | Removed on this branch by owner decision (2026-11-25): the setting is `NO` in both configurations, and `Scripts/shell-audit` fails if it returns. Not yet in a signed build |
| A2 | Process | The evidence analyzer required by the playbook did not exist | `Scripts/release-evidence`, with tests in `Scripts/tests/test_release_evidence.py` |
| A5 | Process | The app has no test target, and `executable-application-tests` is a first-release requirement in `.rpi/release-profile.json` | Open |
| A3 | Process | No independent Wave B charter has run on a candidate | Open |
| A6 | Evidence | The event log does not record a press that Cáptalo refuses for a missing permission, so denial steps need a screenshot or a witness | Accepted as a constraint |
| A7 | S3 | macOS 26.7.2: Vision reports aligned prose in two columns as a table, so Cáptalo read across the columns (5 of 5 runs). It does not report borderless tables of sentences, so those would be read down their columns. Workaround: select one column | Repaired in `DocumentTranscript`, with measured positions as tests |
| A8 | S3 | macOS 27.2.1: a definition wider than the table that Vision reports was read twice | Repaired in `DocumentTranscript` |
| A9 | S4 | Reading order is still decided by thresholds. A table without a header is read by column when every column is mostly cells of 15 or more words (at most one short cell, or one in three); a grid that spans two of three columns separates the third; macOS 26 reports two short lists side by side as a table, read by row; only one borderless table is joined on a page; Vision can merge lines across a narrow column gap | Known limits |
| A4 | Evidence | Cáptalo's log events are info level. A log query over 2026-11-22 to 2026-11-25 returned none, so past use is not evidence. A live run must record events while it happens | Accepted as a constraint |

## Owner decisions (2026-11-25)

1. **Evidence analyzer (A2):** build a small one for the first production release. It is `Scripts/release-evidence`. The playbook requirement stays; steps 4 and 6 now name the tool, its limits and that Cáptalo has no pause.
2. **Stop with an empty selection (row 10):** accepted as an S3 known issue, because the dedicated Stop (panel button or Control-Option-X) works around it. In Preview the reading plays to its end; in Rex it stops after 1.1 s. It belongs in the release notes of the first production release.
3. **macOS 26 (row 22):** tested on 26.7.2; it found A7. The owner keeps macOS 26 supported and asked for the repair.

## Release decision

Not made. No publication is proposed by this record.
