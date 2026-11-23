import Foundation
import Testing
@testable import CaptaloCore

@Suite struct BuildLabelTests {
    static func json(commit: String = "aa8e817cf831a83f81f8e818d972d0d1e3fb0469", dirty: String = "false",
                     configuration: String = "Release", builtAt: String = "2026-11-22T19:33:04Z",
                     prerelease: String = "") -> Data {
        Data("""
        {"commit": "\(commit)", "dirty": \(dirty), "configuration": "\(configuration)", "built_at": "\(builtAt)", \
        "prerelease": "\(prerelease)"}
        """.utf8)
    }

    /// Scripts/set-version writes CAPTALO_PRERELEASE; write-build-info records it.
    @Test func betaBuildsSayWhichBeta() {
        let label = BuildLabel.make(version: "1.0.0", buildInfo: Self.json(prerelease: "beta.3"))
        #expect(label.text == "v1.0.0 beta 3")
        #expect(label.spoken == "Version 1.0.0 beta 3")
        #expect(label.detail.hasPrefix("Version 1.0.0 beta 3, commit aa8e817"))
    }

    @Test func productionBuildsShowTheVersionOnly() {
        #expect(BuildLabel.make(version: "1.0.0", buildInfo: Self.json(prerelease: "")).text == "v1.0.0")
    }

    /// Older build-info.json files have no prerelease key.
    @Test func missingPrereleaseMeansProduction() {
        #expect(BuildLabel.make(version: "1.0.0", buildInfo: Self.json()).text == "v1.0.0")
    }

    /// Only the shape set-version writes is shown; anything else is left out.
    @Test func unexpectedPrereleaseIsLeftOut() {
        #expect(BuildLabel.make(version: "1.0.0", buildInfo: Self.json(prerelease: "rc 1")).text == "v1.0.0")
    }

    /// The commit means nothing to most people, so it stays in the tooltip.
    @Test func showsTheVersionWithTheCommitInTheTooltip() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json())
        #expect(label.text == "v1.0")
        #expect(label.spoken == "Version 1.0")
        #expect(label.detail == "Version 1.0, commit aa8e817, Release build, built 2026-11-22 19:33 UTC")
    }

    @Test func marksABuildWithUncommittedChanges() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json(dirty: "true", configuration: "Debug"))
        #expect(label.text == "v1.0")
        #expect(label.detail == "Version 1.0, commit aa8e817 with uncommitted changes, Debug build, built 2026-11-22 19:33 UTC")
    }

    /// A plain xcodebuild call writes "unknown" and a null dirty flag.
    @Test func unknownCommitShowsTheVersionOnly() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json(commit: "unknown", dirty: "null"))
        #expect(label.text == "v1.0")
        #expect(label.detail == "Version 1.0, Release build, built 2026-11-22 19:33 UTC")
    }

    @Test func missingOrUnreadableBuildInfoShowsTheVersionOnly() {
        #expect(BuildLabel.make(version: "1.0", buildInfo: nil)
            == BuildLabel(text: "v1.0", spoken: "Version 1.0", detail: "Version 1.0"))
        #expect(BuildLabel.make(version: "1.0", buildInfo: Data("not json".utf8)).text == "v1.0")
    }

    @Test func unreadableBuildDateIsLeftOut() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json(builtAt: "yesterday"))
        #expect(label.detail == "Version 1.0, commit aa8e817, Release build")
    }

    @Test func noVersionAndNoCommitSaysUnknown() {
        #expect(BuildLabel.make(version: nil, buildInfo: nil) == .unknown)
        #expect(BuildLabel.unknown.text == "Version unknown")
        #expect(BuildLabel.make(version: "  ", buildInfo: nil).text == "Version unknown")
    }

    @Test func commitWithoutVersionStaysInTheTooltip() {
        let label = BuildLabel.make(version: nil, buildInfo: Self.json())
        #expect(label.text == "Version unknown")
        #expect(label.detail == "Version unknown, commit aa8e817, Release build, built 2026-11-22 19:33 UTC")
    }

    @Test func panelModelCarriesTheBuildLabel() {
        let build = BuildLabel(text: "v1.0", spoken: "Version 1.0", detail: "Version 1.0, commit aa8e817")
        var input = PanelModelTests.ready
        input.build = build
        #expect(PanelModel.make(input).build == build)
    }
}
