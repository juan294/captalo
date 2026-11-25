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

    /// A sidebar beside a wide paragraph is still read (after the paragraph).
    @Test func narrowItemBesideWideItemIsKept() {
        let body = paragraph("Body text.", 0.02, 0.2, 0.66, 0.3)
        let side = paragraph("Sidebar.", 0.72, 0.3, 0.26, 0.05)
        #expect(DocumentTranscript.blocks([side, body]) == [.paragraph("Body text."), .paragraph("Sidebar.")])
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

    /// macOS 27 reports a table that is narrower than the text in its cells (x 0.03 to 0.77, cell text to 0.90).
    @Test func aCellWiderThanItsTableIsNotRepeated() {
        let definition = "The stone edge where the ferry ties up and the carts wait for the crates."
        let table = TranscriptItem(.table([["Quay", definition], ["Valve", "Glass."]]), bounds: CGRect(x: 0.03, y: 0.07, width: 0.74, height: 0.64))
        let list = TranscriptItem(.list(["Bring cash."]), bounds: CGRect(x: 0.03, y: 0.8, width: 0.2, height: 0.05))
        let items = [table, list, paragraph(definition.replacingOccurrences(of: " ferry", with: "\nferry"), 0.26, 0.12, 0.64, 0.06),
                     paragraph("Bring cash.", 0.05, 0.8, 0.3, 0.05)]
        #expect(DocumentTranscript.blocks(items) == [.tableRow(["Quay", definition]), .tableRow(["Valve", "Glass."]), .listItem("Bring cash.")])
    }

    /// The same words elsewhere on the page, or other words that overlap the table, are still read.
    @Test func textThatIsNotTheTablesOwnIsKept() {
        let table = TranscriptItem(.table([["Quay", "Edge"], ["Valve", "Glass"]]), bounds: CGRect(x: 0.05, y: 0.3, width: 0.5, height: 0.2))
        #expect(DocumentTranscript.blocks([table, paragraph("Quay", 0.05, 0.7, 0.1, 0.05)]).last == .paragraph("Quay"))
        #expect(DocumentTranscript.blocks([table, paragraph("A note in the margin", 0.45, 0.35, 0.4, 0.05)]).last == .paragraph("A note in the margin"))
    }

    @Test func blocksFeedTextPreparationWithoutFlattening() {
        let table = TranscriptItem(.table([["Name", "Age"], ["Ann", "30"]]), bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2))
        let paragraphs = Array(TextPreparer.prepare(DocumentTranscript.blocks([table]), source: .ocr).map(\.sentences))
        #expect(paragraphs == [["Name, Age"], ["Ann, 30"]])
    }

    // MARK: Layouts measured with Vision on macOS 26.7.2 (2026-11-25)

    // The words of Fixtures/ocr-two-column.png: 15 to 22 for each paragraph.
    let alpha = "Alpha. The market opens at six, an hour before the first ferry leaves the quay and the bakers arrive with their carts."
    let bravo = "Bravo. Marta has run the vegetable stall for nineteen years and keeps a small notebook in her apron pocket."
    let charlie = "Charlie. By noon the square is crowded, and the fishmonger tells the same joke to everyone who will listen."
    let delta = "Delta. Behind the market two friends repair old radios on a bench covered with valves, screws and wire."
    let echo = "Echo. The last ferry leaves at six in the evening, and the captain still enjoys the slow turn into the harbour."

    func table(_ rows: [[String]]) -> TranscriptItem {
        TranscriptItem(.table(rows), bounds: CGRect(x: 0.05, y: 0.13, width: 0.9, height: 0.68))
    }

    func isRows(_ rows: [[String]]) -> Bool {
        DocumentTranscript.blocks([table(rows)]) == rows.map { .tableRow($0) }
    }

    /// macOS 26 reports aligned prose blocks in two columns as a table; macOS 27 reports paragraphs.
    @Test func proseColumnsReportedAsATableReadColumnByColumn() {
        let title = paragraph("Notes from the harbour market", 0.05, 0.06, 0.38, 0.04)
        #expect(DocumentTranscript.blocks([table([[alpha, delta], [bravo, echo], [charlie, ""]]), title]) == [
            .paragraph("Notes from the harbour market"), .paragraph(alpha), .paragraph(bravo), .paragraph(charlie),
            .paragraph(delta), .paragraph(echo),
        ])
    }

    /// A subheading or a short last paragraph does not make a page a table.
    @Test func aShortParagraphInAProseColumnReadsWithItsColumn() {
        #expect(DocumentTranscript.blocks([table([[alpha, delta], [bravo, "He laughed."]])]) == [
            .paragraph(alpha), .paragraph(bravo), .paragraph(delta), .paragraph("He laughed."),
        ])
    }

    @Test func proseTablesWithAHeaderOrLabelsKeepTheirRows() {
        #expect(isRows([["What people ask", "What we answer"], [alpha, delta], [bravo, echo], [charlie, delta]]), "header row")
        #expect(isRows([["North", alpha], ["South", bravo], ["West", charlie]]), "label column")
        #expect(isRows([[alpha, "North"], [bravo, "South"], [charlie, "West"]]), "label column at the right")
        #expect(isRows([["How do I pay on the ferry?", alpha], ["When does the last ferry leave?", echo]]), "questions are not prose")
        #expect(isRows([["", "What we answer"], [alpha, delta], [bravo, echo]]), "header with an empty corner")
    }

    @Test func tablesOfShortSentencesKeepTheirRows() {
        // Nine to twelve words for each cell: a ruled list of questions and answers.
        #expect(isRows([["Can I bring a bicycle on the ferry in the summer?", "Yes, if there is room on deck after the cars."],
                        ["Where do I buy a ticket when the kiosk is closed?", "Pay the crew on board, in cash or by card."]]))
    }

    @Test func proseTablesThatAreNotColumnsKeepTheirRows() {
        // One column, an uneven row, no text at all, and no text in one column.
        for rows in [[[alpha], [bravo]], [[alpha, delta], [bravo]], [["", ""], ["", ""]], [[alpha, ""], [bravo, ""]]] {
            #expect(isRows(rows))
        }
    }

    @Test func proseStartsAtFifteenWords() {
        let fifteen = "Fifteen words are enough here to count as the prose of a page of columns"
        let fourteen = "Fourteen words are too few here to count as prose of a page column"
        #expect(fifteen.split(separator: " ").count == 15 && fourteen.split(separator: " ").count == 14)
        #expect(!isRows([[fifteen, fifteen], [fifteen, fifteen]]))
        #expect(isRows([[fourteen, fifteen], [fourteen, fifteen]]))
    }

    /// macOS 26 does not report a borderless table of terms; macOS 27 does.
    @Test func termsBesideDefinitionsReadRowByRow() {
        let items = [
            paragraph("Quay", 0.05, 0.12, 0.05, 0.05), paragraph("Valve", 0.05, 0.38, 0.06, 0.04), paragraph("Stall", 0.05, 0.63, 0.05, 0.05),
            paragraph("The stone edge where the ferry ties up.", 0.26, 0.12, 0.64, 0.05),
            paragraph("A glass part of an old radio.", 0.26, 0.37, 0.52, 0.06),
            paragraph("A table with a roof.", 0.27, 0.63, 0.47, 0.06),
        ]
        #expect(DocumentTranscript.blocks(items) == [
            .tableRow(["Quay", "The stone edge where the ferry ties up."]), .tableRow(["Valve", "A glass part of an old radio."]),
            .tableRow(["Stall", "A table with a roof."]),
        ])
    }

    func borderless() -> [TranscriptItem] {
        [
            paragraph("Ferry", 0.07, 0.14, 0.05, 0.05), paragraph("North", 0.07, 0.25, 0.04, 0.04), paragraph("South", 0.07, 0.53, 0.05, 0.03),
            paragraph("Times", 0.28, 0.14, 0.06, 0.04), paragraph(alpha, 0.27, 0.25, 0.31, 0.09), paragraph(bravo, 0.27, 0.53, 0.28, 0.08),
            paragraph("Payment", 0.61, 0.14, 0.10, 0.05), paragraph(delta, 0.61, 0.25, 0.26, 0.08), paragraph(echo, 0.61, 0.53, 0.26, 0.08),
        ]
    }

    @Test func borderlessTableWithLabelsReadsRowByRow() {
        #expect(DocumentTranscript.blocks(borderless()) == [
            .tableRow(["Ferry", "Times", "Payment"]), .tableRow(["North", alpha, delta]), .tableRow(["South", bravo, echo]),
        ])
    }

    @Test func textAroundABorderlessTableKeepsItsPlace() {
        let items = [paragraph("After the table.", 0.07, 0.8), paragraph("Before the table.", 0.07, 0.03)] + borderless()
        let blocks = DocumentTranscript.blocks(items)
        #expect(blocks.first == .paragraph("Before the table."))
        #expect(blocks.last == .paragraph("After the table."))
        #expect(blocks.count == 5)
    }

    /// Each change breaks one property of the grid, so the columns are read down as before.
    @Test func alignedTextThatIsNotAGridReadsColumnByColumn() {
        func columnOrder(_ items: [TranscriptItem]) -> Bool {
            !DocumentTranscript.blocks(items).contains { if case .tableRow = $0 { true } else { false } }
        }
        #expect(columnOrder(borderless().filter { $0.bounds.minY < 0.5 }), "two rows are not a table")
        var long = borderless()
        long[1] = paragraph("North pier and south pier", 0.07, 0.25, 0.04, 0.04)
        #expect(columnOrder(long), "a label has at most four words")
        var shifted = borderless()
        shifted[4] = paragraph(alpha, 0.27, 0.29, 0.31, 0.09)
        #expect(columnOrder(shifted), "cells of a row start at the same height")
        var missing = borderless()
        missing.remove(at: 8)
        #expect(columnOrder(missing), "every row has the same columns")
        var indented = borderless()
        indented[4] = paragraph(alpha, 0.36, 0.25, 0.22, 0.09)
        #expect(columnOrder(indented), "cells of a column start at the same place")
        #expect(columnOrder(borderless() + [paragraph("A stray line.", 0.3, 0.42, 0.2, 0.03)]), "nothing else lies inside the grid")
        var shared = borderless()
        shared.append(paragraph("Dock", 0.07, 0.255, 0.05, 0.04))
        #expect(columnOrder(shared), "two labels never share a cell")
    }

    @Test func pagesThatMacOS26AndLaterReportAsParagraphsKeepTheirColumns() {
        let three = [paragraph(alpha, 0.03, 0.11, 0.28, 0.32), paragraph(delta, 0.36, 0.11, 0.28, 0.32), paragraph(echo, 0.69, 0.11, 0.28, 0.24)]
        #expect(DocumentTranscript.blocks(three) == [.paragraph(alpha), .paragraph(delta), .paragraph(echo)])
        let ragged = [paragraph(alpha, 0.04, 0.07, 0.44, 0.2), paragraph(bravo, 0.04, 0.47, 0.43, 0.17),
                      paragraph(delta, 0.51, 0.07, 0.44, 0.17), paragraph(echo, 0.51, 0.36, 0.44, 0.2)]
        #expect(DocumentTranscript.blocks(ragged) == [.paragraph(alpha), .paragraph(bravo), .paragraph(delta), .paragraph(echo)])
    }

    /// Cards: a short heading above each column of prose is not a label column.
    @Test func headingsAboveColumnsStayWithTheirColumn() {
        let items = [
            paragraph("First", 0.05, 0.1, 0.1, 0.04), paragraph(alpha, 0.05, 0.2, 0.4, 0.1), paragraph(bravo, 0.05, 0.4, 0.4, 0.1),
            paragraph("Second", 0.55, 0.1, 0.1, 0.04), paragraph(delta, 0.55, 0.2, 0.4, 0.1), paragraph(echo, 0.55, 0.4, 0.4, 0.1),
        ]
        #expect(DocumentTranscript.blocks(items) == [
            .paragraph("First"), .paragraph(alpha), .paragraph(bravo), .paragraph("Second"), .paragraph(delta), .paragraph(echo),
        ])
    }

    /// Two short lists beside each other, with one long line each: every row needs a sentence.
    @Test func independentShortColumnsStayColumns() {
        let pros = ["Pros", "Fast on long files", "Cheap to run", "Easy to repair"]
        let cons = ["Cons", "Loud when the machine is busy all day", "Heavy", "Sold in only one colour this year"]
        let items = (0..<4).flatMap { row in
            [paragraph(pros[row], 0.05, 0.1 + CGFloat(row) * 0.15, 0.2, 0.04), paragraph(cons[row], 0.55, 0.1 + CGFloat(row) * 0.15, 0.3, 0.04)]
        }
        #expect(DocumentTranscript.blocks(items) == (pros + cons).map { .paragraph($0) })
    }

    /// Text without spaces counts as one word; it must not turn a page of columns into rows.
    @Test func columnsWithoutSpacesStayColumns() {
        let items = (0..<3).flatMap { row in
            [paragraph("左\(row)", 0.05, 0.1 + CGFloat(row) * 0.25, 0.4, 0.1), paragraph("右\(row)", 0.55, 0.1 + CGFloat(row) * 0.25, 0.4, 0.1)]
        }
        #expect(DocumentTranscript.blocks(items) == ["左0", "左1", "左2", "右0", "右1", "右2"].map { .paragraph($0) })
    }

    func terms(x: CGFloat = 0.05, cellX: CGFloat = 0.26, cellWidth: CGFloat = 0.64) -> [TranscriptItem] {
        ["Quay", "Valve", "Stall"].enumerated().flatMap { row, label in
            [paragraph(label, x, 0.2 + CGFloat(row) * 0.1, 0.05, 0.05), paragraph("\(label) has a definition of some length.", cellX, 0.2 + CGFloat(row) * 0.1, cellWidth, 0.05)]
        }
    }

    let termRows: [Block] = ["Quay", "Valve", "Stall"].map { .tableRow([$0, "\($0) has a definition of some length."]) }

    @Test func aNoteBesideAGridKeepsItsColumn() {
        let left = paragraph("A note at the left edge of the page.", 0.02, 0.22, 0.1, 0.2)
        #expect(DocumentTranscript.blocks([left] + terms(x: 0.2, cellX: 0.3, cellWidth: 0.65)) == [.paragraph("A note at the left edge of the page.")] + termRows)
        let right = paragraph("A note at the right edge of the page.", 0.8, 0.1, 0.15, 0.3)
        #expect(DocumentTranscript.blocks([right] + terms(cellX: 0.2, cellWidth: 0.5)) == termRows + [.paragraph("A note at the right edge of the page.")])
    }

    @Test func columnsBelowAndAboveAGridStayColumns() {
        func columns(_ y: CGFloat, _ name: String) -> [TranscriptItem] {
            [paragraph("LEFT1 in the columns \(name)", 0.05, y, 0.22), paragraph("RIGHT1 in the columns \(name)", 0.32, y, 0.22),
             paragraph("LEFT2 in the columns \(name)", 0.05, y + 0.06, 0.22), paragraph("RIGHT2 in the columns \(name)", 0.32, y + 0.06, 0.22)]
        }
        func order(_ name: String) -> [Block] {
            ["LEFT1", "LEFT2", "RIGHT1", "RIGHT2"].map { .paragraph("\($0) in the columns \(name)") }
        }
        let items = columns(0.6, "below") + terms(cellX: 0.32, cellWidth: 0.2) + columns(0.02, "above")
        #expect(DocumentTranscript.blocks(items) == order("above") + termRows + order("below"))
    }

    /// The order of Vision's items, and equal bounds, never lose or reorder text.
    @Test func gridDoesNotDependOnItemOrderOrUniqueBounds() {
        let expected = DocumentTranscript.blocks(borderless())
        #expect(DocumentTranscript.blocks(borderless().reversed()) == expected)
        let twin = paragraph("Twin", 0.05, 0.9, 0.1, 0.03)
        let blocks = DocumentTranscript.blocks(borderless() + [twin, paragraph("Other", 0.05, 0.9, 0.1, 0.03)])
        #expect(blocks.prefix(3) == expected.prefix(3))
        #expect(Set([blocks[3], blocks[4]].map(\.plainText)) == ["Twin", "Other"])
        var copy = borderless()
        copy.append(paragraph("A copy with a cell's bounds", 0.27, 0.25, 0.31, 0.09))
        #expect(DocumentTranscript.blocks(copy).contains { $0.plainText.contains("A copy with a cell's bounds") })
    }

    /// The limits that the rules state.
    @Test func gridLimits() {
        func rows(label: String, shift: CGFloat) -> Int {
            var items = borderless()
            items[1] = paragraph(label, 0.07 + shift, 0.25, 0.04, 0.04)
            return DocumentTranscript.blocks(items).filter { if case .tableRow = $0 { true } else { false } }.count
        }
        #expect(rows(label: "North pier south pier", shift: 0) == 3, "four words")
        #expect(rows(label: "North", shift: 0.029) == 3, "within three hundredths of the width")
        #expect(rows(label: "North", shift: 0.031) == 0)
    }

    /// A column of many short lines (a file list) is read without a noticeable delay.
    @Test(.timeLimit(.minutes(1))) func largePagesStayFast() {
        let items = (0..<1600).flatMap { row in
            [paragraph("name \(row)", 0.05, CGFloat(row) * 0.0006, 0.2, 0.0004), paragraph("size \(row) kilobytes of text in it", 0.5, CGFloat(row) * 0.0006 + 0.0003, 0.3, 0.0004)]
        }
        let start = ContinuousClock.now
        #expect(DocumentTranscript.blocks(items).count == 3200)
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func aWordThatOnlyTouchesATableIsKept() {
        let prices = TranscriptItem(.table([["Item", "Price"], ["Milk", "1.20"]]), bounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.2))
        #expect(DocumentTranscript.blocks([prices, paragraph("Price", 0.4, 0.262, 0.1, 0.04)]).first == .paragraph("Price"))
    }

    /// A cell starts to the right of its label, not above or inside it.
    @Test func aCellOverItsLabelIsNotBesideIt() {
        var items = terms()
        for row in 0..<3 { items[row * 2] = paragraph(["Quay", "Valve", "Stall"][row], 0.05, 0.2 + CGFloat(row) * 0.1, 0.3, 0.05) }
        #expect(!DocumentTranscript.blocks(items).contains { if case .tableRow = $0 { true } else { false } })
    }

    /// A note beside the last rows only is still beside the grid.
    @Test func aNoteBesideTheLastRowsKeepsItsColumn() {
        let left = paragraph("A note at the left edge of the page.", 0.02, 0.36, 0.1, 0.2)
        let blocks = DocumentTranscript.blocks([left] + terms(x: 0.2, cellX: 0.3, cellWidth: 0.65))
        #expect(blocks == [.paragraph("A note at the left edge of the page.")] + termRows)
    }

    // MARK: Second review

    @Test func aColumnWithManyShortAnswersKeepsItsRows() {
        #expect(isRows([[alpha, "Yes."], [bravo, delta], [charlie, "Agreed."], [echo, delta]]))
        // One short cell in three is a short paragraph; two are answers.
        #expect(!isRows([[alpha, "Yes."], [bravo, delta], [charlie, echo]]))
        #expect(isRows([[alpha, "Yes."], [bravo, delta], [charlie, "No."]]))
    }

    @Test func aHeaderRowHasFewerThanEightWordsInEveryCell() {
        let seven = "A header cell may have seven words"
        let eight = "A cell with eight words is not header"
        #expect(seven.split(separator: " ").count == 7 && eight.split(separator: " ").count == 8)
        #expect(isRows([[seven, seven], [alpha, delta], [bravo, echo]]))
        #expect(!isRows([[eight, seven], [alpha, delta], [bravo, echo]]))
        #expect(!isRows([["Morning", delta], [alpha, echo], [bravo, delta]]))
    }

    /// A left column with prose above a narrow grid, and a right column that ends above the grid.
    @Test func aNarrowGridStaysInItsColumn() {
        let left = paragraph("Prose of the left column above the grid.", 0.05, 0.02, 0.4, 0.1)
        let right = paragraph("Prose of the right column, shorter than the left one.", 0.55, 0.02, 0.4, 0.12)
        let grid = terms(cellX: 0.2, cellWidth: 0.25)
        #expect(DocumentTranscript.blocks([right, left] + grid)
            == [.paragraph("Prose of the left column above the grid.")] + termRows + [.paragraph("Prose of the right column, shorter than the left one.")])
        let below = [paragraph("More prose of the left column below.", 0.05, 0.6, 0.4, 0.1), paragraph("More prose of the right column below.", 0.55, 0.6, 0.4, 0.1)]
        #expect(DocumentTranscript.blocks([right, left] + grid + below)
            == [.paragraph("Prose of the left column above the grid.")] + termRows + [
                .paragraph("More prose of the left column below."),
                .paragraph("Prose of the right column, shorter than the left one."), .paragraph("More prose of the right column below."),
            ])
    }

    @Test func columnsBelowAWideGridWithANoteBesideItStayColumns() {
        let note = paragraph("A note at the left edge.", 0.01, 0.22, 0.1, 0.1)
        let columns = [paragraph("LEFT1 in the columns below", 0.05, 0.6, 0.3), paragraph("RIGHT1 in the columns below", 0.55, 0.6, 0.3),
                       paragraph("LEFT2 in the columns below", 0.05, 0.7, 0.3), paragraph("RIGHT2 in the columns below", 0.55, 0.7, 0.3)]
        #expect(DocumentTranscript.blocks(columns + [note] + terms(x: 0.2, cellX: 0.3, cellWidth: 0.65))
            == [.paragraph("A note at the left edge.")] + termRows
            + ["LEFT1", "LEFT2", "RIGHT1", "RIGHT2"].map { .paragraph("\($0) in the columns below") })
    }

    /// A sidebar of several notes beside a heading and a wide grid stays one column.
    @Test func aSidebarBesideAWideGridIsNotTorn() {
        let notes = ["First note in the sidebar.", "Second note in the sidebar.", "Third note in the sidebar."]
        let sidebar = [paragraph(notes[0], 0.02, 0.02, 0.2, 0.1), paragraph(notes[1], 0.02, 0.25, 0.2, 0.1), paragraph(notes[2], 0.02, 0.7, 0.2, 0.1)]
        let heading = paragraph("Words of the harbour", 0.28, 0.05, 0.3, 0.05)
        #expect(DocumentTranscript.blocks([heading] + terms(x: 0.28, cellX: 0.4, cellWidth: 0.55) + sidebar)
            == notes.map { .paragraph($0) } + [.paragraph("Words of the harbour")] + termRows)
    }

    @Test func twoShortParagraphsInSixStillMakeAPage() {
        let left = [alpha, bravo, charlie, delta, echo, alpha]
        #expect(!isRows([[left[0], "He laughed."], [left[1], delta], [left[2], echo], [left[3], "So did she."], [left[4], alpha], [left[5], bravo]]))
    }

    @Test func aWordThatIsLessThanHalfInsideATableIsKept() {
        let prices = TranscriptItem(.table([["Item", "Price"], ["Milk", "1.20"]]), bounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.2))
        #expect(DocumentTranscript.blocks([prices, paragraph("Price", 0.4, 0.276, 0.1, 0.04)]).first == .paragraph("Price"))
        #expect(DocumentTranscript.blocks([prices, paragraph("Price", 0.4, 0.284, 0.1, 0.04)]) == [.tableRow(["Item", "Price"]), .tableRow(["Milk", "1.20"])])
    }
}
