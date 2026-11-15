import CaptaloCore
import Combine
import Synchronization
import SwiftUI

@MainActor
final class CaptaloAppState: ObservableObject {
    static let shared = CaptaloAppState()

    /// Voice and speed sync to `readingSettings` (read off the main actor) and
    /// persist in the defaults store on every change.
    @Published var speed: Float {
        didSet { preferencesChanged() }
    }
    @Published var voiceState: VoiceInstallState = .checking
    @Published var voice: String {
        didSet { preferencesChanged() }
    }
    @Published var loginItem = LoginItemRow.make(status: .notRegistered)
    /// Shown under the recorder after a binding was rejected.
    @Published var shortcutRejection: String?
    /// "The last reading stopped because of a voice error." until the next reading.
    @Published var lastReadingError: String?
    @Published var accessibilityPermissionGranted: Bool

    let speechService = SpeechService()
    /// Injected for tests; the app uses the standard domain.
    let defaults: UserDefaults
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
    lazy var capture: CaptureCoordinator = Self.makeCapture(
        accessibility: accessibility, requests: requests, lock: clipboardLock)

    /// Built outside the main actor so its closures are nonisolated.
    nonisolated static func makeCapture(
        accessibility: AccessibilityAdapter, requests: RequestCoordinator, lock: AsyncSerialLock
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            ax: accessibility, menu: MenuCopyAdapter(), keys: KeyEventAdapter(), focus: accessibility,
            transaction: { ClipboardTransaction(pasteboard: SystemPasteboard(), lock: lock) },
            isCurrent: { await requests.isCurrent($0) },
            sleep: { try? await Task.sleep(for: $0) }
        )
    }
    /// The selection capture, chosen once: wrapped by the probe in probe mode.
    var selectionCapture: @Sendable (InputToken) async -> CaptureOutcome {
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
    }
    #if DEBUG
    lazy var captureProbe = CaptureProbeRunner(accessibility: accessibility)
    #endif
    /// Opens the settings window when the voice needs attention.
    var onVoiceAttentionRequired: (() -> Void)?
    var onAccessibilityPermissionRequired: (() -> Void)?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accessibilityPermissionGranted = AXIsProcessTrusted()
        let saved = ReadingPreferences.load(from: defaults, voices: speechService.voices)
        speed = saved.speed
        voice = saved.voice
        readingSettings.set(voice: saved.voice, speed: saved.speed)
    }

    private func preferencesChanged() {
        readingSettings.set(voice: voice, speed: speed)
        ReadingPreferences(speed: speed, voice: voice).save(to: defaults)
    }

    var canSpeak: Bool {
        voiceState.canSpeak
    }
}

/// The voice and speed a new reading uses. A change applies from the next reading.
nonisolated final class ReadingSettings: Sendable {
    static let defaultVoice = "af_heart"
    private let state = Mutex<(voice: String, speed: Float)>((ReadingSettings.defaultVoice, 1.0))

    var current: (voice: String, speed: Float) { state.withLock { $0 } }

    func set(voice: String, speed: Float) { state.withLock { $0 = (voice, speed) } }
}
