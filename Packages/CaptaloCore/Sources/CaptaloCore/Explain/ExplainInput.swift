import Foundation

public enum ExplainDepth: String, Codable, Sendable {
    case simple, middle, detailed

    fileprivate var targetPercent: Int {
        switch self {
        case .simple: 50
        case .middle: 40
        case .detailed: 75
        }
    }
}

public enum ExplainStyle: String, Codable, Sendable {
    case plain, examples, metaphors, picture
}

public enum ExplainInputError: Error {
    case empty, tooManyWords, tooManyBytes, profileTooLong
}

/// The untrusted user message. The separate trusted instruction interprets its settings.
public struct ExplainInput: Encodable, Sendable {
    public let source: String
    public let depth: ExplainDepth
    public let style: ExplainStyle
    public let profile: String
    public let targetWords: Int

    enum CodingKeys: String, CodingKey {
        case source, depth, style, profile
        case targetWords = "target_words"
    }

    public init(source: String, depth: ExplainDepth, style: ExplainStyle, profile: String) throws {
        guard source.utf8.count <= 256 * 1024 else { throw ExplainInputError.tooManyBytes }
        let count = source.split(whereSeparator: \.isWhitespace).count
        guard count > 0 else { throw ExplainInputError.empty }
        guard count <= 3000 else { throw ExplainInputError.tooManyWords }
        guard profile.count <= 240 else { throw ExplainInputError.profileTooLong }
        self.source = source
        self.depth = depth
        self.style = style
        self.profile = profile
        self.targetWords = max(20, (count * depth.targetPercent + 99) / 100)
    }
}
