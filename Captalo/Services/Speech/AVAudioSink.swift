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

    func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void) {
        guard Double(sampleRate) == Self.sampleRate,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            played()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        lock.withLock {
            if !engine.isRunning { try? engine.start() }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in played() }
            if !player.isPlaying { player.play() }
        }
    }

    func stop() {
        lock.withLock { player.stop() }
    }

    private func configurationChanged() {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            player.stop()
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try? engine.start()
            return onConfigurationChange
        }
        handler?()
    }
}
