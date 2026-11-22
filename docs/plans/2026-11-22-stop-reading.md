# Stop reading

Add a Stop reading button to the menu-bar panel and an optional user-chosen global shortcut. Both cancel active speech and older pending reads without looking up the selection. The six-app study found that clearing a highlight in Preview left playback running and Rex waited for Copy. A separate action lets the user stop in either app. Keep shortcut assignment optional, including on an existing installation.

Owner decision 13 of 2026-11-22 (core reader plan) later gave the Stop shortcut an initial value, Control-Option-X. It stays optional and outside setup, and a recorded or cleared value is kept.

## Implementation and acceptance

One implementation phase covers the ordered stop operation, its two entry points and acceptance. [Phase specification](2026-11-22-stop-reading-phases/phase-1.md). Baseline is local develop at a7ca813. The owner authorized implementation. Test the installed candidate on the Studio; the other Macs are reserved for later performance work.

## Consumer sweep

Search for `stopSession`, `reservePress`, `play(text:`, `readRegion` and `shortcutChanged`. Cover the shortcut delegate, voice samples, selection and region requests, the panel model, shortcut recorder and its conflict check. Preserve the existing voice-repair stop semantics. The current paths are in RequestCoordinator.swift:62, CaptaloApplicationDelegate.swift:17, CaptaloAppStateSettings.swift:40 and ReadPane.swift:17.

## Stuck states and recovery

Idle Stop is silent and repeatable. A later Read works normally. Unassigned or conflicting shortcuts can be changed in the Read pane; the button is available independently. Stop supersedes an earlier capture while allowing its clipboard restoration to finish. Test delayed results and a later read, render the panel, and time the global action during live reading.
