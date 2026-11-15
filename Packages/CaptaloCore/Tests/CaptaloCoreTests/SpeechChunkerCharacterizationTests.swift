import Testing
@testable import CaptaloCore

/// Characterization of the inherited chunker (baseline §4). Phase 3 replaces
/// the chunker with `UnitChunker`; these tests then change deliberately.
@Suite struct SpeechChunkerCharacterizationTests {
    /// Builds a sentence of exactly `length` characters ending with `end`.
    static func sentence(_ length: Int, seed: Character = "a", end: Character = ".") -> String {
        precondition(length >= 2)
        var words: [String] = []
        var used = 0
        // Words of 4 letters separated by spaces, then pad, then the end mark.
        while used + 5 < length - 1 {
            words.append(String(repeating: seed, count: 4))
            used += 5
        }
        var body = words.joined(separator: " ")
        if body.isEmpty { body = String(seed) }
        let pad = length - 1 - body.count
        if pad > 0 { body += String(repeating: seed, count: pad) }
        let result = body + String(end)
        precondition(result.count == length, "\(result.count) != \(length)")
        return "W" + result.dropFirst()
    }

    @Test func firstChunkTargets45To110Characters() {
        // A 42-character first sentence is below the 45-character first-chunk
        // minimum, so it joins the next sentence (73 characters in total).
        let s1 = Self.sentence(42, seed: "b")
        let s2 = Self.sentence(30, seed: "c")
        let s3 = Self.sentence(60, seed: "d")
        let chunks = SpeechChunker.chunks(from: "\(s1) \(s2) \(s3)")
        #expect(chunks.first == "\(s1) \(s2)")
        #expect(chunks.first.map { (45...110).contains($0.count) } == true)

        // A first sentence of 50 characters flushes on its own.
        let t1 = Self.sentence(50, seed: "e")
        let t2 = Self.sentence(60, seed: "f")
        #expect(SpeechChunker.chunks(from: "\(t1) \(t2)").first == t1)
    }

    @Test func longFirstSentenceSplitsAtWordBoundaryWithin110() {
        // 150 characters, no commas: the first chunk is cut at the last word
        // that fits in 110 characters, and the rest starts the next chunk.
        let long = Self.sentence(150, seed: "g")
        let chunks = SpeechChunker.chunks(from: long)
        #expect(chunks.count == 2)
        #expect(chunks[0].count <= 110)
        #expect(chunks[0].count > 100)
        #expect(chunks.joined(separator: " ") == long)
    }

    @Test func laterSentenceOver240SplitsAtWordsWithin240() {
        let first = Self.sentence(50, seed: "a")
        let long = Self.sentence(300, seed: "h")
        let chunks = SpeechChunker.chunks(from: "\(first) \(long)")
        #expect(chunks.first == first)
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.count <= 240 })
        #expect(chunks.dropFirst().joined(separator: " ") == long)
    }

    @Test func laterChunkMinimumIsExactly80() {
        let first = Self.sentence(50, seed: "a")
        // 41 + 1 + 41 = 83 reaches 80 at the second sentence end.
        let a = (0..<3).map { Self.sentence(41, seed: Character(UnicodeScalar(UInt8(98 + $0)))) }
        #expect(SpeechChunker.chunks(from: ([first] + a).joined(separator: " ")) == [first, a[0...1].joined(separator: " "), a[2]])
        // 39 + 1 + 39 = 79 stays below 80, so a third sentence joins.
        let b = (0..<3).map { Self.sentence(39, seed: Character(UnicodeScalar(UInt8(98 + $0)))) }
        #expect(SpeechChunker.chunks(from: ([first] + b).joined(separator: " ")) == [first, b.joined(separator: " ")])
    }

    @Test func laterChunksFlushAtSentenceEndAbove80() {
        let first = Self.sentence(50, seed: "a")
        let later = (0..<4).map { Self.sentence(30, seed: Character(UnicodeScalar(UInt8(98 + $0)))) }
        let chunks = SpeechChunker.chunks(from: ([first] + later).joined(separator: " "))
        // 30, 61, 92: the chunk flushes at the first sentence end at or above 80.
        #expect(chunks == [first, later[0...2].joined(separator: " "), later[3]])
    }

    @Test func hardLimit240SplitsAtComma() {
        let first = Self.sentence(50, seed: "a")
        // Six comma-terminated phrases of 50 characters, then a final period.
        let phrases = (0..<6).map { index -> String in
            let seed = Character(UnicodeScalar(UInt8(98 + index)))
            let phrase = Self.sentence(50, seed: seed, end: ",")
            // Only the first phrase starts a sentence; the rest continue it.
            return index == 0 ? phrase : phrase.lowercased()
        }
        let long = phrases.joined(separator: " ").dropLast() + "."
        let chunks = SpeechChunker.chunks(from: "\(first) \(long)")
        #expect(chunks.count == 3)
        #expect(chunks[1] == phrases[0...3].joined(separator: " "))
        #expect(chunks[1].hasSuffix(","))
        #expect(chunks[1].count <= 240)
        #expect(chunks.allSatisfy { $0.count <= 240 })
    }

    /// Recorded: the explicit newline rule has no observable effect, because
    /// phrase splitting on whitespace already joins lines with single spaces.
    @Test func newlinesBecomeSpaces() {
        #expect(SpeechChunker.chunks(from: "Hello\nworld.") == ["Hello world."])
    }

    @Test func spaceInsertedAfterPeriodBeforeUppercase() {
        #expect(SpeechChunker.chunks(from: "We finish.But we start again.") == ["We finish. But we start again."])
    }

    /// Recorded behavior, not intent: the inherited comment says decimals are
    /// untouched, but the rule also matches a digit after the full stop.
    @Test func decimalAfterPeriodAlsoGetsSpace() {
        #expect(SpeechChunker.chunks(from: "Version 3.5 is out.") == ["Version 3. 5 is out."])
    }

    @Test func singleTokenOver240StaysWhole() {
        let token = String(repeating: "x", count: 300)
        #expect(SpeechChunker.chunks(from: token) == [token])
        let first = Self.sentence(50, seed: "a")
        #expect(SpeechChunker.chunks(from: "\(first) \(token)") == [first, token])
    }
}
