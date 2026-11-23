import Foundation
import Testing
@testable import CaptaloCore

@Suite struct BuildLabelTests {
    static func json(commit: String = "aa8e817cf831a83f81f8e818d972d0d1e3fb0469", dirty: String = "false",
                     configuration: String = "Release", builtAt: String = "2026-11-22T19:33:04Z") -> Data {
        Data("""
        {"commit": "\(commit)", "dirty": \(dirty), "configuration": "\(configuration)", "built_at": "\(builtAt)"}
        """.utf8)
    }

    @Test func showsVersionAndShortCommit() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json())
        #expect(label.text == "v1.0 · aa8e817")
        #expect(label.detail == "Version 1.0, commit aa8e817, Release build, built 2026-11-22 19:33 UTC")
    }

    @Test func marksABuildWithUncommittedChanges() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json(dirty: "true", configuration: "Debug"))
        #expect(label.text == "v1.0 · aa8e817+")
        #expect(label.detail == "Version 1.0, commit aa8e817 with uncommitted changes, Debug build, built 2026-11-22 19:33 UTC")
    }

    /// A plain xcodebuild call writes "unknown" and a null dirty flag.
    @Test func unknownCommitShowsTheVersionOnly() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json(commit: "unknown", dirty: "null"))
        #expect(label.text == "v1.0")
        #expect(label.detail == "Version 1.0, Release build, built 2026-11-22 19:33 UTC")
    }

    @Test func missingOrUnreadableBuildInfoShowsTheVersionOnly() {
        #expect(BuildLabel.make(version: "1.0", buildInfo: nil) == BuildLabel(text: "v1.0", detail: "Version 1.0"))
        #expect(BuildLabel.make(version: "1.0", buildInfo: Data("not json".utf8)).text == "v1.0")
    }

    @Test func unreadableBuildDateIsLeftOut() {
        let label = BuildLabel.make(version: "1.0", buildInfo: Self.json(builtAt: "yesterday"))
        #expect(label.detail == "Version 1.0, commit aa8e817, Release build")
    }

    @Test func noVersionAndNoCommitSaysUnknown() {
        #expect(BuildLabel.make(version: nil, buildInfo: nil) == BuildLabel(text: "Version unknown", detail: "Version unknown"))
        #expect(BuildLabel.make(version: "  ", buildInfo: nil).text == "Version unknown")
    }

    @Test func commitWithoutVersionStillShows() {
        #expect(BuildLabel.make(version: nil, buildInfo: Self.json()).text == "aa8e817")
    }

    @Test func panelModelCarriesTheBuildLabel() {
        let build = BuildLabel(text: "v1.0 · aa8e817", detail: "Version 1.0, commit aa8e817")
        var input = PanelModelTests.ready
        input.build = build
        #expect(PanelModel.make(input).build == build)
    }
}
