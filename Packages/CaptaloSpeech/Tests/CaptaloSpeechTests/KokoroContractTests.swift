import CaptaloCore
import Foundation
import Testing
@testable import CaptaloSpeech

/// Contract probe against the real Kokoro frontend and engine (plan phase 3):
/// needs the verified voice files in .local/models (make fetch-models).
@Suite(.serialized) struct KokoroContractTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let models = repository.appendingPathComponent(".local/models")
    static let manifestURL = repository.appendingPathComponent("Models.manifest.json")
    /// The app's slowest and fastest speeds.
    static let speeds: [Float] = [0.75, 1.35]

    func engine() async throws -> (KokoroSynthesizer, ModelManifest, URL) {
        let manifest = try ModelManifest.load(from: Self.manifestURL)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("captalo-contract-\(UUID().uuidString)")
        let setup = VoiceSetup(store: ModelStore(root: root), manifest: manifest)
        let result = await setup.prepare(bundleModels: Self.models)
        try #require(result == .state(.ready))
        return (setup.synthesizer, manifest, root)
    }

    @Test func unpunctuated400CharacterUnitStaysWithinTheLimitOrSplits() async throws {
        let (synthesizer, manifest, root) = try await engine()
        defer { try? FileManager.default.removeItem(at: root) }
        let words = ["river", "stone", "lantern", "orchard", "harbour", "meadow", "library", "bridge"]
        var text = ""
        var index = 0
        while text.count < 395 { text += (text.isEmpty ? "" : " ") + words[index % words.count]; index += 1 }
        let unit = String(text.prefix(400))
        for voice in manifest.voices {
            for speed in Self.speeds {
                let audio = try await synthesizer.synthesize(unit, voice: voice, speed: speed)
                let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
                if seconds > ReadingLimits().maxUnitSeconds {
                    // Oversize: the session must split and still complete.
                    let session = ReadingSession(
                        units: { AnyIterator(UnitChunker([Paragraph(sentences: [unit])]).makeIterator()) },
                        synthesizer: synthesizer, sink: ImmediateSink(), voice: voice, speed: speed)
                    #expect(await session.outcome() == .finished, "\(voice) at \(speed)")
                } else {
                    #expect(seconds > 1, "\(voice) at \(speed): \(seconds) s")
                }
            }
        }
        await synthesizer.stop()
    }

    @Test func numbersFileNamesAcronymsAndURLsYieldSpeech() async throws {
        let (synthesizer, manifest, root) = try await engine()
        defer { try? FileManager.default.removeItem(at: root) }
        let cases = [
            "Version 3.14 shipped with 1,024 tests.",
            "Open Package.swift in the editor.",
            "NASA and the BBC are acronyms.",
            TextPreparer.prepare([.paragraph("See https://www.example.com/docs?id=7 now.")], source: .selection)
                .flatMap(\.sentences).joined(separator: " "),
        ]
        #expect(cases[3] == "See example.com now.")
        for text in cases {
            let audio = try await synthesizer.synthesize(text, voice: manifest.voices[0], speed: 1)
            #expect(audio.phonemeCount > 0, "\(text)")
            #expect(!(audio.normalizedText ?? "").isEmpty, "\(text)")
            #expect(audio.samples.count > audio.sampleRate / 2, "\(text)")
        }
        await synthesizer.stop()
    }
}

final class ImmediateSink: AudioSink, Sendable {
    func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool { played(); return true }
    func stop() {}
}
