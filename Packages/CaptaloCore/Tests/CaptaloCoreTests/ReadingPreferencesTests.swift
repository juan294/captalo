import Foundation
import Testing
@testable import CaptaloCore

@Suite struct ReadingPreferencesTests {
    static let disposablePrefix = "com.thecreativetoken.captalo.tests."

    /// A disposable domain unique to one test. Teardown deletes the domain with
    /// `defaults delete` and then the empty plist the delete leaves in
    /// ~/Library/Preferences, only for this exact prefix plus the test's UUID.
    /// An in-process removePersistentDomain lets cfprefsd write the empty plist
    /// again about 10 s later; the out-of-process delete does not.
    func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let id = UUID()
        let name = Self.disposablePrefix + id.uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer {
            let delete = Process()
            delete.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            delete.arguments = ["delete", name]
            delete.standardOutput = FileHandle.nullDevice
            delete.standardError = FileHandle.nullDevice
            try? delete.run()
            delete.waitUntilExit()
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/\(Self.disposablePrefix)\(id.uuidString).plist")
            try? FileManager.default.removeItem(at: plist)
            #expect(!FileManager.default.fileExists(atPath: plist.path), "disposable plist left behind")
        }
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
