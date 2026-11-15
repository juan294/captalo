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

    static func name(_ event: PrivacyEvent) -> String {
        String(event.rendered.prefix { $0 != " " })
    }

    /// Exhaustive switch: adding a case fails to compile until it is counted
    /// here, and the count must match the names sampled in `allCases`.
    static let caseCount = PrivacyEvent.voicePrewarmed(accelerator: .neuralEngine).arms

    @Test func allCasesCoversEveryCase() {
        #expect(Set(Self.allCases.map(Self.name)).count == Self.caseCount)
    }

    @Test func firstAudioRendersMilliseconds() {
        let event = PrivacyEvent.firstAudio(characters: 7, elapsed: .milliseconds(1_250), accelerator: .cpuAndGPU)
        #expect(event.rendered == "firstAudio characters=7 elapsedMs=1250 accelerator=cpuAndGPU")
    }
}

private extension PrivacyEvent {
    /// The number of cases; the switch has no default.
    var arms: Int {
        switch self {
        case .voicePrewarmed, .firstAudio: 2
        }
    }
}
