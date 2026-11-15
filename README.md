# Cáptalo

Hear visible text and understand it with less effort. Cáptalo is a local macOS read-aloud utility derived from [Shreysid/Sotto](https://github.com/Shreysid/Sotto).

**Status:** development fork. Workspace and workflow configuration are installed; no Cáptalo release is available. The app identity is Cáptalo. The core reader (selection reading, the quiet agent-app shell and screen-region OCR) is built on `develop` and passes its automated checks; runtime acceptance on a signed install is still pending, so none of it is a shipped feature.

## Intended experience

Select text and use a shortcut to hear it. For text that cannot be selected, the planned second action is a shortcut plus a dragged screen rectangle, recognized locally. Speech and OCR stay on the Mac. No cloud voice service, floating transcript, subscription or paid reader dependency.

The existing foundation supplies Accessibility selection capture with a clipboard fallback, local Kokoro speech through FluidAudio, and playback controls. Voice quality, application compatibility and offline behavior still require runtime acceptance testing.

## Start here

- [Project briefing](docs/briefing.md): accepted requirements, fork decision, source baseline and next-session scope.
- [Setup handoff](docs/setup-handoff.md): verification evidence, local integrations and next steps.
- [Design brief](docs/research/2026-11-13-captalo-brief.md): product goals and acceptance criteria.
- [Agent instructions](AGENTS.md): native Claude and Codex RPI workflows and project commands.
- [Release procedure](docs/release/release-playbook.md): evidence and publication boundaries.
- [Upstream README](docs/upstream/Sotto-README.md): original installation and usage information for Sotto, not Cáptalo releases.

## Development

Requires macOS 26+, Apple silicon for the intended local inference path, Xcode 27 and `xcbeautify`. Swift Package Manager resolves the pinned FluidAudio dependency. Dependencies and model assets require initial downloads; listening is intended to operate offline afterward.

```sh
make test             # CaptaloCore unit tests (debug and release)
make build-unsigned   # Debug and Release app builds into .local/build/DerivedData
make verify           # full sequential local gate
```

When the global developer directory selects Command Line Tools, set `DEVELOPER_DIR` for that command to the installed Xcode developer directory. Do not change the machine-wide developer selection just for this project. A local build is not a signed or distributable release.

The integration branch is `develop`; `main` is reserved for explicitly authorized releases. Keep implementation branches local. `origin` is the Cáptalo fork and `upstream` is the original project, retained for reviewed upstream updates.

The project includes a `.summon` configuration for the locally installed `opus-codex-shell` layout. After registration, launch with `summon captalo`.

## Attribution and license

Cáptalo is based on Sotto by Shreysid. This README was rewritten for the Cáptalo fork on 2026-11-13; the original is preserved under `docs/upstream/`. Upstream application source and assets remain unchanged during workspace setup.

The [Apache License 2.0](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md) are preserved. FluidAudio and Kokoro supply the inference foundation. Cáptalo is an independent fork and does not imply endorsement by upstream authors.
