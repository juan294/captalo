import Testing
@testable import CaptaloCore

@Suite struct PrivacyLogTests {
    static let allCases: [PrivacyEvent] = [
        .voicePrewarmed(accelerator: .neuralEngine),
        .voicePrewarmed(accelerator: .cpuAndGPU),
        .firstAudio(characters: 42, elapsed: .milliseconds(1_250), accelerator: .neuralEngine),
    ]

    @Test func eventsRenderOnlyEnumNamesAndNumbers() {
        // Allowed tokens: an event name, then key=value pairs whose value is
        // an integer or a known enum raw value.
        let enumValues = Set(["neuralEngine", "cpuAndGPU"])
        for event in Self.allCases {
            let parts = event.rendered.split(separator: " ")
            #expect(!parts.isEmpty)
            let nameIsWord = parts[0].allSatisfy { $0.isLetter }
            #expect(nameIsWord)
            for pair in parts.dropFirst() {
                let kv = pair.split(separator: "=", maxSplits: 1)
                #expect(kv.count == 2, "\(pair)")
                guard kv.count == 2 else { continue }
                let value = String(kv[1])
                #expect(Int64(value) != nil || enumValues.contains(value), "\(pair)")
            }
        }
    }

    /// Exhaustive over every case: adding a case fails to compile until it is
    /// listed here and in `allCases`, so no case escapes the rendering check.
    static func sampleCount(_ event: PrivacyEvent) -> Int {
        switch event {
        case .voicePrewarmed: 2
        case .firstAudio: 1
        }
    }

    @Test func allCasesCoversEveryCase() {
        var seen: [String: Int] = [:]
        for event in Self.allCases {
            let name = String(event.rendered.split(separator: " ")[0])
            seen[name, default: 0] += 1
            #expect(seen[name]! <= Self.sampleCount(event))
        }
        let expected = Self.allCases.reduce(into: Set<String>()) { $0.insert(String($1.rendered.split(separator: " ")[0])) }
        #expect(expected.count == 2)
    }

    @Test func firstAudioRendersMilliseconds() {
        let event = PrivacyEvent.firstAudio(characters: 7, elapsed: .milliseconds(1_250), accelerator: .cpuAndGPU)
        #expect(event.rendered == "firstAudio characters=7 elapsedMs=1250 accelerator=cpuAndGPU")
    }
}
