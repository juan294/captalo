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
/// items stay list blocks, so cleanup never flattens them.
public enum DocumentTranscript {
    /// Items at least this wide (fraction of the image) span all columns.
    static let fullWidth: CGFloat = 0.6
    /// A paragraph this much inside a table or list repeats its text and is dropped.
    static let containedFraction: CGFloat = 0.9

    public static func blocks(_ items: [TranscriptItem]) -> [Block] {
        ordered(items).flatMap(blocks(for:))
    }

    static func ordered(_ raw: [TranscriptItem]) -> [TranscriptItem] {
        let structures = raw.filter { if case .paragraph = $0.content { false } else { true } }
        let items = raw.filter { item in
            guard case .paragraph = item.content else { return true }
            return !structures.contains { contained(item.bounds, in: $0.bounds) }
        }
        let wide = items.filter { $0.bounds.width >= fullWidth }.sorted { $0.bounds.minY < $1.bounds.minY }
        var result: [TranscriptItem] = []
        var bandTop: CGFloat = -.infinity
        for divider in wide + [nil] {
            let bandBottom = divider?.bounds.minY ?? .infinity
            let band = items.filter { $0.bounds.width < fullWidth && $0.bounds.midY >= bandTop && $0.bounds.midY < bandBottom }
            result += columns(band).flatMap { $0.sorted { $0.bounds.minY < $1.bounds.minY } }
            if let divider {
                result.append(divider)
                bandTop = divider.bounds.maxY
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
                groups[index] = (merged, groups[index].items + [item])
            } else {
                groups.append((range, [item]))
            }
        }
        return groups.sorted { $0.range.lowerBound < $1.range.lowerBound }.map(\.items)
    }

    static func contained(_ inner: CGRect, in outer: CGRect) -> Bool {
        let overlap = inner.intersection(outer)
        guard !overlap.isNull, inner.width > 0, inner.height > 0 else { return false }
        return (overlap.width * overlap.height) / (inner.width * inner.height) >= containedFraction
    }

    static func blocks(for item: TranscriptItem) -> [Block] {
        switch item.content {
        case let .paragraph(text): [.paragraph(text)]
        case let .list(items): items.map { .listItem($0) }
        case let .table(rows): rows.map { .tableRow($0) }
        }
    }
}
