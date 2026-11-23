import Foundation

/// The version in the panel footer, so a tester can tell one installed build
/// from another. The marketing version alone does not change between builds;
/// the commit from `build-info.json` (Scripts/write-build-info) does.
public struct BuildLabel: Equatable, Sendable {
    /// The footer text: "v1.0 · aa8e817".
    public let text: String
    /// The tooltip and VoiceOver text, with the build type and date.
    public let detail: String

    public init(text: String, detail: String) {
        self.text = text
        self.detail = detail
    }

    public static let unknown = BuildLabel(text: "Version unknown", detail: "Version unknown")

    private struct Info: Decodable {
        let commit: String?
        let dirty: Bool?
        let configuration: String?
        let built_at: String?
    }

    /// `version` is the bundle's short version string; `buildInfo` is the
    /// contents of `build-info.json`, nil when the file is missing.
    public static func make(version: String?, buildInfo: Data?) -> BuildLabel {
        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let info = buildInfo.flatMap { try? JSONDecoder().decode(Info.self, from: $0) }
        let commit = info?.commit.flatMap(shortCommit)
        let dirty = info?.dirty == true

        var text: [String] = []
        var detail: [String] = []
        if let version {
            text.append("v\(version)")
            detail.append("Version \(version)")
        }
        if let commit {
            text.append(dirty ? "\(commit)+" : commit)
            detail.append(dirty ? "commit \(commit) with uncommitted changes" : "commit \(commit)")
        }
        guard !text.isEmpty else { return .unknown }
        if let configuration = info?.configuration?.nonEmpty { detail.append("\(configuration) build") }
        if let built = info?.built_at.flatMap(builtDate) { detail.append("built \(built)") }
        return BuildLabel(text: text.joined(separator: " · "), detail: detail.joined(separator: ", "))
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
