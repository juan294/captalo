# Cáptalo

Hear visible text and understand it with less effort. Cáptalo is a local macOS read-aloud utility derived from [Shreysid/Sotto](https://github.com/Shreysid/Sotto).

**Status:** beta. Three notarized betas are published as [GitHub pre-releases](https://github.com/juan294/captalo/releases) (macOS 26 or later); there is no production release. Selection reading, screen-region OCR, Stop and the menu-bar panel are built and pass the automated checks. Acceptance on a signed install is in progress; the [acceptance inventory](docs/release/2026-11-25-core-reader-acceptance.md) lists what is proven and what is open.

## Intended experience

Select text and use a shortcut to hear it. For text that cannot be selected, the second action is a shortcut plus a dragged screen rectangle, recognized locally. Speech and OCR stay on the Mac. No cloud voice service, floating transcript, subscription or paid reader dependency.

To stop a reading, click **Stop** in the menu-bar panel. You can also press **Control-Option-X** (the initial **Stop reading** shortcut, which you can change in the **Read** pane) from another app, even after you clear the selection. The read shortcuts start as **Control-Option-S** (selection) and **Control-Option-A** (region).

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
