import CaptaloCore
import Combine
import Synchronization
import SwiftUI

@MainActor
final class CaptaloAppState: ObservableObject {
    static let shared = CaptaloAppState()

    static let speedSteps: [Float] = [0.75, 0.85, 1.0, 1.15, 1.25, 1.35]

    enum DefaultsKey {
        static let wordsSpoken = "stats.wordsSpoken"
        static let totalDictationSeconds = "stats.totalDictationSeconds"
        static let pronunciationRules = "speech.pronunciationRules"
        static let globalShortcut = "globalShortcut"
    }

    /// Voice and speed sync to `readingSettings` (read off the main actor) on every change.
    @Published var speed: Float = 1.0 {
        didSet { readingSettings.set(voice: voice, speed: speed) }
    }
    @Published var pauseForVoiceApps = true
    @Published var showMenuBarStatus = true
    @Published var status = "Preparing local voice..."
    @Published var wordsSpoken: Int
    @Published var totalDictationSeconds: Double
    @Published var latestFirstAudio: Duration?
    @Published var voiceState: VoiceInstallState = .checking
    @Published var voice: String {
        didSet { readingSettings.set(voice: voice, speed: speed) }
    }
    /// "The last reading stopped because of a voice error." until the next reading.
    @Published var lastReadingError: String?
    @Published var accessibilityPermissionGranted: Bool
    @Published var statusIcon = WaveStatusIconAnimator.image(phase: 0)
    @Published var shortcut: GlobalShortcut
    @Published var shortcutError: String?
    @Published var pronunciationRules: [PronunciationRule]

    let speechService = SpeechService()
    /// Voice and speed as the reading pipeline sees them (read off the main actor).
    let readingSettings = ReadingSettings()
    let accessibility = AccessibilityAdapter()
    let clipboardLock = AsyncSerialLock()
    /// The session factory, chosen once: the silent seam in probe mode, else speech.
    lazy var requests: RequestCoordinator = {
        #if DEBUG
        if isCaptureProbeActive {
            return RequestCoordinator { _, _, finished in SilentTimedSession(finished: finished) }
        }
        #endif
        let speechService = speechService
        let settings = readingSettings
        return RequestCoordinator { _, text, finished in
            let (voice, speed) = settings.current
            return speechService.makeSession(
                text: text, source: .selection, voice: voice, speed: speed, finished: finished,
                voiceError: { Task { @MainActor in CaptaloAppState.shared.reportVoiceError() } }
            )
        }
    }()
    lazy var capture: CaptureCoordinator = {
        let requests = self.requests
        let lock = clipboardLock
        return CaptureCoordinator(
            ax: accessibility, menu: MenuCopyAdapter(), keys: KeyEventAdapter(), focus: accessibility,
            transaction: { ClipboardTransaction(pasteboard: SystemPasteboard(), lock: lock) },
            isCurrent: { await requests.isCurrent($0) }
        )
    }()
    /// The selection capture, chosen once: wrapped by the probe in probe mode.
    lazy var selectionCapture: @Sendable (InputToken) async -> CaptureOutcome = {
        let capture = self.capture
        #if DEBUG
        if let probe = captureProbe {
            return { token in await probe.measure(token) { await capture.capture(token) } }
        }
        #endif
        return { token in
            let outcome = await capture.capture(token)
            // Text that cleanup removes completely is silence, like an empty selection.
            if case let .text(text, _) = outcome, !TextPreparer.hasSpeakableText(text) { return .nothingSelected }
            return outcome
        }
    }()
    #if DEBUG
    lazy var captureProbe = CaptureProbeRunner(accessibility: accessibility)
    #endif
    var dictationSessionStartedAt: ContinuousClock.Instant?
    lazy var waveAnimator = WaveStatusIconAnimator { [weak self] image in
        self?.statusIcon = image
    }

    var onShortcutChanged: ((GlobalShortcut) -> Void)?
    var onOpenStudio: (() -> Void)?
    /// Opens the settings window when the voice needs attention.
    var onVoiceAttentionRequired: (() -> Void)?
    var onAccessibilityPermissionRequired: (() -> Void)?

    private init() {
        wordsSpoken = UserDefaults.standard.integer(forKey: DefaultsKey.wordsSpoken)
        totalDictationSeconds = UserDefaults.standard.double(forKey: DefaultsKey.totalDictationSeconds)
        accessibilityPermissionGranted = accessibility.isProcessTrusted()
        pronunciationRules = Self.loadPronunciationRules()
        let initialVoice = speechService.voices.first ?? ReadingSettings.defaultVoice
        voice = initialVoice
        readingSettings.set(voice: initialVoice, speed: 1.0)

        if let data = UserDefaults.standard.data(forKey: DefaultsKey.globalShortcut),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
    }

    var isProcessing: Bool {
        ["Preparing", "Loading", "Reading", "Generating", "Speaking"].contains {
            status.hasPrefix($0)
        }
    }

    var speedIndex: Int {
        Self.speedSteps.indices.min {
            abs(Self.speedSteps[$0] - speed) < abs(Self.speedSteps[$1] - speed)
        } ?? 2
    }

    var canSpeak: Bool {
        voiceState.canSpeak
    }

    func updateStatus(_ text: String) {
        status = text
        waveAnimator.setAnimating(isProcessing)
    }
}

/// The voice and speed a new reading uses. A change applies from the next reading.
nonisolated final class ReadingSettings: Sendable {
    static let defaultVoice = "af_heart"
    private let state = Mutex<(voice: String, speed: Float)>((ReadingSettings.defaultVoice, 1.0))

    var current: (voice: String, speed: Float) { state.withLock { $0 } }

    func set(voice: String, speed: Float) { state.withLock { $0 = (voice, speed) } }
}
