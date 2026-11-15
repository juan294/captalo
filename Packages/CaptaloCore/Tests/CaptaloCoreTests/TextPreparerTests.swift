import Testing
@testable import CaptaloCore

/// Positive and negative fixture per cleanup rule (owner decision 7).
@Suite struct TextPreparerTests {
    func spoken(_ text: String, source: TextSource = .selection) -> [[String]] {
        let blocks: [Block] = source == .selection ? Array(TextPreparer.blocks(fromSelection: text)) : [.paragraph(text)]
        return TextPreparer.prepare(blocks, source: source).map(\.sentences)
    }

    func flat(_ text: String, source: TextSource = .selection) -> String {
        spoken(text, source: source).flatMap { $0 }.joined(separator: " ")
    }

    @Test func markdownEmphasisNotSpoken() {
        #expect(flat("**Hello there**") == "Hello there") // upstream issue 5
        #expect(flat("A *word* and __strong__ and ~~gone~~ text.") == "A word and strong and gone text.")
        #expect(flat("Use `make verify` first.") == "Use make verify first.")
    }

    @Test func operatorsAndIdentifiersStay() {
        #expect(flat("a * b = c") == "a * b = c")
        #expect(flat("x -> y and a > b") == "x -> y and a > b")
        #expect(flat("call snake_case_name now") == "call snake_case_name now")
        #expect(flat("a && b || c") == "a && b || c")
    }

    @Test func headingsQuotesAndBulletsAreRemoved() {
        #expect(spoken("# Title\nBody text.") == [["Title"], ["Body text."]])
        #expect(flat("> quoted line") == "quoted line")
        #expect(spoken("Intro.\n- first item\n- second item\n1. numbered") == [["Intro."], ["first item"], ["second item"], ["numbered"]])
        #expect(flat("5 - 3 is two") == "5 - 3 is two")
    }

    @Test func promptAtLineStartOnly() {
        #expect(flat("$ ls -la") == "ls -la")
        #expect(flat("It costs $5 today") == "It costs $5 today")
        #expect(flat("% make test") == "make test")
        #expect(flat("100 % sure") == "100 % sure")
    }

    @Test func urlsBecomeHostNames() {
        #expect(flat("See https://www.example.com/a/b?c=1 now.") == "See example.com now.")
        #expect(flat("Read [the docs](https://example.com/x) today.") == "Read the docs today.")
        #expect(flat("example.com stays as written") == "example.com stays as written")
    }

    @Test func terminalNoiseIsRemoved() {
        #expect(flat("\u{1B}[31mred\u{1B}[0m text") == "red text")
        #expect(flat("│ cell │ ─────") == "cell")
        #expect(flat("before\n========\nafter") == "before after")
        #expect(flat("a-b and x--y stay") == "a-b and x--y stay")
    }

    @Test func pathsAndHashesStayAsWritten() {
        #expect(flat("Open /usr/local/bin/swift and commit a3f9c2e1.") == "Open /usr/local/bin/swift and commit a3f9c2e1.")
    }

    @Test func hyphenRejoinOnlyForOCR() {
        #expect(flat("infor-\nmation", source: .ocr) == "information")
        #expect(flat("well-\nknown") == "well- known")
        #expect(flat("Paris-\nLondon", source: .ocr) == "Paris- London")
    }

    @Test func tableRowsReadInRowOrder() {
        // Upstream issue 1: a Markdown table is read row by row.
        let table = "| Name | Age |\n|---|---|\n| Ann | 30 |\n| Bob | 41 |"
        #expect(spoken(table) == [["Name, Age"], ["Ann, 30"], ["Bob, 41"]])
    }

    @Test func codeFencesDropAndCodeLinesStay() {
        let text = "Run this:\n```\nlet x = a * b\n```\nDone."
        #expect(spoken(text) == [["Run this:"], ["let x = a * b"], ["Done."]])
    }

    @Test func normalizesLineEndingsSpacesAndZeroWidth() {
        #expect(flat("one\r\ntwo\u{00A0}three\u{200B}four") == "one two threefour")
    }

    @Test func blockBoundariesAreParagraphs() {
        #expect(spoken("First one. Second one.\n\nThird.") == [["First one.", "Second one."], ["Third."]])
    }

    @Test func emptyResultMeansNothingToSay() {
        #expect(spoken("  \n ──── \n **** ").isEmpty)
    }

    @Test func ocrBlocksKeepTheirKinds() {
        let blocks: [Block] = [.tableRow(["Item", "Price"]), .listItem("- milk"), .paragraph("Total due.")]
        #expect(TextPreparer.prepare(blocks, source: .ocr).map(\.sentences) == [["Item, Price"], ["milk"], ["Total due."]])
    }
}
