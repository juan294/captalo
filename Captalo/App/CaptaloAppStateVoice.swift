import AppKit
import CaptaloCore
import Foundation

extension CaptaloAppState {
    /// Installs the bundled voice (or repairs it) and starts the engine.
    func prepareVoice() {
        voiceState = .checking
        updateStatus("Preparing local voice...")
        let service = speechService
        Task { apply(await service.prepare()) }
    }

    /// "Reinstall voice" in the settings window.
    func reinstallVoice() {
        voiceState = .checking
        updateStatus("Reinstalling voice...")
        let service = speechService
        Task { apply(await service.reinstall()) }
    }

    func apply(_ result: SpeechService.PrepareResult) {
        switch result {
        case .secondInstance:
            // Another Cáptalo owns the voice store; this instance exits and the first keeps running.
            NSApplication.shared.terminate(nil)
        case let .state(state):
            voiceState = state
            updateStatus(state.statusText)
            if !state.canSpeak { onVoiceAttentionRequired?() }
        }
    }

    func reportVoiceError() {
        lastReadingError = "The last reading stopped because of a voice error."
        onVoiceAttentionRequired?()
    }

    func setVoice(_ name: String) {
        guard speechService.voices.contains(name) else { return }
        voice = name
        readingSettings.set(voice: voice, speed: speed)
    }

    /// Reads a short sample in `name` as a normal reading (it replaces any reading).
    func playSample(_ name: String) {
        setVoice(name)
        let requests = self.requests
        let spokenName = name.replacingOccurrences(of: "_", with: " ")
        Task { await requests.playText("This is the \(spokenName) voice. Select text and press your shortcut to hear it.") }
    }
}

extension VoiceInstallState {
    var statusText: String {
        switch self {
        case .checking: "Preparing local voice..."
        case .ready: "Voice ready"
        case .damaged: "Voice files are damaged. Reinstall voice."
        case .bundleInvalid: "The voice in this copy of Cáptalo is damaged. Reinstall Cáptalo."
        case let .installFailed(need): "Cáptalo needs \(Int((Double(need) / 1_000_000).rounded(.up))) MB free to install its voice."
        case .failed: "The voice could not start."
        }
    }
}
