import Foundation
import NaturalLanguage
import Synchronization

/// A structural block of captured text. OCR produces blocks directly; a
/// selection is split into blocks on blank lines, list markers and table rows.
public enum Block: Equatable, Sendable {
    case paragraph(String)
    case listItem(String)
    case tableRow([String])
    case codeLine(String)
}

public enum TextSource: String, Sendable {
    case selection
    case ocr
}

/// One paragraph of speakable sentences. Block boundaries are paragraph
/// boundaries. A cleaned block is split into sentences on demand, one at a
/// time, so a very large paragraph is never segmented ahead of the reading (VAL-05).
public struct Paragraph: Equatable, Sendable {
    private enum Content: Equatable, Sendable {
        case sentences([String])
        /// Cleaned, whitespace-collapsed block text.
        case text(String)
    }

    private let content: Content

    public init(sentences: [String]) {
        content = .sentences(sentences)
    }

    init(text: String) {
        content = .text(text)
    }

    /// Every sentence at once (tests and diagnostics; the reading pipeline
    /// takes them one at a time through `makeSentenceIterator()`).
    public var sentences: [String] { Array(IteratorSequence(makeSentenceIterator())) }

    var isEmpty: Bool {
        switch content {
        case let .sentences(sentences): sentences.isEmpty
        case let .text(text): text.isEmpty
        }
    }

    func makeSentenceIterator() -> SentenceIterator {
        switch content {
        case let .sentences(sentences): .list(sentences.makeIterator())
        case let .text(text): .tokens(TokenizedSentences(text: text))
        }
    }
}

/// Counts sentences the tokenizer produces, so tests can check that a
/// paragraph is segmented on demand. Production never sets `current`.
final class SegmentationCounter: Sendable {
    @TaskLocal static var current: SegmentationCounter?
    private let count = Mutex(0)

    func add() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

/// Sentences of one paragraph, produced on demand.
enum SentenceIterator: IteratorProtocol {
    case list(IndexingIterator<[String]>)
    case tokens(TokenizedSentences)

    mutating func next() -> String? {
        switch self {
        case var .list(iterator):
            defer { self = .list(iterator) }
            return iterator.next()
        case var .tokens(iterator):
            defer { self = .tokens(iterator) }
            return iterator.next()
        }
    }
}

/// Cleaned text through NLTokenizer one sentence at a time (step 6); when it
/// finds no sentence, the whole text is one.
struct TokenizedSentences: IteratorProtocol {
    private let text: String
    private let tokenizer = NLTokenizer(unit: .sentence)
    private var position: String.Index
    private var producedAny = false

    init(text: String) {
        self.text = text
        tokenizer.string = text
        position = text.startIndex
    }

    mutating func next() -> String? {
        while position < text.endIndex {
            let range = tokenizer.tokenRange(at: position)
            // A position outside every sentence advances by one character.
            let token = range.upperBound > position ? text[range] : ""
            position = range.upperBound > position ? range.upperBound : text.index(after: position)
            let sentence = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                producedAny = true
                SegmentationCounter.current?.add()
                return sentence
            }
        }
        guard !producedAny, !text.isEmpty else { return nil }
        producedAny = true
        SegmentationCounter.current?.add()
        return text
    }
}

/// Conservative cleanup (owner decision 7): only markup and noise are removed.
/// Paths, code operators and hashes are spoken as written; URLs become host
/// names; hyphen rejoining applies to OCR text only.
public enum TextPreparer {
    /// Paragraphs, produced lazily one block at a time. Empty when nothing speakable remains.
    public static func prepare<Blocks: Sequence>(_ blocks: Blocks, source: TextSource) -> LazyFilterSequence<LazyMapSequence<Blocks, Paragraph>>
    where Blocks.Element == Block {
        blocks.lazy
            .map { paragraph(from: $0, source: source) }
            .filter { !$0.isEmpty }
    }

    /// Splits selected text into blocks (lazily, line by line).
    public static func blocks(fromSelection text: String) -> SelectionBlocks {
        SelectionBlocks(text: normalizeCharacters(text))
    }

    /// The one text-to-units chain used by the app, the region reader and the
    /// probe: selection text is split into blocks; OCR blocks go straight into
    /// cleanup with the OCR rules; then units.
    public static func units(for content: ReadingContent) -> AnyIterator<SynthesisUnit> {
        AnyIterator(unitIterator(for: content))
    }

    /// The iterator behind `units(for:)`, with its preparation counters (tests).
    static func unitIterator(
        for content: ReadingContent
    ) -> UnitChunker<LazyFilterSequence<LazyMapSequence<AnySequence<Block>, Paragraph>>>.Iterator {
        let (blocks, source): (AnySequence<Block>, TextSource) = switch content {
        case let .text(text): (AnySequence(blocks(fromSelection: text)), .selection)
        case let .document(blocks): (AnySequence(blocks), .ocr)
        }
        return UnitChunker(prepare(blocks, source: source)).makeIterator()
    }

    /// False when cleanup leaves nothing to say: silence, like an empty selection.
    public static func hasSpeakableText(_ content: ReadingContent) -> Bool {
        units(for: content).next() != nil
    }

    // MARK: - Per-block cleanup

    static func paragraph(from block: Block, source: TextSource) -> Paragraph {
        let text: String
        switch block {
        case let .paragraph(raw), let .listItem(raw):
            text = cleanProse(raw, source: source)
        case let .tableRow(cells):
            text = cells.map { cleanProse($0, source: source) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case let .codeLine(raw):
            // Code is spoken as written, minus noise and a line-start prompt symbol.
            text = collapseWhitespace(Pattern.prompt.replace(removeNoise(normalizeCharacters(raw)), ""))
        }
        return Paragraph(text: text)
    }

    static func cleanProse(_ raw: String, source: TextSource) -> String {
        // Not redundant for selection text: normalization is not idempotent
        // (an NBSP or CR joined to a zero-width scalar survives one pass).
        var text = normalizeCharacters(raw)
        if source == .ocr {
            text = Pattern.ocrHyphenBreak.replace(text, "$1$2")
        }
        text = removeNoise(text)
        for marker in [Pattern.headingMark, .quoteMark, .bullet, .numberedBullet, .prompt] {
            text = marker.replace(text, "")
        }
        text = Pattern.markdownLink.replace(text, "$1")
        text = Pattern.url.replace(text, "$1")
        // Asterisk emphasis only: underscores belong to identifiers
        // (`__init__.py`, `snake_case`) far more often than to Markdown.
        text = Pattern.strongEmphasis.replace(text, "$1")
        text = Pattern.emphasis.replace(text, "$1")
        text = Pattern.strike.replace(text, "$1")
        text = Pattern.inlineCode.replace(text, "$1")
        return collapseWhitespace(text)
    }

    /// Step 1: line endings, NBSP and zero-width characters. Text with none
    /// of them is returned as it is (every replacement would be a no-op).
    static func normalizeCharacters(_ text: String) -> String {
        guard needsNormalizing(text) else { return text }
        var result = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        result.unicodeScalars.removeAll { zeroWidth.contains($0) }
        return result
    }

    /// True when `text` holds a scalar that `normalizeCharacters` replaces or drops.
    static func needsNormalizing(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0 == "\r" || $0 == "\u{00A0}" || ($0.value >= 0x200B && zeroWidth.contains($0)) }
    }

    /// Step 3: ANSI sequences, box-drawing runs and separator runs.
    static func removeNoise(_ text: String) -> String {
        var result = Pattern.ansi.replace(text, "")
        result = Pattern.boxDrawing.replace(result, " ")
        return Pattern.separatorRun.replace(result, " ")
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static let zeroWidth: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]
}

/// A compiled ICU pattern (NSRegularExpression is immutable and thread-safe).
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, lines: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: lines ? [.anchorsMatchLines] : [])
    }

    func replace(_ text: String, _ template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static let headingLine = Pattern(#"^#{1,6}\s+\S"#)
    static let listLine = Pattern(#"^(?:[-*+•]|\d{1,3}[.)])\s+\S"#)

    static let ansi = Pattern(#"\x{1B}(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x{07}\x{1B}]*(?:\x{07}|\x{1B}\\)|[@-Z\\-_])"#)
    static let boxDrawing = Pattern(#"[\x{2500}-\x{259F}]+"#)
    static let separatorRun = Pattern(#"[-=_*~]{4,}"#)
    static let headingMark = Pattern(#"^[ \t]{0,3}#{1,6}[ \t]+"#, lines: true)
    static let quoteMark = Pattern(#"^[ \t]{0,3}(?:>[ \t]?)+"#, lines: true)
    static let bullet = Pattern(#"^[ \t]*[-*+•][ \t]+"#, lines: true)
    static let numberedBullet = Pattern(#"^[ \t]*\d{1,3}[.)][ \t]+"#, lines: true)
    static let prompt = Pattern(#"^[ \t]*[$%❯➜›»][ \t]+"#, lines: true)
    static let markdownLink = Pattern(#"!?\[([^\]]*)\]\([^)\s]*\)"#)
    /// Trailing sentence punctuation after a URL stays in the text.
    static let url = Pattern(#"\b(?:https?|ftp)://(?:www\.)?([^/\s:?#]+)\S*?(?=[.,;:!?)\]]*(?:\s|$))"#)
    static let strongEmphasis = Pattern(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    static let emphasis = Pattern(#"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])"#)
    static let strike = Pattern(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    static let inlineCode = Pattern(#"`([^`]+)`"#)
    static let ocrHyphenBreak = Pattern(#"(\p{L})-\n(\p{Ll})"#)
}

/// A lazy split of selected text into blocks: blank lines end paragraphs;
/// list markers and table rows are blocks of their own; code fences
/// delimit code lines and are dropped.
public struct SelectionBlocks: Sequence {
    let text: String

    public func makeIterator() -> Iterator {
        Iterator(lines: Lines(rest: text[...]))
    }

    /// The text's lines, found one at a time (the same lines as splitting
    /// on every newline, empty ones included). A byte search finds them: an
    /// LF byte is a whole "\n" character unless a CR precedes it (CR LF is one
    /// character, which is not a line break here).
    struct Lines {
        var rest: Substring?

        var first: Substring? {
            guard let rest else { return nil }
            let bytes = rest.utf8
            var index = bytes.startIndex
            while let newline = bytes[index...].firstIndex(of: 0x0A) {
                if newline == bytes.startIndex || bytes[bytes.index(before: newline)] != 0x0D {
                    return rest[..<newline]
                }
                index = bytes.index(after: newline)
            }
            return rest
        }

        mutating func popFirst() -> Substring? {
            guard let line = first, let current = rest else { return nil }
            rest = line.endIndex < current.endIndex ? current[current.index(after: line.endIndex)...] : nil
            return line
        }
    }

    public struct Iterator: IteratorProtocol {
        var lines: Lines
        var inFence = false
        var inTable = false
        var pending: Block?

        public mutating func next() -> Block? {
            if let block = pending {
                pending = nil
                return block
            }
            var paragraph: [Substring] = []
            while let line = lines.popFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFence.toggle()
                    inTable = false
                    if let block = flush(&paragraph) { return block }
                    continue
                }
                if inFence {
                    if let block = flush(&paragraph) { pending = .codeLine(String(line)); return block }
                    return .codeLine(String(line))
                }
                if trimmed.isEmpty {
                    inTable = false
                    if let block = flush(&paragraph) { return block }
                    continue
                }
                if let special = special(trimmed) {
                    if let block = flush(&paragraph) {
                        if let special { pending = special }
                        return block
                    }
                    if let special { return special }
                    continue
                }
                inTable = false
                paragraph.append(line)
            }
            return flush(&paragraph)
        }

        /// A line is a table row only inside a Markdown table: it starts with
        /// a pipe, or a separator row follows it (the header), or it follows
        /// a table row. A shell pipeline (`a | b | c`) is prose.
        private mutating func special(_ line: String) -> Block?? {
            if Self.isSeparatorRow(line) {
                inTable = true
                return .some(nil)
            }
            let nextIsSeparator = lines.first.map { Self.isSeparatorRow(String($0)) } ?? false
            if line.contains("|"), line.hasPrefix("|") || inTable || nextIsSeparator {
                inTable = true
                var cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                return .some(.tableRow(cells))
            }
            if Pattern.headingLine.matches(line) {
                return .some(.paragraph(line))
            }
            if Pattern.listLine.matches(line) {
                return .some(.listItem(line))
            }
            return nil
        }

        /// `| --- | :-: |`; surrounding whitespace allowed.
        static func isSeparatorRow(_ line: String) -> Bool {
            line.contains("|") && line.contains("-") && line.allSatisfy { "|-: \t".contains($0) }
        }

        private func flush(_ paragraph: inout [Substring]) -> Block? {
            guard !paragraph.isEmpty else { return nil }
            defer { paragraph.removeAll() }
            return .paragraph(paragraph.joined(separator: "\n"))
        }

    }
}
