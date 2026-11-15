import Foundation
import Testing
@testable import CaptaloCore

@Suite struct ReadingPreferencesTests {
    func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "com.thecreativetoken.captalo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func speedAndVoiceRoundTrip() {
        withSuite { defaults in
            ReadingPreferences(speed: 1.25, voice: "af_bella").save(to: defaults)
            #expect(ReadingPreferences.load(from: defaults, voices: ["af_heart", "af_bella"]) == ReadingPreferences(speed: 1.25, voice: "af_bella"))
        }
    }

    @Test func missingValuesUseDefaults() {
        withSuite { defaults in
            #expect(ReadingPreferences.load(from: defaults, voices: ["af_heart", "af_bella"]) == ReadingPreferences(speed: 1.0, voice: "af_heart"))
        }
    }

    @Test func unknownVoiceFallsBackToTheFirstBundledVoice() {
        withSuite { defaults in
            ReadingPreferences(speed: 1.0, voice: "removed_voice").save(to: defaults)
            #expect(ReadingPreferences.load(from: defaults, voices: ["af_heart"]).voice == "af_heart")
        }
    }

    @Test func speedSnapsToSupportedSteps() {
        withSuite { defaults in
            defaults.set(Float(1.32), forKey: ReadingPreferences.speedKey)
            #expect(ReadingPreferences.load(from: defaults, voices: ["af_heart"]).speed == 1.35)
        }
        #expect(ReadingPreferences.snap(0.1) == 0.75)
    }
}
