#if DEBUG
import CaptaloCore
import Foundation

/// Debug capture probe (`-CaptureProbe YES`, plan phase 2 task 3). Compares
/// each capture with the embedded fixture after whitespace normalization and
/// logs only `PrivacyLog.probe` (enums, counts and durations).
nonisolated final class CaptureProbeRunner: Sendable {
    static let defaultsKey = "CaptureProbe"

    let expected: String
    private let accessibility: AccessibilityAdapter

    init?(accessibility: AccessibilityAdapter, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: Self.defaultsKey),
              let url = Bundle.main.url(forResource: "capture-matrix", withExtension: "txt", subdirectory: "CaptureProbe"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        expected = text
        self.accessibility = accessibility
    }

    func measure(_ token: InputToken, capture: @Sendable () async -> CaptureOutcome) async -> CaptureOutcome {
        let clock = ContinuousClock()
        let snapshotStart = clock.now
        let (before, countBefore) = await Self.clipboard()
        let providerMs = Self.milliseconds(snapshotStart.duration(to: clock.now))
        let started = clock.now
        let outcome = await capture()
        let elapsedMs = Self.milliseconds(started.duration(to: clock.now))
        let (after, countAfter) = await Self.clipboard()
        var layer: CaptureLayerKind?
        var capturedLength = 0
        if case let .text(text, captured) = outcome {
            layer = captured
            capturedLength = text.count
        }
        PrivacyLog.record(.probe(
            result: CaptureProbe.result(for: outcome, expected: expected),
            layer: layer,
            expectedLength: expected.count,
            capturedLength: capturedLength,
            clipboardIntact: CaptureProbe.clipboardIntact(before: before, after: after),
            focusKept: accessibility.frontmostPID() == token.source.pid,
            providerMs: providerMs,
            elapsedMs: elapsedMs,
            changeDelta: countAfter - countBefore
        ))
        return outcome
    }

    @MainActor
    private static func clipboard() -> ([PasteboardItemSnapshot], Int) {
        let pasteboard = SystemPasteboard()
        let items = pasteboard.materialize().map { item in
            PasteboardItemSnapshot(entries: item.map { ($0.type, $0.data ?? Data("<unavailable>".utf8)) })
        }
        return (items, pasteboard.changeCount)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }
}
#endif
