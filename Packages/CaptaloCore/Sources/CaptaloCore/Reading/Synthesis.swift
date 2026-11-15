/// One synthesized unit: 24 kHz mono Float32 PCM plus the engine's view of the text.
public struct SynthesizedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    /// The engine's written-form normalization (the expected spoken form).
    public let normalizedText: String?
    public let phonemeCount: Int

    public init(samples: [Float], sampleRate: Int, normalizedText: String? = nil, phonemeCount: Int = 0) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.normalizedText = normalizedText
        self.phonemeCount = phonemeCount
    }

    public var seconds: Double { audioSeconds(samples: samples.count, sampleRate: sampleRate) }
}

/// Seconds of audio in `samples` frames at `sampleRate`.
public func audioSeconds(samples: Int, sampleRate: Int) -> Double {
    Double(samples) / Double(max(sampleRate, 1))
}

/// The speech engine seen by the reading pipeline. The Kokoro adapter lives
/// in CaptaloSpeech; tests use an in-memory synthesizer.
public protocol Synthesizer: Sendable {
    func synthesize(_ text: String, voice: String, speed: Float) async throws -> SynthesizedAudio
}
