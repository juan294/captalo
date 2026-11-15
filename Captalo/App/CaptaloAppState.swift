import CaptaloCore
import Combine
import KeyboardShortcuts
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
    /// Cached: whether a read shortcut is recorded (updated by the recorder).
    @Published var readShortcutSet = KeyboardShortcuts.getShortcut(for: .readSelection) != nil
    @Published var regionShortcutSet = KeyboardShortcuts.getShortcut(for: .readRegion) != nil
    @Published var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    /// Screen Recording was requested once; after that the row offers "Quit and reopen".
    @Published var screenRecordingRequested = false
    @Published var ocrFailures = OcrFailureCounter()
    /// "The last reading stopped because of a voice error." until the next reading.
    @Published var lastReadingError: String?
    @Published var accessibilityPermissionGranted: Bool

    let speechService = SpeechService()
    /// Where speed and voice persist (the app's standard domain).
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
        return RequestCoordinator { _, content, finished in
            let (voice, speed) = settings.current
            return speechService.makeSession(
                content: content, voice: voice, speed: speed, finished: finished,
                voiceError: { Task { @MainActor in CaptaloAppState.shared.reportVoiceError() } }
            )
        }
    }()
    lazy var regionReader: RegionReader = Self.makeRegionReader(requests: requests)
    lazy var capture: CaptureCoordinator = Self.makeCapture(
        accessibility: accessibility, requests: requests, lock: clipboardLock)

    /// Built outside the main actor so its closures are nonisolated.
    nonisolated static func makeCapture(
        accessibility: AccessibilityAdapter, requests: RequestCoordinator, lock: AsyncSerialLock
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            ax: accessibility, menu: MenuCopyFinder(tree: AXMenuTree()), keys: KeyEventAdapter(), focus: accessibility,
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
            if case let .text(text, _) = outcome, !TextPreparer.hasSpeakableText(.text(text)) { return .nothingSelected }
            return outcome
        }
    }
    #if DEBUG
    lazy var captureProbe = CaptureProbeRunner(accessibility: accessibility)
    #endif
    /// Shows the settings window.
    var onSetupRequired: (() -> Void)?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accessibilityPermissionGranted = accessibility.isProcessTrusted()
        let saved = ReadingPreferences.load(from: defaults, voices: speechService.voices)
        speed = saved.speed
        voice = saved.voice
        readingSettings.set(voice: saved.voice, speed: saved.speed)
    }

    /// Opens the settings window when required setup is missing (launch, a
    /// failed press, a voice that needs attention). The one place that decides.
    func requireSetup() {
        if !setup.isReady { onSetupRequired?() }
    }

    private func preferencesChanged() {
        readingSettings.set(voice: voice, speed: speed)
        ReadingPreferences(speed: speed, voice: voice).save(to: defaults)
    }

}

/// The voice and speed a new reading uses. A change applies from the next reading.
nonisolated final class ReadingSettings: Sendable {
    private let state = Mutex<(voice: String, speed: Float)>((ReadingPreferences.defaultVoice, ReadingPreferences.defaultSpeed))

    var current: (voice: String, speed: Float) { state.withLock { $0 } }

    func set(voice: String, speed: Float) { state.withLock { $0 = (voice, speed) } }
}
