<!-- rpi-overlay: skill=rpi-release; written-against=034673a9ed50 -->
# Project overlay for rpi-release

## Procedure

The release procedure is [docs/release/release-playbook.md](../../docs/release/release-playbook.md). Its "Versions" section is the version contract. These steps are required for every Cáptalo release, beta or production.

1. Take the version from the request, as the stock skill requires. A production version is `X.Y.Z`; a beta is `X.Y.Z-beta.N`. Never guess the version. The build number is not part of the request: `Scripts/set-version` raises it by one for each new version.
2. Run `Scripts/set-version --show` and `git tag -l 'v*'`. The requested version must be newer than the project's version, and its tag `v<version>` must not exist. Origin also carries the upstream Sotto tags `v0.1.0` and `v1.0.1`; a Cáptalo version must never reuse one of them. If the requested version collides, stop and ask Juan for another.
3. Run `Scripts/set-version <version>`. It is the only way the version enters the project. Do not edit `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` or `CAPTALO_PRERELEASE` by hand, and do not pass them to `xcodebuild` or `make` as overrides. Commit the change to `Captalo.xcodeproj/project.pbxproj` in the release preparation commit.
4. The version-bearing file inventory is `Captalo.xcodeproj/project.pbxproj` only. Repeat the stock scan for the old version anyway, and add any new product file that carries the version to this list and to `Scripts/set-version`.
5. Build the candidate through `make` from a clean tree, so `build-info.json` records the commit and `"dirty": false`. Then run `Scripts/set-version --check <version> --app <candidate Captalo.app>` on the exact bundle that is signed and packaged. It must exit 0 before the release is presented for authorization. A failure blocks the release.
6. Derive every name from the version: DMG `Captalo-<version>.dmg`, tag `v<version>`, release title `Cáptalo X.Y.Z` or `Cáptalo X.Y.Z beta N`. The release notes state the line that `Scripts/set-version --show` prints, for example `1.0.0-beta.3 (build 3)`, and the short commit. In `CHANGELOG.md`, move the `[Unreleased]` entries under a heading for the new version and date, add that build line, and update the compare links at the end of the file.
7. A beta is cut from `develop` and published with `gh release create --prerelease`. A production release is promoted to `main` with a merge commit and published without `--prerelease`. A production bundle must not carry a prerelease: to promote a beta, run `Scripts/set-version X.Y.Z`, which clears `CAPTALO_PRERELEASE` and raises the build number.
8. On the installed candidate, confirm that the panel footer shows `vX.Y.Z beta N` for a beta or `vX.Y.Z` for production.
