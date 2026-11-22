# Stop reading implementation and acceptance

The implementation of 2026-11-22-stop-reading.md was based on local develop at a7ca813. The clean application candidate is c5066dce279e6cf4b53e1274bac8f6df554b65f7, built and tested in the feature/stop-reading worktree. The Stop button is in the menu-bar rail on every tab. The optional global binding is in Read. The user can use the button immediately and choose a shortcut later.

## Native Release

The signed Release at /Applications/Captalo.app was tested on the Studio with synthetic text. A process-only CoreAudio tap monitored output after speech began. The tester cleared the highlight and invoked either the global shortcut or the actual rail button. Captures and playback events came from the installed application.

| Source | Global Stop hotkey, two trials | Panel Stop |
| --- | --- | --- |
| Preview | 25.5 and 29.0 ms to last detected speech | 13.7 ms with speech active at the press |
| Rex | 29.6 and 30.4 ms | 12.6 ms to last detected speech |

The initial Preview button press landed during a 130 ms pause. A repeat synchronized to a voiced buffer measured 13.7 ms while repository verification ran in the background. All four button/shortcut combinations emitted the stop event, with no new capture. The hotkey preserved source focus. The clipboard was preserved across Stop, and a subsequent reading produced speech. The test binding was supplied only at launch. Both test runs restored the original clipboard and frontend app, released their meters and test documents, and returned the installed candidate to a normal launch.

## Review and verification

Automated regressions exercise cancellation of a pending selection or OCR request, late Stop delivery, an idle Stop, reading the same text again after Stop, and voice samples on both sides of Stop. Reusing the playback-only stop failed the directed tests. Independent review found that a newer read of the same text could toggle off a session that Stop had already superseded. The new test reproduced this. The correction compares the session generation with the last Stop before applying the toggle. Subsequent review approved the implementation. The simplify pass consolidated cancellation of older input and reused the panel recorder and audio sink. No model or capture path was added.

All 18 repository checks passed on the clean application candidate, including both builds, offline and completeness checks, panel renders and the script tests. The 20 focused coordinator tests and 32 focused panel/shortcut tests passed. The ready-state panel render includes both controls and fits the existing dimensions. The live Read pane scrolls when notices use the remaining vertical space.

Raw local receipts are under .local/stop-checks and .local/stop-native on the primary checkout. These are retained for local review. The two other Macs are reserved for later efficiency testing.

## Deviations

The first button driver searched accessibility windows. The native popover appears under the menu-bar extras accessibility tree. After correcting the driver, both button tests passed. No application change was needed for this discrepancy. The project has no rpi-plan or rpi-implement overlay for this task.
