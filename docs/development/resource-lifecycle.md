# Cáptalo local resources

## Current footprint

Cáptalo is a native macOS app. It has no Docker stack, database, server port, remote development service, or resource-cleanup daemon. Do not allocate these merely to run repository checks.

The canonical workspace is `/Users/juan/code/captalo`. Parallel code tasks use isolated worktrees and separate build directories. A worktree does not isolate macOS preferences, Accessibility/Screen Recording permissions, clipboard state, downloaded model caches, or audio devices.

## Resource classes

| Resource | Class | Owner and lifecycle |
| --- | --- | --- |
| `.local/setup/DerivedData/` | Retained setup build cache | Cáptalo setup task; retain through setup review, then reuse for local builds. Remove only with scoped cleanup authorization after checking no Xcode/build process uses it. |
| `.local/setup/xcodebuild.log` and `.rpi/local/` | Recovery/evidence | Cáptalo setup task; retain through handoff and candidate review. Never prune as a disposable cache. |
| SwiftPM and Xcode shared caches | Shared reusable | Xcode/package tooling; preserve. Do not clean globally to solve a local build problem. |
| Kokoro/FluidAudio downloaded models | Persistent reusable | User/application; shared consumers and exact paths must be identified before deletion. No model download or removal is part of RPI installation. |
| Upstream Sotto preferences, support files, and macOS permission grants | Persistent user state | Preserve. A fork or worktree does not grant ownership of upstream app data. |
| Test screenshots, audio and selected text | Sensitive task data | Prefer synthetic fixtures in a unique ignored task directory; record ownership and intended disposal before capture. Never index or publish them. |

## Build and inspection

From the repository root, use the Makefile. Builds use `.local/build/DerivedData`; logs go to `.local/build/logs/`.

```sh
make build-unsigned   # Debug and Release, CODE_SIGNING_ALLOWED=NO
make test             # CaptaloCore tests
```

These commands build and exit; they do not launch the app, download the runtime voice, or start a service. Package resolution may download build dependencies. Other developers set `DEVELOPER_DIR` to their installed full Xcode. Do not change global `xcode-select` as part of a project task.

`make install` is the integration owner's command. It writes `/Applications/Captalo.app` (task-owned only when its bundle ID is `com.thecreativetoken.captalo`), `.local/build/install-record.json` (commit, worktree, configuration, designated requirement, launched PID), `.local/build/install-staging/` and one rollback copy in `.local/build/install-previous/`. It quits only the PID in the record and stops if another process runs from the fixed path.

`.local/setup/DerivedData/` is the stale setup build cache from before the rename. Remove it only with owner authorization after checking that no Xcode process uses it.

Before removing an owned build directory, verify its resolved path, task record, current worktree, and all live Xcode/build consumers. Never run broad cache, Docker, or application-support cleanup.

## Future runtime testing

Record exact process IDs, app bundle identity, build path, fixture directory and intended finish action before launching a test app. The app uses its own bundle ID and defaults domain (`com.thecreativetoken.captalo`); the upstream `com.Shreysid.Sotto` domain is never touched. Until phase 3 removes it, the inherited speech code can create the shared `~/.cache/fluidaudio` directory, which other FluidAudio consumers may use. Establish isolation before treating any runtime state as disposable. Stop only the verified task-owned app process. Permission changes and model deletion require their own explicit authorization.

At task completion report stopped processes, retained assets, the owner, and the next review action. For setup, retain the build cache and logs for the next Cáptalo session; no app or service launch is required.
