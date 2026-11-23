# Changelog

All notable changes to Cáptalo are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow the rules in [the release playbook](docs/release/release-playbook.md#versions): `X.Y.Z` for production and `X.Y.Z-beta.N` for betas.

## [Unreleased]

### Added

- The menu-bar panel footer shows the version, for example `v1.0.0 beta 2`. Hover over it to see the commit, build type and build date.
- `Scripts/set-version` sets the version and build number for each release and checks that a built app carries them.

## [1.0.0-beta.2] - 2026-11-23

Build 2, commit `aa8e817`.

### Fixed

- The repeated Screen Recording setup prompt. If macOS still reports that screen access is off after a request, Cáptalo offers **Open Settings**. You can continue to read selected text without screen access.

## [1.0.0-beta.1] - 2026-11-22

Build 1, commit `bb97faa`. The build record includes uncommitted changes.

### Added

- First Cáptalo beta: reads selected text and text in a screen region aloud on your Mac, on macOS 26 or later.

[Unreleased]: https://github.com/juan294/captalo/compare/v1.0.0-beta.2...develop
[1.0.0-beta.2]: https://github.com/juan294/captalo/compare/v1.0.0-beta.1...v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/juan294/captalo/releases/tag/v1.0.0-beta.1
