import Foundation

/// Speed and voice, persisted in an injected defaults store (baseline §6).
/// Tests use a uniquely named suite that they remove afterwards.
public struct ReadingPreferences: Equatable, Sendable {
    public static let speedSteps: [Float] = [0.75, 0.85, 1.0, 1.15, 1.25, 1.35]
    public static let speedKey = "reading.speed"
    public static let voiceKey = "reading.voice"

    public var speed: Float
    public var voice: String

    public init(speed: Float, voice: String) {
        self.speed = speed
        self.voice = voice
    }

    /// The nearest supported speed.
    public static func snap(_ speed: Float) -> Float {
        speedSteps.min { abs($0 - speed) < abs($1 - speed) } ?? 1.0
    }

    /// Loads saved values; an unknown voice or a missing value falls back to the defaults.
    public static func load(from defaults: UserDefaults, voices: [String]) -> ReadingPreferences {
        let fallbackVoice = voices.first ?? "af_heart"
        let savedVoice = defaults.string(forKey: voiceKey)
        let voice = savedVoice.flatMap { voices.contains($0) ? $0 : nil } ?? fallbackVoice
        let speed = defaults.object(forKey: speedKey) == nil ? 1.0 : snap(defaults.float(forKey: speedKey))
        return ReadingPreferences(speed: speed, voice: voice)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(speed, forKey: Self.speedKey)
        defaults.set(voice, forKey: Self.voiceKey)
    }
}
