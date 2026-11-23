import Foundation

/// The version in the panel footer: the marketing version, plus "beta N" for a
/// beta (Scripts/set-version). The tooltip adds the commit from
/// `build-info.json` (Scripts/write-build-info), so a tester can tell two
/// builds of one version apart.
public struct BuildLabel: Equatable, Sendable {
    /// The footer text: "v1.0.0" or "v1.0.0 beta 3".
    public let text: String
    /// What VoiceOver says: "Version 1.0".
    public let spoken: String
    /// The tooltip, with the commit, build type and date.
    public let detail: String

    public init(text: String, spoken: String, detail: String) {
        self.text = text
        self.spoken = spoken
        self.detail = detail
    }

    public static let unknown = BuildLabel(text: "Version unknown", spoken: "Version unknown", detail: "Version unknown")

    private struct Info: Decodable {
        let commit: String?
        let dirty: Bool?
        let configuration: String?
        let built_at: String?
        /// "beta.3" for a beta, empty for a production release.
        let prerelease: String?
    }

    /// `version` is the bundle's short version string; `buildInfo` is the
    /// contents of `build-info.json`, nil when the file is missing.
    public static func make(version: String?, buildInfo: Data?) -> BuildLabel {
        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let info = buildInfo.flatMap { try? JSONDecoder().decode(Info.self, from: $0) }
        let commit = info?.commit.flatMap(shortCommit)
        let dirty = info?.dirty == true

        let beta = info?.prerelease.flatMap(betaNumber).map { " beta \($0)" } ?? ""
        let text = version.map { "v\($0)\(beta)" } ?? unknown.text
        let spoken = version.map { "Version \($0)\(beta)" } ?? unknown.spoken
        var detail = [spoken]
        if let commit {
            detail.append(dirty ? "commit \(commit) with uncommitted changes" : "commit \(commit)")
        }
        if let configuration = info?.configuration?.nonEmpty { detail.append("\(configuration) build") }
        if let built = info?.built_at.flatMap(builtDate) { detail.append("built \(built)") }
        return BuildLabel(text: text, spoken: spoken, detail: detail.joined(separator: ", "))
    }

    /// "beta.3" is 3; any other shape is nil.
    private static func betaNumber(_ prerelease: String) -> Int? {
        guard prerelease.hasPrefix("beta."), let number = Int(prerelease.dropFirst(5)), number > 0 else { return nil }
        return number
    }

    /// The first seven characters of a hexadecimal commit; nil for "unknown".
    private static func shortCommit(_ commit: String) -> String? {
        guard commit.count >= 7, commit.allSatisfy(\.isHexDigit) else { return nil }
        return String(commit.prefix(7))
    }

    /// "2026-11-22T19:33:04Z" as "2026-11-22 19:33 UTC"; nil when unreadable.
    private static func builtDate(_ stamp: String) -> String? {
        guard let date = try? Date(stamp, strategy: .iso8601) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date) + " UTC"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
