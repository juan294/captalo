import AppKit
import CaptaloCore
import CaptaloSpeech
import Foundation

extension CaptaloAppState {
    /// Installs the bundled voice (or repairs it) and starts the engine.
    func prepareVoice() {
        voiceState = .checking
        let service = speechService
        Task { apply(await service.prepare()) }
    }

    /// "Reinstall voice" in the settings window. A playing reading ends first
    /// with a voice error, so its lease is released before the repair.
    func reinstallVoice() {
        let wasReading = speechService.isReading
        voiceState = .checking
        let service = speechService
        let requests = self.requests
        Task {
            await requests.stopSession()
            if wasReading { reportVoiceError() }
            apply(await service.reinstall())
        }
    }

    func apply(_ result: SpeechService.PrepareResult) {
        switch result {
        case .secondInstance:
            // Another Cáptalo owns the voice store; this instance exits and the first keeps running.
            NSApplication.shared.terminate(nil)
        case let .state(state):
            voiceState = state
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
    }

    /// Reads a short sample in `name` as a normal reading (it replaces any reading).
    func playSample(_ name: String) {
        setVoice(name)
        let requests = self.requests
        let spokenName = name.replacingOccurrences(of: "_", with: " ")
        Task { await requests.play(text: "This is the \(spokenName) voice. Select text and press your shortcut to hear it.") }
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
