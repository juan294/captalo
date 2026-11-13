# Cáptalo setup handoff

Prepared on 2026-11-13 for the next session in `/Users/juan/code/captalo`.

## Scope and starting point

The owner authorized a dedicated workspace, GitHub fork, Summon configuration, project briefing, full native RPI adoption, Archy tracking and local Graphify enrollment. This setup does not include a product implementation plan, application changes or a release.

The public fork is [juan294/captalo](https://github.com/juan294/captalo), from [Shreysid/Sotto](https://github.com/Shreysid/Sotto), starting at `30e0dfbf2cfbef01b8c462bfec2452b3c0295a61`. The integration branch is `develop`; `main` retains upstream history for a later authorized release. Resolve the current setup commit with `git rev-parse develop`; verify the working tree and remote branch when resuming. The original source, project, artwork, license and third-party notices remain unchanged.

## Workspace and workflow

- `.summon` selects `opus-codex-shell`. The workspace is registered and trusted locally; both the ordinary and Rex-specific dry runs passed. Launch with `summon captalo`.
- Codex and Claude native RPI skills were installed with cc-rpi 2.1.0's direct-route lifecycle engine from clean source commit `dd792f88487bea97a72f5e6240f5b660b62cd250`. The installation owns 189 manifest entries, with 26 Codex and 25 Claude skills. The installation check is healthy with no drift or conflicts.
- Shared project instructions live in `AGENTS.md`; `CLAUDE.md` imports them. The [adoption record](plans/2026-11-13-rpi-adoption.md), [resource contract](development/resource-lifecycle.md) and [release procedure](release/release-playbook.md) document the native macOS workflow and remaining release prerequisites.
- Native skill/hook execution and trust in a fresh agent session have not been observed. File installation health does not establish live harness behavior.

## Tracking

Archy's project registry contains active, monitored Cáptalo at path `captalo`, repository `juan294/captalo`, project ID `79115f9e-276d-4e2b-a2a4-dd3221ddc112`. The local morning-briefing and portfolio-watchdog project lists include this workspace. Existing schedule enablement and CI routing remain unchanged.

Local Graphify configuration uses the repository's own `graphify-out` link. Web graph publication is disabled and review publication is local-only. No hosted export or CI workflow was added. The setup evidence directory records the live indexing result separately from registry enrollment.

## Verification and retained evidence

The inherited app compiled successfully with Xcode 27.0 at `/Applications/Xcode-beta.app`, using an unsigned Debug build and `.local/setup/DerivedData`. The sequential verification runner passed whitespace, RPI ownership/installation and macOS build checks. The first verification-runner invocation refused an evidence path outside `.rpi/local`; rerunning with the required evidence location passed.

There is no inherited automated application test target. No app was launched, voice model downloaded, permission grant changed, or runtime speech/capture/privacy test performed. An independent review of the setup and separate reuse, quality and efficiency passes found no actionable issue.

Local evidence is deliberately ignored by Git:

- `.rpi/local/setup-verification.json` and `.local/setup/verification.log`: sequential setup gate results and candidate identity.
- `.local/setup/xcodebuild.log`: initial native build log.
- `.local/setup/summon-dry-run.txt` and `.local/setup/summon-rex-dry-run.txt`: workspace launch previews.
- `.local/setup/archy-registry.json`: registry readback.
- `.rpi/local/transactions/`: lifecycle installation journal and recovery evidence.

The setup task retains its roughly 924 MB DerivedData directory for the next Cáptalo session to reuse or review under the resource contract. Build processes exited; no Cáptalo app, Docker stack, database or task service was started. Shared Xcode caches and existing application data remain user-owned. Archy's shared Graphify service and its retained indexes are fleet-owned resources, not disposable Cáptalo task services.

## Next session

Start `$rpi-plan` in Codex or `/rpi-plan` in Claude in this workspace. Read the [briefing](briefing.md) and [design brief](research/2026-11-13-captalo-brief.md), verify actual refs and the local setup evidence, and query the local graph before unfamiliar source exploration. Stop after a reviewed product plan.

The plan must address pleasant local speech, reliable capture across terminals/browsers/PDFs/documents, the accepted screen-region OCR fallback, English listening for a second-language reader, clipboard/focus safety, and nearly invisible operation without a floating transcript. Voice acceptance and representative cross-app reproductions should establish the foundation before app renaming or broad changes. Setup approval does not authorize implementation, signing, release, or hosted publication.
