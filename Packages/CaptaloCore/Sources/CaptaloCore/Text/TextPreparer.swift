import Foundation
import NaturalLanguage

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

/// One paragraph of speakable sentences. Block boundaries are paragraph boundaries.
public struct Paragraph: Equatable, Sendable {
    public let sentences: [String]

    public init(sentences: [String]) {
        self.sentences = sentences
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
            .filter { !$0.sentences.isEmpty }
    }

    /// Splits selected text into blocks (lazily, line by line).
    public static func blocks(fromSelection text: String) -> SelectionBlocks {
        SelectionBlocks(text: normalizeCharacters(text))
    }

    /// The one text-to-units chain used by the app and the probe: blocks
    /// (selection text is split; OCR text is one paragraph until phase 5),
    /// cleanup, then units.
    public static func units(for text: String, source: TextSource) -> AnyIterator<SynthesisUnit> {
        let blocks = source == .selection ? Array(blocks(fromSelection: text)) : [Block.paragraph(text)]
        return AnyIterator(UnitChunker(prepare(blocks, source: source)).makeIterator())
    }

    /// Units for a committed reading: selection text is split into blocks;
    /// OCR blocks go straight into cleanup with the OCR rules.
    public static func units(for content: ReadingContent) -> AnyIterator<SynthesisUnit> {
        switch content {
        case let .text(text): units(for: text, source: .selection)
        case let .document(blocks): AnyIterator(UnitChunker(prepare(blocks, source: .ocr)).makeIterator())
        }
    }

    /// False when cleanup leaves nothing to say: silence, like an empty selection.
    public static func hasSpeakableText(_ text: String, source: TextSource = .selection) -> Bool {
        units(for: text, source: source).next() != nil
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
        return Paragraph(sentences: sentences(in: text))
    }

    static func cleanProse(_ raw: String, source: TextSource) -> String {
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

    /// Step 1: line endings, NBSP and zero-width characters.
    static func normalizeCharacters(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        result.unicodeScalars.removeAll { zeroWidth.contains($0) }
        return result
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

    /// Step 6: sentences through NLTokenizer within one block.
    static func sentences(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result.isEmpty ? [text] : result
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
        Iterator(lines: text.split(separator: "\n", omittingEmptySubsequences: false)[...])
    }

    public struct Iterator: IteratorProtocol {
        var lines: ArraySlice<Substring>
        var inFence = false
        var inTable = false
        var pending: [Block] = []

        public mutating func next() -> Block? {
            if !pending.isEmpty { return pending.removeFirst() }
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
                    if let block = flush(&paragraph) { pending.append(.codeLine(String(line))); return block }
                    return .codeLine(String(line))
                }
                if trimmed.isEmpty {
                    inTable = false
                    if let block = flush(&paragraph) { return block }
                    continue
                }
                if let special = special(trimmed) {
                    if let block = flush(&paragraph) {
                        if let special { pending.append(special) }
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
