import CaptaloCore
import Combine
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

    @Published var speed: Float = 1.0
    @Published var pauseForVoiceApps = true
    @Published var showMenuBarStatus = true
    @Published var status = "Preparing local voice..."
    @Published var isPaused = false
    @Published var wordsSpoken: Int
    @Published var totalDictationSeconds: Double
    @Published var latestFirstAudio: Duration?
    @Published var kokoroInstallationState: KokoroInstallationState = .checking
    @Published var kokoroInstalledProgress = 0.0
    @Published var accessibilityPermissionGranted: Bool
    @Published var statusIcon = WaveStatusIconAnimator.image(phase: 0)
    @Published var shortcut: GlobalShortcut
    @Published var shortcutError: String?
    @Published var pronunciationRules: [PronunciationRule]

    let speech = SpeechController()
    let accessibility = AccessibilityAdapter()
    let clipboardLock = AsyncSerialLock()
    /// The session factory, chosen once: the silent seam in probe mode, else speech.
    lazy var requests: RequestCoordinator = {
        let speech = speech
        #if DEBUG
        if isCaptureProbeActive {
            return RequestCoordinator { _, _, finished in SilentTimedSession(finished: finished) }
        }
        #endif
        return RequestCoordinator { token, text, finished in
            SpeechPlaybackSession(token: token, text: text, speech: speech, finished: finished) { session in
                CaptaloAppState.shared.beginReading(session)
            }
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
        return { await capture.capture($0) }
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
    var onKokoroDownloadRequired: (() -> Void)?
    var onAccessibilityPermissionRequired: (() -> Void)?

    private init() {
        wordsSpoken = UserDefaults.standard.integer(forKey: DefaultsKey.wordsSpoken)
        totalDictationSeconds = UserDefaults.standard.double(forKey: DefaultsKey.totalDictationSeconds)
        accessibilityPermissionGranted = accessibility.isProcessTrusted()
        pronunciationRules = Self.loadPronunciationRules()

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
        kokoroInstallationState.canSpeak
    }

    func updateStatus(_ text: String) {
        status = text
        waveAnimator.setAnimating(isProcessing)
    }
}
