# Cáptalo RPI adoption

Date: 2026-11-13. Scope: repository/workspace setup authorized by Juan; no product implementation or release.

## Preserve

Preserve upstream Sotto history at `30e0dfbf2cfbef01b8c462bfec2452b3c0295a61`, Swift sources, Xcode project/scheme, pinned FluidAudio dependency, Apache-2.0 license, third-party notices and assets. There were no upstream AGENTS/CLAUDE instructions, RPI registrations, hooks, application tests or GitHub workflows to migrate. No unknown custom instruction files need removal.

## Adopt

Use the verified direct source receipt at `~/.config/cc-rpi/installations/user/local/source-receipt.json`, resolving to `/Users/juan/code/cc-rpi`, clean source commit `dd792f88487bea97a72f5e6240f5b660b62cd250`, version 2.1.0. Install project-scoped Claude and Codex native skills, managed rules, policy hooks and complete resources using the ownership-aware engine. Selected domains: ci-workflow, deployment-safety, error-patterns, git-workflow, github-cli, macos-rules, multi-agent, shell-tools and systematic-debugging. Supabase, Python and WebMCP domain skills are not selected; universal conditional rule bodies remain installed for future task applicability.

Project-owned facts remain outside managed blocks in AGENTS.md; CLAUDE.md imports AGENTS.md. Install lifecycle skills remain user-scoped, avoiding duplicate project/user registrations. No plugin cache or user installation is changed.

## Ownership and capability review

The engine owns manifest entries, content-addressed baseline bytes, full installed skill resources, marked instruction blocks and explicit settings keys. This project owns `.rpi/policy.json`, the project facts, resource contract and release profile. Setup plans and transaction/recovery evidence stay in ignored `.rpi/local/`.

The first plan correctly refused capability writes without explicit selection. The reviewed additions are scoped policy hooks, prompts for release/provider commands, and denial of mirror pushes. The user's full RPI setup request authorizes installing these project controls. Re-plan with `config:claude-policy`, `config:codex-hooks` and `resource:codex-permissions` selected; do not bypass a failed transaction or overwrite unknown configuration.

## Local conventions

Integration is `develop`; production is `main`. Temporary work stays local. Sutura owns CI routing, and no hosted workflow is introduced. Product planning occurs in the dedicated Cáptalo workspace after setup. Xcode retains Sotto names until an approved product change. A build is not an application test or release acceptance.

## Verification and handoff

Review the engine plan for scope, conflicts, instruction budget and recovery paths, apply the exact ready plan, then run installation check and diagnostics. Run whitespace validation and the real Xcode build sequentially at integration. Record setup evidence separately from unresolved application tests, voice audition, OCR and permission behavior. Follow `docs/release/release-playbook.md` for a future release; missing required runtime evidence blocks release.

## Adoption result

The reviewed install plan applied atomically with 275 operations and no conflicts. Recovery journal: `.rpi/local/transactions/64033fc0c14c4eb3a8461c0141f450dd/journal.json`. Engine check returned `healthy` with zero operations/conflicts. Project-owned CLAUDE import was retained. Diagnostics found no missing resources, duplicate skill registrations, route collisions, configuration issues, import cycles, or instruction-budget overflow. Managed root instructions are 7,655 bytes against an 8,192-byte budget; combined Codex instructions are below its assumed 32,768-byte limit.

Native hook registration is configured; native discovery, project trust and actual hook execution remain unverified until a session opens this workspace. Diagnostics' `CLAUDE.md` source-added observation corresponds to the deliberately retained project-owned import, not missing workflow resources. The optional Git pre-push receipt gate remains off; the declared local suite and publication instructions still apply. No global policy or native plugin cache was changed.

The setup coordinator owns the final sequential build/verification receipt and commit. Product tests, runtime acceptance, signing, and the release evidence analyzer remain explicit first-release prerequisites in `.rpi/release-profile.json`, not unfinished RPI installation. Source remains Sotto; no app behavior was changed by adoption.
