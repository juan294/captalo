/// One synthesis unit (plan "Synthesis units", review R9, V2-5).
public struct SynthesisUnit: Equatable, Sendable {
    public let id: Int
    public let paragraphID: Int
    public let sentenceID: Int
    public let text: String
    /// The last unit of its sentence: a sentence pause follows.
    public let endsSentence: Bool
    /// The last unit of its paragraph: a paragraph pause follows.
    public let endsParagraph: Bool
}

/// Splits paragraphs into units lazily: one unit per sentence; a sentence
/// longer than `maxLength` is split at the last whitespace or pause
/// punctuation before the limit, or at a grapheme-cluster boundary when an
/// unbroken token leaves no other break. The first unit of a reading is
/// capped at `firstMaxLength`. No unit crosses a paragraph.
public struct UnitChunker<Paragraphs: Sequence>: Sequence where Paragraphs.Element == Paragraph {
    public static var maxLength: Int { 400 }
    public static var firstMaxLength: Int { 160 }
    static var pauseCharacters: Set<Character> { [",", ";", ":", "—", "–", ")", "]"] }

    let paragraphs: Paragraphs

    public init(_ paragraphs: Paragraphs) {
        self.paragraphs = paragraphs
    }

    public func makeIterator() -> Iterator {
        Iterator(paragraphs: paragraphs.makeIterator())
    }

    public struct Iterator: IteratorProtocol {
        var paragraphs: Paragraphs.Iterator
        var queue: [SynthesisUnit] = []
        var nextUnitID = 0
        var nextParagraphID = 0
        var nextSentenceID = 0
        var firstUnitCut = false
        /// Paragraphs pulled from the source so far (laziness checks).
        public private(set) var paragraphsPulled = 0

        public mutating func next() -> SynthesisUnit? {
            while queue.isEmpty {
                guard let paragraph = paragraphs.next() else { return nil }
                paragraphsPulled += 1
                enqueue(paragraph)
            }
            return queue.removeFirst()
        }

        private mutating func enqueue(_ paragraph: Paragraph) {
            let paragraphID = nextParagraphID
            nextParagraphID += 1
            for (sentenceIndex, sentence) in paragraph.sentences.enumerated() {
                let sentenceID = nextSentenceID
                nextSentenceID += 1
                var rest = Substring(sentence)
                var pieces: [Substring] = []
                while !rest.isEmpty {
                    let limit = firstUnitCut ? UnitChunker.maxLength : UnitChunker.firstMaxLength
                    firstUnitCut = true
                    let (head, tail) = UnitChunker.split(rest, limit: limit)
                    if !head.isEmpty { pieces.append(head) }
                    rest = tail
                }
                for (index, piece) in pieces.enumerated() {
                    let lastPiece = index == pieces.count - 1
                    queue.append(SynthesisUnit(
                        id: nextUnitID, paragraphID: paragraphID, sentenceID: sentenceID, text: String(piece),
                        endsSentence: lastPiece,
                        endsParagraph: lastPiece && sentenceIndex == paragraph.sentences.count - 1
                    ))
                    nextUnitID += 1
                }
            }
        }
    }

    /// The head (at most `limit` characters, trimmed) and the rest (trimmed).
    static func split(_ text: Substring, limit: Int) -> (Substring, Substring) {
        let trimmed = text.drop(while: \.isWhitespace)
        guard trimmed.count > limit else { return (trimmed.trimmingTrailingWhitespace, "") }
        let windowEnd = trimmed.index(trimmed.startIndex, offsetBy: limit)
        // The last break inside the window: before whitespace, or after pause punctuation.
        var index = windowEnd
        while index > trimmed.startIndex {
            let previous = trimmed.index(before: index)
            let character = trimmed[previous]
            if character.isWhitespace, previous > trimmed.startIndex {
                return (trimmed[..<previous].trimmingTrailingWhitespace, trimmed[previous...].drop(while: \.isWhitespace))
            }
            if pauseCharacters.contains(character) {
                return (trimmed[..<index], trimmed[index...].drop(while: \.isWhitespace))
            }
            index = previous
        }
        // No break: hard split at the grapheme boundary at the limit (a Swift Character is a grapheme cluster).
        return (trimmed[..<windowEnd], trimmed[windowEnd...])
    }
}

extension Substring {
    var trimmingTrailingWhitespace: Substring {
        var end = endIndex
        while end > startIndex, self[index(before: end)].isWhitespace { end = index(before: end) }
        return self[startIndex..<end]
    }
}
