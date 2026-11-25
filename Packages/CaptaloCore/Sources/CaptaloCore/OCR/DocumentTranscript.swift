import CoreGraphics

/// One recognized container, independent of Vision. Bounds are normalized
/// to the image (0...1), top-left origin, y down.
public struct TranscriptItem: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case paragraph(String)
        case list([String])
        case table([[String]])
    }

    public let content: Content
    public let bounds: CGRect

    public init(_ content: Content, bounds: CGRect) {
        self.content = content
        self.bounds = bounds
    }
}

/// Reading order and structure for OCR (plan phase 5, unit 5B): items that
/// span most of the width split the page into bands; within a band, columns
/// read left to right and top to bottom. Tables stay row blocks and list
/// items stay list blocks, so cleanup never flattens them. Vision's tables
/// differ by macOS version, so two layouts are decided here: a table of prose
/// only is a page of columns, and an aligned grid beside short labels is a table.
public enum DocumentTranscript {
    /// Items at least this wide (fraction of the image) span all columns.
    static let fullWidth: CGFloat = 0.6
    /// A paragraph this much inside a table or list repeats its text and is dropped.
    static let containedFraction: CGFloat = 0.9
    /// A paragraph with a cell's own words repeats it when at least this much of it lies in the table.
    static let repeatedFraction: CGFloat = 0.5
    /// A table cell with at least this many words is prose (the measured page has 18 to 23).
    static let proseWords = 15
    /// A header cell has fewer words than this.
    static let headerWords = 8
    /// A grid label has at most this many words, and a grid at least this many rows.
    static let labelWords = 4
    static let gridRows = 3
    /// Cells of one grid column start within this fraction of the image width.
    static let columnAlignment: CGFloat = 0.03

    public static func blocks(_ items: [TranscriptItem]) -> [Block] {
        ordered(items).flatMap(blocks(for:))
    }

    static func ordered(_ raw: [TranscriptItem]) -> [TranscriptItem] {
        let structures = raw.filter { if case .paragraph = $0.content { false } else { true } }
        let items = raw.filter { item in
            guard case let .paragraph(text) = item.content else { return true }
            return !structures.contains { contained(item.bounds, in: $0.bounds) || repeats(text, item.bounds, of: $0) }
        }
        guard let (grid, others) = grid(in: items) else { return banded(items) }
        func isBeside(_ item: TranscriptItem) -> Bool {
            item.bounds.minY < grid.bounds.maxY && item.bounds.maxY > grid.bounds.minY
        }
        let beside = others.filter(isBeside)
        let away = others.filter { !isBeside($0) }
        // A grid that spans more than one column splits the page as a wide item does, and the text
        // beside it keeps its column. Any other grid is one more item of its column.
        let spanned = columns(away.filter { $0.bounds.width < fullWidth }).filter { column in
            column.contains { $0.bounds.minX < grid.bounds.maxX && $0.bounds.maxX > grid.bounds.minX }
        }
        guard spanned.count > 1 else { return banded(others + [grid], neverWide: grid) }
        return banded(away.filter { $0.bounds.midY < grid.bounds.minY }) + banded(beside + [grid], neverWide: grid)
            + banded(away.filter { $0.bounds.midY >= grid.bounds.minY })
    }

    static func banded(_ items: [TranscriptItem], neverWide: TranscriptItem? = nil) -> [TranscriptItem] {
        func isWide(_ item: TranscriptItem) -> Bool { item.bounds.width >= fullWidth && item != neverWide }
        let wide = items.filter(isWide).sorted { $0.bounds.minY < $1.bounds.minY }
        var result: [TranscriptItem] = []
        var bandTop: CGFloat = -.infinity
        for divider in wide + [nil] {
            let bandBottom = divider?.bounds.minY ?? .infinity
            let band = items.filter { !isWide($0) && $0.bounds.midY >= bandTop && $0.bounds.midY < bandBottom }
            result += columns(band).flatMap { $0.sorted { $0.bounds.minY < $1.bounds.minY } }
            if let divider {
                result.append(divider)
                // Bands partition the page: narrow items beside a divider read after it.
                bandTop = divider.bounds.minY
            }
        }
        return result
    }

    /// Groups items whose horizontal extents overlap, ordered left to right.
    static func columns(_ items: [TranscriptItem]) -> [[TranscriptItem]] {
        var groups: [(range: ClosedRange<CGFloat>, items: [TranscriptItem])] = []
        for item in items.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            let range = item.bounds.minX...item.bounds.maxX
            if let index = groups.firstIndex(where: { $0.range.overlaps(range) }) {
                let merged = min(groups[index].range.lowerBound, range.lowerBound)...max(groups[index].range.upperBound, range.upperBound)
                groups[index].range = merged
                groups[index].items.append(item)
            } else {
                groups.append((range, [item]))
            }
        }
        return groups.sorted { $0.range.lowerBound < $1.range.lowerBound }.map(\.items)
    }

    /// Vision on macOS 26 does not report a borderless table whose cells are sentences. Short labels
    /// down the left, each with the same cells beside it and a sentence in every row below the first,
    /// become one table. Returns the table and the items outside it, or nil.
    static func grid(in items: [TranscriptItem]) -> (grid: TranscriptItem, others: [TranscriptItem])? {
        let cells = items.enumerated().compactMap { index, item -> GridCell? in
            guard case let .paragraph(text) = item.content else { return nil }
            return GridCell(index: index, text: text, words: wordCount(text), bounds: item.bounds)
        }
        let byTop = cells.sorted { $0.bounds.minY < $1.bounds.minY }
        let labels = cells.filter { $0.words <= labelWords }.sorted { $0.bounds.minX < $1.bounds.minX }
        var next = 0
        while next < labels.count {
            // One try for each left edge: the labels that start close to the leftmost one left.
            let edge = labels[next].bounds.minX + columnAlignment
            let end = labels[next...].firstIndex { $0.bounds.minX > edge } ?? labels.endIndex
            let column = labels[next..<end]
            next = end
            guard column.count >= gridRows else { continue }
            let rows = column.map { [$0] + $0.cellsBeside(byTop) }
                .filter { $0.count > 1 }
                .sorted { $0[0].bounds.minY < $1[0].bounds.minY }
            let used = rows.flatMap { $0.map(\.index) }
            guard rows.count >= gridRows, Set(used).count == used.count,
                  rows.allSatisfy({ aligned($0, with: rows[0]) }),
                  rows.dropFirst().allSatisfy({ $0.contains { $0.words > labelWords } }) else { continue }
            let area = rows.joined().reduce(rows[0][0].bounds) { $0.union($1.bounds) }
            let taken = Set(used)
            let others = items.enumerated().filter { !taken.contains($0.offset) }.map(\.element)
            guard !others.contains(where: { area.intersects($0.bounds) }) else { continue }
            return (TranscriptItem(.table(rows.map { $0.map(\.text) }), bounds: area), others)
        }
        return nil
    }

    struct GridCell {
        let index: Int
        let text: String
        let words: Int
        let bounds: CGRect

        /// The cells to the right that start at the same height (within half of the lower one), left to right.
        func cellsBeside(_ byTop: [GridCell]) -> [GridCell] {
            let reach = bounds.height / 2
            var low = 0, high = byTop.count
            while low < high {
                let middle = (low + high) / 2
                if byTop[middle].bounds.minY < bounds.minY - reach { low = middle + 1 } else { high = middle }
            }
            return byTop[low...].prefix { $0.bounds.minY <= bounds.minY + reach }
                .filter {
                    $0.bounds.minX > bounds.maxX
                        && abs($0.bounds.minY - bounds.minY) <= min($0.bounds.height, bounds.height) / 2
                }
                .sorted { $0.bounds.minX < $1.bounds.minX }
        }
    }

    static func aligned(_ row: [GridCell], with first: [GridCell]) -> Bool {
        row.count == first.count && zip(row, first).allSatisfy { abs($0.bounds.minX - $1.bounds.minX) <= columnAlignment }
    }

    /// The paragraphs of a page that Vision reported as a table (aligned prose in columns, macOS 26),
    /// column by column. Nil for a table: it has a header row, or a column that is not prose.
    static func pageColumns(_ rows: [[String]]) -> [String]? {
        guard let width = rows.first?.count, width > 1, rows.allSatisfy({ $0.count == width }) else { return nil }
        guard rows[0].contains(where: { wordCount($0) >= headerWords }) else { return nil }
        let columns = (0..<width).map { column in rows.map { $0[column] }.filter { wordCount($0) > 0 } }
        // Prose has at most one short paragraph (a subheading, a last line) in three.
        let isProse = columns.allSatisfy { column in
            let short = column.count { wordCount($0) < proseWords }
            return short < column.count && short <= max(1, column.count / 3)
        }
        return isProse ? columns.flatMap(\.self) : nil
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// A paragraph that lies mostly in a table or list and has the words of one of its cells: Vision's
    /// table can be narrower than its own text.
    static func repeats(_ text: String, _ bounds: CGRect, of structure: TranscriptItem) -> Bool {
        guard overlap(bounds, with: structure.bounds) >= repeatedFraction else { return false }
        let words = text.split(whereSeparator: \.isWhitespace)
        let cells: [String] = switch structure.content {
        case .paragraph: []
        case let .list(items): items
        case let .table(rows): rows.flatMap(\.self)
        }
        return cells.contains { $0.split(whereSeparator: \.isWhitespace) == words }
    }

    static func contained(_ inner: CGRect, in outer: CGRect) -> Bool {
        overlap(inner, with: outer) >= containedFraction
    }

    /// The fraction of `inner` that lies in `outer`.
    static func overlap(_ inner: CGRect, with outer: CGRect) -> CGFloat {
        let shared = inner.intersection(outer)
        guard !shared.isNull, inner.width > 0, inner.height > 0 else { return 0 }
        return (shared.width * shared.height) / (inner.width * inner.height)
    }

    static func blocks(for item: TranscriptItem) -> [Block] {
        switch item.content {
        case let .paragraph(text): [.paragraph(text)]
        case let .list(items): items.map { .listItem($0) }
        case let .table(rows): pageColumns(rows)?.map { .paragraph($0) } ?? rows.map { .tableRow($0) }
        }
    }
}
