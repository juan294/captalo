# Capture matrix: procedure and status

- Date: 2026-11-15. Plan: `2026-11-15-captalo-core-reader.md`, phase 2, tasks 5 and 6.
- Status: **not run.** The matrix needs the signed install at `/Applications/Captalo.app` and one Accessibility grant. Signing is blocked (notes, deviation D1), so no app in the matrix has a recorded result yet. Phase 2 cannot be accepted until this matrix runs.
- Waivers: none requested or granted.

## What is under test

The layered reader in `Packages/CaptaloCore/Sources/CaptaloCore/Capture/`:

1. Accessibility: `AXSelectedText`, then `AXSelectedTextRange` with `AXStringForRange`, then the WebKit text-marker range. Chromium and Electron apps get `AXManualAccessibility` once per launch. `AXEnhancedUserInterface` is never set.
2. A confirmed empty selection is "nothing selected" and never reaches Copy.
3. When Accessibility gives no answer and `CopyPolicy` allows Copy: the app's own Copy menu item (Cmd+C key equivalent), pressed through Accessibility. A disabled Copy item means "nothing selected".
4. Synthetic Cmd+C only when the app has no Copy item, after the modifiers are released (500 ms limit).
5. Every Copy runs inside the fenced clipboard transaction (`ClipboardTransaction`): snapshot, recheck, one-change attribution in a 1 s window, final check, restore with the `org.nspasteboard` transient and auto-generated markers.

`CopyPolicy` list at this commit: `com.microsoft.VSCode` (`editor.emptySelectionClipboard`, default on). Any app whose no-selection case produces text or changes the clipboard is added and retested.

## Apps

| App | Mandatory (decision 5) |
|---|---|
| Rex | yes |
| Safari | yes |
| Google Chrome | yes |
| Preview (selectable PDF: `make capture-pdf`) | yes |
| TextEdit | yes |
| Microsoft Word | yes |
| Ghostty, Terminal, Firefox, Visual Studio Code, Pages, Notes | recorded, not blocking |

## Procedure

1. `make install` (Debug, integration owner only). Grant Accessibility to `/Applications/Captalo.app` once.
2. Quit Cáptalo through the install record, then launch the probe build: `open /Applications/Captalo.app --args -CaptureProbe YES`. In probe mode the playing session is the Debug-only `SilentTimedSession` seam (30 s, no audio), labelled as a seam in all evidence.
3. `make clipboard-sentinel`. It **replaces** the general clipboard with plain text, RTF, a custom type and a file URL.
4. Open `Fixtures/capture-matrix.txt` (or the PDF) in the app under test, note the time, and run the cases:
   - (a) select the whole fixture and press the read shortcut;
   - (b) place the caret with nothing selected and press;
   - (c) with a seam session playing, select nothing and press (expect `seamSession state=stopped`), then select the fixture and press (expect a new `started`).
5. `Scripts/capture-matrix-collect --since "<time>" --app "<name>" --version "<version>" --case <a|b|c>` writes `.local/capture/<ISO time>-<app>.json`. Probe events carry only enums, counts and durations: result, layer, expected and captured lengths, clipboard intact, focus kept, provider time (the probe's own pre-press clipboard materialization), elapsed time and change-count delta.
6. Summarize here per app: name and version, layer, pass or fail, clipboard intact, focus kept, change delta, latency, provider time, no-selection outcome, stop and replace outcomes. Flag any Copy over 300 ms.
7. Permission survival (task 7): after a changed rebuild and `make install`, capture works without re-granting. Record both designated requirements.

## Accepted clipboard limitation (owner decision 9, 2026-11-15)

The Copy layers stay, with every fence and check in phase 2. These races remain and are accepted as a known S3 limitation, recorded here and in release notes when a release is planned:

- (a) a single foreign clipboard write within the 1 s Copy window can be spoken and then overwritten by the restore;
- (b) a foreign write in the instant between the final change-count check and the restore write is overwritten;
- (c) a source-app Copy that arrives after the 1 s window replaces the previous clipboard.

Clipboard managers can also observe the source app's Copy before the restore; the transient markers only ask them to ignore the restore write. Cáptalo never claims that the clipboard is always preserved.

## Results

None yet. See the status line above.
