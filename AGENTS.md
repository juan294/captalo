# Project: Cáptalo

Cáptalo (`captalo`) is a native macOS utility for understanding visible text through local speech. The goal is: select text and hear it, or mark a screen region for local OCR, without a floating transcript or cloud processing.

Start with [the briefing](docs/briefing.md) and [the accepted design brief](docs/research/2026-11-13-captalo-brief.md).

## Current state and authority

This is a public fork of `Shreysid/Sotto`, based on `30e0dfbf2cfbef01b8c462bfec2452b3c0295a61`. Keep upstream attribution, `LICENSE`, and `THIRD_PARTY_NOTICES.md`. The app is renamed Cáptalo (project `Captalo.xcodeproj`, scheme `Captalo`, bundle ID `com.thecreativetoken.captalo`, macOS 26 minimum). The app icon (`Captalo/Logo.icon`) and the menu-bar glyph (`Captalo/Assets.xcassets/MenuBarGlyph.imageset`) are Cáptalo's own artwork (concept A, 2026-11-19). The core reader plan (`docs/plans/2026-11-15-captalo-core-reader.md`) defines the remaining work; OCR and the unobtrusive shell are not complete until its phases are accepted.

Shared instructions live here; `CLAUDE.md` imports this file. Do not introduce an import cycle. Use the installed native RPI skill for the requested phase, reading its full instructions and references. Codex invokes `$rpi-plan`, `$rpi-implement`, and other `$rpi-*` skills; Claude invokes `/rpi-plan`, `/rpi-implement`, and other `/rpi-*` skills. Native `/plan` and `/status` are not RPI workflows. Planning and product implementation belong in this workspace, with the normal phase acceptance boundaries.

## Stack and source map

- Swift, SwiftUI, AppKit, AVFoundation, and macOS Accessibility; macOS 26 or newer.
- Xcode project `Captalo.xcodeproj`, shared scheme `Captalo`; Swift Package Manager pins FluidAudio in `Captalo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- `Packages/CaptaloCore/`: pure logic and its Swift Testing suite (no AppKit UI, no FluidAudio). `PrivacyLog` is the only logging API for app code.
- `Captalo/App/`, `Captalo/Services/`, `Captalo/UI/`, `Captalo/Models/`: AppKit and system adapters, speech and the inherited UI.
- `Scripts/`: signing identity, install, log audit and build-info helpers, with tests in `Scripts/tests/`.
- No application database, backend, cloud runtime, Supabase, Docker stack, or listening service is required.

## Verification

Run checks sequentially and preserve the first failure evidence. A compiler/build pass does not prove capture, speech quality, offline behavior, or permission recovery.

```sh
make verify    # the sequential suite listed in .rpi/policy.json, via rpi-verify.py
make test      # CaptaloCore tests, debug and release
make build-unsigned
```

The Makefile sets `DEVELOPER_DIR` to `/Applications/Xcode-beta.app/Contents/Developer` (override per command); never change the machine's developer selection. Every `xcodebuild` call pipes through `xcbeautify` (`brew install xcbeautify`). Builds use `.local/build/DerivedData`. Package resolution may download pinned build dependencies; that never proves offline runtime behavior. Each phase that adds a verification step updates `make verify`'s policy list in the same commit.

Signed installs: `make signing-setup` once, then `make install [CONFIG=Release]`. Only the integration owner runs `make install`; worktree implementers run tests and unsigned builds only. The fixed path is `/Applications/Captalo.app`; the install record is `.local/build/install-record.json` and the rollback copy `.local/build/install-previous/`. The install quits only the recorded process.

- No fallbacks without approval. One code path per action. A new fallback layer needs an owner decision recorded in a plan. The capture layers approved in the core reader plan are not ad-hoc fallbacks.
- Apple documentation: use https://sosumi.ai through web fetch; send only public API names.

Runtime voice/capture validation and signed distribution are separate from these checks. The authoritative release procedure is [docs/release/release-playbook.md](docs/release/release-playbook.md).

## Git and publication

- `origin`: `juan294/captalo`; `upstream`: `Shreysid/Sotto` for fetch only.
- Integration branch: `develop`. Production branch: `main`.
- Work in isolated worktrees or local temporary branches, then integrate reviewed changes locally into `develop`.
- Keep upstream history and use a merge commit when promoting `develop` to `main`; never rewrite upstream history or push to upstream.
- No release, app distribution, signing/account changes, or production publication follows from local setup authorization. Inspect triggers and require explicit publication scope before external writes.
- Sutura owns fleet CI routing. Do not add routing changes, mode toggles, or hosted experimentation here. `.github/workflows/ci.yml` (Sutura decision 2026-11-20) runs 13 of the 16 `make verify` checks unsigned on the hosted `xcode-27` image (Xcode 27.2) for pushes to `main` and for manual dispatches (owner-authorized, on the exact `develop` commit before a beta; Sutura addendum 2026-11-28); `rpi-installation`, `ocr-probe` (Vision document recognition fails on the hosted VM), `panel-render` (the menu-bar panel drawn to PNG from fixtures), signing, permissions, audio and Rex stay local. Change it only through Sutura.

## Product and data constraints

All speech and OCR processing must remain local. No cloud fallback, telemetry, retained captured text, or screenshots by default. Owner decision 2026-11-20: a future Explain action may send captured text to a cloud language model, only after the user connects a provider; Read, OCR and speech never use the network. Explain is not built; see [the opt-in brief](docs/research/2026-11-20-explain-cloud-opt-in-brief.md). Model/dependency downloads are explicit setup operations. Preserve clipboard data, focus, and user permissions; use synthetic text for testing. Never silently read unrelated or stale clipboard content when selection capture fails.

Read [the resource contract](docs/development/resource-lifecycle.md) before allocating task services, reusing caches, or cleaning resources. Application support files, downloaded model caches, macOS permission grants and inherited preferences are persistent user data, not disposable worktree resources.

## Source intelligence and artifacts

Use local `graphify_local` for `captalo`, with `project_path` set to this repository root and graph access through its own `graphify-out` symlink. Query before unfamiliar code orientation, caller tracing, broad changes, or PR impact reviews, then confirm against source. If the graph is absent or stale, report that and read source directly. Never use hosted Graphify for this project; never call Graphify memory-writing or reflection actions.

Version curated documents in `docs/research/`, `docs/plans/`, `docs/decisions/`, and `docs/release/`. Keep raw operational reports in ignored `docs/agents/`, and machine-specific build logs/evidence in ignored `.local/` or `.rpi/local/`. Do not commit credentials, local captures, model assets, or user-specific runtime state.
<!-- rpi:push-accountability:start -->
# Push Accountability

Keep working branches and worktrees local. Finish applicable tests, coverage,
typechecks, lint, build and deployment preflight locally, resolve failures,
and integrate completed work locally into the documented integration branch.
Inspect workflow and deployment triggers before the single authorized push of
that completed branch. Never create Vercel Preview deployments or publish
working branches/PRs for experimentation. If an integration push would create a
Preview, stop before pushing and use only a documented, non-destructive bypass.
Production publication remains separately and explicitly authorized. Read-only
inspection of existing runs and deployments is allowed.

Commit or preserve intended changes before pulling; never pull through a dirty
tree. After an authorized push, inspect every expected workflow for the exact
pushed commit. Diagnose failures from existing logs and reproduce/fix locally.
Report the failed remote result; do not trigger reruns or a fix-and-repush loop.
A new remote action needs authorization after the complete local gates pass.
<!-- rpi:push-accountability:end -->
<!-- rpi:rpi-details:start -->
# RPI Details

## Context Management

- Each RPI phase should be its own conversation.
  Preserve their acceptance boundaries unless the user explicitly authorizes
  continuation; a continuation instruction does not remove verification.
- Use `/clear` between unrelated tasks.
  Use `/compact` when context is heavy but the task continues.
- Handoffs record objective, approved scope, base/current commit and worktree,
  findings, decisions, check evidence and tested identity, deviations, risks and
  next phase. On resume, verify actual files, refs and evidence validity before
  relying on the handoff; compaction never grants new authority.
- Subagents are context control mechanisms --
  they search/read in their window and return only distilled results.
- Research and planning happen against the integration branch.
  Implementation happens in worktrees or temporary branches.

## Rules for All Phases

- Read controlling instructions/contracts and directly mentioned files completely.
  Inspect implementation to the depth needed; reuse valid prior reads.
- In `rpi-research`, document what exists without improvement recommendations.
  Use the separate `rpi-assess` workflow for evaluative research and alternatives.
- Every code reference must include file:line.
- Delegate only useful bounded independent assignments within this phase.
  A narrow task may stay with the parent. State objective, permitted actions,
  owned files, evidence/output, resource budget and terminal condition for each
  assignment. Missing required results remain coverage gaps until resolved.
- Never write documents with placeholder values.
- Before allocating local task services or reporting their cleanup, read `.rpi/rules/resource-lifecycle.md`. Release owned disposable resources within authorization or record a retained-resource handoff before task/worktree completion; report cleanup failures explicitly. A worktree or name prefix does not prove database ownership.
- Exhaust all tools before suggesting manual steps --
  check CLI tools, shell commands, MCP servers, and file tools
  before escalating to the user.

## Rules for Implementation

- Follow the atomic loop:
  implement -> independent review -> repair -> simplify -> verify.
  The native simplify command or Codex helper catches code reuse, quality, and efficiency issues
  that the plan-compliance reviewer does not check.
- Independent batch work stays local, one owner per file set/worktree and one
  integration owner. Never use a batch mode that automatically publishes PRs.
  Keep at most three simultaneous implementers; use fewer when the task or
  available resources do not justify three.
- Run ALL automated verification after each phase.
- Stop after each phase for acceptance unless the user explicitly authorizes
  continuation. Finish all authorized phase work before that gate.
- If a technical discovery invalidates the plan contract, record the adjustment
  and explain the impact before dependent work; ask only for a required new decision.

## Pre-Release Workflow

`rpi-pre-launch` -> `rpi-remediate` -> `rpi-update-docs` -> `rpi-release`

After `rpi-pre-launch`, include a simplify pass for reuse, quality and
efficiency. Track its findings with the other audit results; resolve security
and infrastructure findings through the same review, repair and verification
loop. Preserve all required audit domains regardless of staffing.

Release verification is proportional. Wave A's truthful local gate applies to
every release; Wave B exploratory charters and Waves C-H run only when the
project's release profile selects them, one Wave B round per candidate.

Resolve every confirmed actionable finding before acceptance. For an S3 or S4
finding (below S1/S2: data loss, a security boundary breach, a broken core
workflow or a normal-use defect with no workaround), an owner-approved accepted
known issue, recorded with its severity and reason, is a valid disposition; fix
it in a later release. Reject false positives with evidence. Strategic findings needing a new architectural decision
receive explicit local dispositions and owner review; external issue creation
requires authorization. Never silently discard a finding.

## Testing Philosophy

Prefer automated verification.
Manual only for: sudo, hardware, new installs, visual-only.
Use deterministic linting/formatting tools. Preserve TDD for behavioral code
changes. Run all required phase/final gates locally, sequentially with failure
aggregation; a later success cannot erase an earlier failure. Reuse evidence
only for unchanged tested inputs, never as a substitute for an invalidated gate.
<!-- rpi:rpi-details:end -->
<!-- rpi:rule-map:start -->
## Conditional rule access

Before acting on a matching task/path, read the installed rule body below.
The installation manifest records the selected components and exact mappings.
This root map applies even when a session starts at the repository root and
later edits a nested directory; it is an instruction contract, not a native
Codex glob loader. Sessions started inside a subproject also read their actual
root-to-current-directory instruction chain. Preserve project-specific overrides.

| Task or path | Required resource | Essential constraint |
| --- | --- | --- |
| Docker, local stacks, database tests, task services or resource cleanup (even without a Dockerfile) | `.rpi/rules/resource-lifecycle.md` | Prove ownership; finish disposable lifecycles; preserve shared/recovery data and report retained resources. |
| Deployment, CI, release or infrastructure configuration | `.rpi/rules/deployment-safety.md` | Local gates first; no Vercel Preview; production needs authorization. |
| SQL, Supabase migrations, schema, data access or database tests | `.rpi/rules/supabase.md` | Reset/test locally; privileges and RLS are distinct; remote targets need authorization. |
| Behavioral changes, tests, fixtures and validation | `.rpi/rules/testing.md` | TDD for behavioral code; every required check must run and pass. |
| WebMCP, MCP tools, tool registration or agent-facing interfaces | `.rpi/rules/webmcp.md` | Validate on the server; isolate unstable browser APIs and test caller recovery. |

If a required component is missing, report the exact missing path and run the
read-only installation check before proceeding with dependent work. Never
invent a successful read or silently treat an incomplete install as healthy.
<!-- rpi:rule-map:end -->
