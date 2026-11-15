import CoreGraphics
import Testing
@testable import CaptaloCore

@Suite struct DocumentTranscriptTests {
    func paragraph(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 0.4, _ h: CGFloat = 0.05) -> TranscriptItem {
        TranscriptItem(.paragraph(text), bounds: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test func twoColumnsLeftColumnFirst() {
        // Vision may list items row by row across columns; the reader goes down the left column first.
        let items = [paragraph("L1", 0.05, 0.1), paragraph("R1", 0.55, 0.1), paragraph("L2", 0.05, 0.2), paragraph("R2", 0.55, 0.2)]
        #expect(DocumentTranscript.blocks(items) == [.paragraph("L1"), .paragraph("L2"), .paragraph("R1"), .paragraph("R2")])
    }

    @Test func fullWidthTitleAndFooterSplitTheColumns() {
        let items = [
            paragraph("Right", 0.55, 0.3), paragraph("Footer", 0.05, 0.9, 0.9),
            paragraph("Title", 0.05, 0.05, 0.9), paragraph("Left", 0.05, 0.3),
        ]
        #expect(DocumentTranscript.blocks(items) == [.paragraph("Title"), .paragraph("Left"), .paragraph("Right"), .paragraph("Footer")])
    }

    @Test func tableRowsStayRowBlocksInOrder() {
        let table = TranscriptItem(.table([["Item", "Price"], ["Milk", "1.20"], ["Bread", "2.10"]]), bounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.2))
        let items = [paragraph("Total due.", 0.1, 0.6), table, paragraph("Receipt", 0.1, 0.1)]
        #expect(DocumentTranscript.blocks(items) == [
            .paragraph("Receipt"), .tableRow(["Item", "Price"]), .tableRow(["Milk", "1.20"]), .tableRow(["Bread", "2.10"]), .paragraph("Total due."),
        ])
    }

    @Test func listItemsStayListBlocks() {
        let list = TranscriptItem(.list(["milk", "bread"]), bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
        #expect(DocumentTranscript.blocks([list]) == [.listItem("milk"), .listItem("bread")])
    }

    @Test func paragraphsInsideTablesAreNotRepeated() {
        let table = TranscriptItem(.table([["a", "b"]]), bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2))
        let inside = paragraph("a b", 0.15, 0.12, 0.3, 0.05)
        #expect(DocumentTranscript.blocks([table, inside]) == [.tableRow(["a", "b"])])
    }

    @Test func blocksFeedTextPreparationWithoutFlattening() {
        let table = TranscriptItem(.table([["Name", "Age"], ["Ann", "30"]]), bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2))
        let paragraphs = Array(TextPreparer.prepare(DocumentTranscript.blocks([table]), source: .ocr).map(\.sentences))
        #expect(paragraphs == [["Name, Age"], ["Ann, 30"]])
    }
}
