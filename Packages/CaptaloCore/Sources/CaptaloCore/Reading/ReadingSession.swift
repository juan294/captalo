import Foundation

/// Plays PCM. The app's implementation wraps AVAudioEngine; tests use an
/// in-memory sink. `played` fires once a buffer has played back.
///
/// Both calls are synchronous so the session can stop and reschedule with no
/// suspension in between (a replay is never interleaved with new units).
public protocol AudioSink: Sendable {
    func schedule(_ samples: [Float], sampleRate: Int, played: @escaping @Sendable () -> Void)
    /// Silence at once and drop every scheduled buffer.
    func stop()
}

public enum ReadingOutcome: Equatable, Sendable {
    case finished
    case stopped
    case voiceError
}

/// Observations for tests, the probe and PrivacyLog (no text).
public enum ReadingEvent: Equatable, Sendable {
    case scheduled(unitID: Int, sentenceID: Int, seconds: Double, queuedSeconds: Double)
    case played(unitID: Int)
    case oversizeSplit(unitID: Int)
    case replayed(unitID: Int)
}

public struct ReadingLimits: Sendable {
    /// Units synthesized beyond the audible one.
    public var lookahead = 3
    /// A synthesized unit longer than this is split and re-synthesized, never truncated.
    public var maxUnitSeconds = 35.0
    /// Queued (scheduled, not yet audible) seconds: lookahead × maxUnitSeconds.
    public var maxQueuedSeconds = 105.0
    /// A piece is never split below this many characters.
    public var minimumSplitLength = 40
    public var sentencePause = 0.30
    public var paragraphPause = 0.35

    public init() {}
}

/// One committed reading (plan phase 3, unit 3C; review R9, V2-5).
///
/// At most one synthesis call is in flight, at most `lookahead` synthesized
/// units wait behind the audible one, and every result is checked against
/// `maxUnitSeconds` before it is enqueued. Played buffers are released.
public actor ReadingSession {
    private struct Piece {
        let unit: SynthesisUnit
        let text: String
        let isLastPiece: Bool
    }

    private struct Scheduled {
        let sequence: UInt64
        let unit: SynthesisUnit
        let isLastPiece: Bool
        let samples: [Float]
        let sampleRate: Int
        var played = false
        var seconds: Double { Double(samples.count) / Double(max(sampleRate, 1)) }
    }

    private let synthesizer: Synthesizer
    private let sink: AudioSink
    private let voice: String
    private let speed: Float
    private let limits: ReadingLimits
    private let onEvent: @Sendable (ReadingEvent) -> Void
    private var makeUnits: (@Sendable () -> AnyIterator<SynthesisUnit>)?
    private var units: AnyIterator<SynthesisUnit>?
    private var pending: [Piece] = []
    private var queue: [Scheduled] = []
    private var epoch: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var stopped = false
    private var failed = false
    private var exhausted = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var runTask: Task<ReadingOutcome, Never>?
    public private(set) var maxRetained = 0
    public private(set) var maxQueuedSeconds = 0.0

    public init(
        units: @escaping @Sendable () -> AnyIterator<SynthesisUnit>,
        synthesizer: Synthesizer,
        sink: AudioSink,
        voice: String,
        speed: Float,
        limits: ReadingLimits = ReadingLimits(),
        onEvent: @escaping @Sendable (ReadingEvent) -> Void = { _ in }
    ) {
        makeUnits = units
        self.synthesizer = synthesizer
        self.sink = sink
        self.voice = voice
        self.speed = speed
        self.limits = limits
        self.onEvent = onEvent
    }

    /// Starts the pipeline and returns at once; `outcome()` waits for the end.
    public func start() {
        guard runTask == nil else { return }
        runTask = Task { await self.run() }
    }

    public func outcome() async -> ReadingOutcome {
        start()
        return await runTask!.value
    }

    /// Stop or replace: silence at once; an in-flight result is discarded when it returns.
    public func stop() async {
        guard !stopped else { return }
        stopped = true
        epoch += 1
        queue.removeAll()
        pending.removeAll()
        wake()
        sink.stop()
    }

    /// `AVAudioEngineConfigurationChange`: the sink has restarted; play again
    /// from the start of the audible unit (owner decision 6).
    public func deviceChanged() {
        guard !stopped else { return }
        epoch += 1
        sink.stop()
        if let first = queue.first { onEvent(.replayed(unitID: first.unit.id)) }
        for index in queue.indices { queue[index].played = false }
        queue.forEach(scheduleToSink)
    }

    // MARK: - Pipeline

    private func run() async -> ReadingOutcome {
        if let makeUnits {
            units = makeUnits()
            self.makeUnits = nil
        }
        while !stopped {
            if !failed, queue.count <= limits.lookahead, let piece = nextPiece() {
                await synthesize(piece)
                continue
            }
            if queue.isEmpty {
                if failed { return .voiceError }
                if exhausted { return .finished }
            }
            await waitForPlayback()
        }
        return .stopped
    }

    private func nextPiece() -> Piece? {
        if !pending.isEmpty { return pending.removeFirst() }
        guard let unit = units?.next() else {
            exhausted = true
            return nil
        }
        return Piece(unit: unit, text: unit.text, isLastPiece: true)
    }

    private func synthesize(_ piece: Piece) async {
        let audio: SynthesizedAudio
        do {
            audio = try await synthesizer.synthesize(piece.text, voice: voice, speed: speed)
        } catch {
            // Scheduled audio finishes, then the reading ends with a voice error.
            if !stopped { failed = true }
            return
        }
        guard !stopped else { return } // stop or replace: the result is discarded
        let seconds = Double(audio.samples.count) / Double(max(audio.sampleRate, 1))
        if seconds > limits.maxUnitSeconds {
            onEvent(.oversizeSplit(unitID: piece.unit.id))
            guard let halves = split(piece) else {
                failed = true // a minimum-size piece is still oversize: never truncate
                return
            }
            pending.insert(contentsOf: halves, at: 0)
            return
        }
        var samples = audio.samples
        if piece.isLastPiece {
            var pause = piece.unit.endsSentence ? limits.sentencePause : 0
            if piece.unit.endsParagraph { pause += limits.paragraphPause }
            samples.append(contentsOf: repeatElement(0, count: Int((pause * Double(audio.sampleRate)).rounded())))
        }
        nextSequence += 1
        let item = Scheduled(sequence: nextSequence, unit: piece.unit, isLastPiece: piece.isLastPiece,
                             samples: samples, sampleRate: audio.sampleRate)
        queue.append(item)
        maxRetained = max(maxRetained, queue.count)
        let queued = queue.dropFirst().reduce(0) { $0 + $1.seconds }
        maxQueuedSeconds = max(maxQueuedSeconds, queued)
        onEvent(.scheduled(unitID: piece.unit.id, sentenceID: piece.unit.sentenceID, seconds: item.seconds, queuedSeconds: queued))
        scheduleToSink(item)
    }

    private func split(_ piece: Piece) -> [Piece]? {
        let count = piece.text.count
        guard count >= limits.minimumSplitLength * 2 else { return nil }
        let (head, tail) = UnitChunker<[Paragraph]>.split(Substring(piece.text), limit: count / 2)
        guard !head.isEmpty, !tail.isEmpty, head.count >= limits.minimumSplitLength || tail.count >= limits.minimumSplitLength else {
            return nil
        }
        return [
            Piece(unit: piece.unit, text: String(head), isLastPiece: false),
            Piece(unit: piece.unit, text: String(tail), isLastPiece: piece.isLastPiece),
        ]
    }

    private func scheduleToSink(_ item: Scheduled) {
        let scheduledEpoch = epoch
        let sequence = item.sequence
        sink.schedule(item.samples, sampleRate: item.sampleRate) { [weak self] in
            Task { await self?.played(sequence: sequence, epoch: scheduledEpoch) }
        }
    }

    /// Playback callbacks reach the actor through separate tasks, which may
    /// run out of order: each marks its buffer, and the leading played
    /// buffers are released in order.
    private func played(sequence: UInt64, epoch playedEpoch: UInt64) {
        // Callbacks from before a stop or an engine restart are ignored.
        guard playedEpoch == epoch, let index = queue.firstIndex(where: { $0.sequence == sequence }) else { return }
        queue[index].played = true
        while let first = queue.first, first.played {
            queue.removeFirst()
            if first.isLastPiece { onEvent(.played(unitID: first.unit.id)) }
        }
        wake()
    }

    private func waitForPlayback() async {
        await withCheckedContinuation { waiter = $0 }
    }

    private func wake() {
        waiter?.resume()
        waiter = nil
    }

    public var retainedBuffers: Int { queue.count }
}
