import CaptaloCore
import CoreGraphics
import Vision

/// `DocumentRecognizer` over Vision's `RecognizeDocumentsRequest` (macOS 26).
/// Cancellation of the calling task cancels the request: Vision returns at
/// once with `requestCancelled` (gate 0, 2026-11-15).
public struct VisionRecognizer: DocumentRecognizer {
    public init() {}

    public func recognize(_ image: CGImage) async throws -> [TranscriptItem] {
        let observations = try await RecognizeDocumentsRequest().perform(on: image)
        return observations.flatMap { Self.items($0.document) }
    }

    /// Paragraphs, lists and tables with bounds normalized to the image,
    /// top-left origin. Reading order is decided by `DocumentTranscript`.
    static func items(_ document: DocumentObservation.Container) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        for paragraph in document.paragraphs {
            items.append(TranscriptItem(.paragraph(paragraph.transcript), bounds: topLeft(paragraph.boundingRegion.boundingBox.cgRect)))
        }
        for list in document.lists {
            items.append(TranscriptItem(.list(list.items.map(\.itemString)), bounds: topLeft(list.boundingRegion.boundingBox.cgRect)))
        }
        for table in document.tables {
            let rows = table.rows.map { row in row.map { $0.content.text.transcript } }
            items.append(TranscriptItem(.table(rows), bounds: topLeft(table.boundingRegion.boundingBox.cgRect)))
        }
        return items
    }

    /// Vision's normalized rectangles have a lower-left origin.
    static func topLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}
