import Testing
@testable import CaptaloCore

@Suite struct UnitChunkerTests {
    func units(_ paragraphs: [[String]]) -> [SynthesisUnit] {
        Array(UnitChunker(paragraphs.map(Paragraph.init(sentences:))))
    }

    /// `count` words of `width` letters separated by single spaces.
    func words(_ count: Int, width: Int = 4, letter: Character = "a") -> String {
        Array(repeating: String(repeating: letter, count: width), count: count).joined(separator: " ")
    }

    @Test func oneUnitPerShortSentence() {
        let result = units([["One.", "Two two.", "Three three three."]])
        #expect(result.map(\.text) == ["One.", "Two two.", "Three three three."])
        #expect(result.map(\.sentenceID) == [0, 1, 2])
        #expect(result.map(\.endsSentence) == [true, true, true])
        #expect(result.map(\.endsParagraph) == [false, false, true])
    }

    @Test func longSentenceSplitAtLastBreakBefore400() {
        // The first unit takes a short sentence so the long one uses the 400 limit.
        let long = words(30) + ", " + words(70) + "."   // 149 + 2 + 349 + 1 = 501 characters
        let result = units([["Short.", long]])
        #expect(result.count == 3)
        #expect(result[1].text.count <= 400)
        #expect(result[1].text.hasSuffix("aaaa") || result[1].text.hasSuffix(","))
        #expect(result[1].sentenceID == result[2].sentenceID)
        #expect(!result[1].endsSentence)
        #expect(result[2].endsSentence)
        #expect((result[1].text + " " + result[2].text) == long)
    }

    @Test func pausePunctuationIsPreferredWhenLast() {
        // A comma at 395 is the last break before 400.
        let head = words(79) + "," // 79*5-1 = 394 + 1 = 395 characters
        let sentence = head + "bbbbbbbbbbbbbbbbbbbb end."
        let result = units([["Short.", sentence]])
        #expect(result[1].text == head)
    }

    @Test func breakExactlyAtTheLimitIsUsed() {
        let head = words(80) // 80*5-1 = 399 characters
        let exact = head + "a" // 400 characters, then a space
        let result = units([["Short.", exact + " tail words here."]])
        #expect(result[1].text == exact)
    }

    @Test func unpunctuatedTextSplitAtWhitespace() {
        let text = words(2_000)  // 9,999 characters, no punctuation
        let result = units([["Short.", text]])
        #expect(result.dropFirst().allSatisfy { $0.text.count <= 400 && !$0.text.hasPrefix(" ") && !$0.text.hasSuffix(" ") })
        #expect(result.dropFirst().allSatisfy { $0.text.split(separator: " ").allSatisfy { $0 == "aaaa" } })
        #expect(result.dropFirst().map(\.text).joined(separator: " ") == text)
    }

    @Test func unbrokenTokenOver400HardSplitAtGraphemeBoundary() {
        let token = String(repeating: "x", count: 1_000)
        let result = units([["Short.", token]])
        #expect(result.dropFirst().map(\.text.count) == [400, 400, 200])
        #expect(result.dropFirst().map(\.text).joined() == token)
    }

    @Test func unbrokenTokenInFirstUnitHardSplitAt160() {
        let token = String(repeating: "y", count: 500)
        let result = units([[token]])
        #expect(result.map(\.text.count) == [160, 340])
    }

    @Test func hardSplitNeverBreaksAGraphemeCluster() {
        // "é" as e + combining acute is one Character of two scalars; the family emoji is one Character of 7.
        let cluster = "e\u{301}"
        let family = "👨‍👩‍👧‍👦"
        let token = String(repeating: cluster, count: 300) + String(repeating: family, count: 300)
        let result = units([["Short.", token]])
        #expect(result.dropFirst().map(\.text).joined() == token)
        for unit in result.dropFirst() {
            #expect(unit.text.count <= 400)
            #expect(unit.text.unicodeScalars.first != "\u{301}")
            #expect(unit.text.unicodeScalars.first != "\u{200D}")
        }
    }

    @Test func firstUnitCappedAt160() {
        let first = words(60) + "."  // 300 characters
        let result = units([[first, "Next."]])
        #expect(result[0].text.count <= 160)
        #expect(result[0].text.count > 150)
        #expect(result[1].text.count <= 400)
        #expect(result[0].sentenceID == result[1].sentenceID)
        #expect(result.last?.text == "Next.")
    }

    @Test func noUnitCrossesParagraph() {
        let result = units([["A one.", "A two."], ["B one."], [words(150) + "."]])
        #expect(result.map(\.paragraphID) == [0, 0, 1, 2, 2])
        #expect(result.filter(\.endsParagraph).map(\.text.first) == ["A", "B", "a"])
        #expect(Set(result.map(\.id)) == Set(0..<result.count))
    }

    @Test func lazyProductionDoesNotPreparePastLookahead() {
        let paragraphs = (0..<10_000).lazy.map { Paragraph(sentences: ["Sentence \($0)."]) }
        var iterator = UnitChunker(paragraphs).makeIterator()
        for _ in 0..<4 { _ = iterator.next() }
        #expect(iterator.paragraphsPulled == 4)
    }
}
