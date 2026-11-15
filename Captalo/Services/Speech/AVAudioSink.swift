@preconcurrency import AVFoundation
import CaptaloCore
import Foundation

/// `AudioSink` over one AVAudioEngine and player node (24 kHz mono Float32).
/// On `AVAudioEngineConfigurationChange` (headphones unplugged, device
/// switched) it restarts the engine and reports the change, so the reading
/// replays from the start of the audible unit (owner decision 6).
nonisolated final class AVAudioSink: AudioSink, @unchecked Sendable {
    static let sampleRate = 24_000.0

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: AVAudioSink.sampleRate, channels: 1)!
    private let lock = NSLock()
    /// A player stop completes every dropped buffer; the gate keeps those
    /// completions from looking like plays (phase 3 review, blocker 2).
    private let gate = PlaybackGate()
    private var observer: NSObjectProtocol?
    private var onConfigurationChange: (@Sendable () -> Void)?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.configurationChanged() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func setConfigurationChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { onConfigurationChange = handler }
    }

    /// False (nothing scheduled) for a wrong format or when the engine cannot start;
    /// the session then ends with a voice error instead of skipping audio.
    func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) -> Bool {
        guard Double(sampleRate) == Self.sampleRate, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return false
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        let gated = gate.gated(played)
        return lock.withLock {
            if !engine.isRunning {
                do { try engine.start() } catch { return false }
            }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in gated() }
            if !player.isPlaying { player.play() }
            return true
        }
    }

    func stop() {
        lock.withLock {
            gate.invalidate()
            player.stop()
        }
    }

    private func configurationChanged() {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            // Invalidate first: the stop below completes every scheduled buffer.
            gate.invalidate()
            player.stop()
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try? engine.start()
            return onConfigurationChange
        }
        // The session replays from the start of the audible unit; scheduling
        // reports failure if the engine did not restart.
        handler?()
    }
}
