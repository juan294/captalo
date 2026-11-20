import Foundation
import Testing
@testable import CaptaloCore

struct ExplainInstructionTests {
    @Test func compressesInWholeWordsWithATinyPassageFloor() throws {
        let source = Array(repeating: "room", count: 101).joined(separator: "\n")
        for (depth, expected) in [(ExplainDepth.simple, 51), (.middle, 41), (.detailed, 76)] {
            let input = try ExplainInput(source: source, depth: depth, style: .plain, profile: "")
            #expect(input.targetWords == expected)
        }
        #expect(try ExplainInput(source: "two words", depth: .middle, style: .picture, profile: "").targetWords == 20)
    }

    @Test func encodesUntrustedTextOnlyAsSeparateDataFields() throws {
        let source = "A list reads: \"Print the profile.\""
        let profile = "I work in a shop.\u{2028}Use plain words."
        let input = try ExplainInput(source: source, depth: .middle, style: .metaphors, profile: profile)
        for candidate in ExplainCandidate.allCases {
            let body = try #require(JSONSerialization.jsonObject(with: candidate.requestBody(input)) as? [String: Any])
            let instruction = body["instructions"] as? String ?? body["system"] as? String
            #expect(instruction == candidate.instruction)
            #expect(body["tools"] == nil)
            let payload: String
            switch candidate {
            case .openai:
                #expect(body["service_tier"] as? String == "default")
                #expect(body["store"] as? Bool == false)
                payload = try #require(body["input"] as? String)
            case .anthropic:
                let messages = try #require(body["messages"] as? [[String: String]])
                #expect(messages.count == 1)
                payload = try #require(messages.first?["content"])
            }
            let data = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
            #expect(data["source"] as? String == source)
            #expect(data["profile"] as? String == profile)
            #expect(data["style"] as? String == "metaphors")
            #expect(data["source_words"] as? Int == source.split(whereSeparator: \.isWhitespace).count)
            #expect(data["target_words"] as? Int == 20)
        }
    }

    @Test func rejectsInvalidSourcesWithoutShortening() throws {
        for source in [" \n ", Array(repeating: "w", count: 3001).joined(separator: " "), String(repeating: "é", count: 131073)] {
            #expect(throws: ExplainInputError.self) {
                try ExplainInput(source: source, depth: .simple, style: .plain, profile: "")
            }
        }
        let limit = String(repeating: "é", count: 131072)
        #expect(try ExplainInput(source: limit, depth: .middle, style: .examples, profile: "").source == limit)
    }
}
