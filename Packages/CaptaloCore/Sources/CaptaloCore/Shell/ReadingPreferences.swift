import Foundation

/// Speed and voice, persisted in an injected defaults store (baseline §6).
/// Tests use a uniquely named suite that they remove afterwards.
public struct ReadingPreferences: Equatable, Sendable {
    public static let speedSteps: [Float] = [0.75, 0.85, 1.0, 1.15, 1.25, 1.35]
    public static let defaultSpeed: Float = 1.0
    public static let defaultVoice = "af_heart"
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
        speedSteps[speedIndex(of: speed)]
    }

    /// The index of the nearest supported speed.
    public static func speedIndex(of speed: Float) -> Int {
        speedSteps.indices.min { abs(speedSteps[$0] - speed) < abs(speedSteps[$1] - speed) } ?? 2
    }

    /// Loads saved values; an unknown voice or a missing value falls back to the defaults.
    public static func load(from defaults: UserDefaults, voices: [String]) -> ReadingPreferences {
        let fallbackVoice = voices.first ?? defaultVoice
        let savedVoice = defaults.string(forKey: voiceKey)
        let voice = savedVoice.flatMap { voices.contains($0) ? $0 : nil } ?? fallbackVoice
        let speed = defaults.object(forKey: speedKey) == nil ? defaultSpeed : snap(defaults.float(forKey: speedKey))
        return ReadingPreferences(speed: speed, voice: voice)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(speed, forKey: Self.speedKey)
        defaults.set(voice, forKey: Self.voiceKey)
    }
}
