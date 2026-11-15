/// A keyboard event as the overlay's event tap sees it.
public struct KeyEvent: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case down, up }

    public static let escapeKeyCode: Int64 = 53

    public let phase: Phase
    public let keyCode: Int64
    /// An autorepeat keyDown of a held key.
    public let isRepeat: Bool

    public init(phase: Phase, keyCode: Int64, isRepeat: Bool = false) {
        self.phase = phase
        self.keyCode = keyCode
        self.isRepeat = isRepeat
    }

    var isEscape: Bool { keyCode == Self.escapeKeyCode }
}

/// A system key event tap. The app wraps a session `CGEventTap`; tests use a fake.
@MainActor
public protocol KeyEventTap: AnyObject {
    /// Starts delivering keyDown and keyUp events to `handler`, which returns
    /// true to swallow the event. Returns false when the tap cannot be created.
    func install(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> Bool
    func remove()
}

/// Keeps Esc from the source app while the region overlay is visible
/// (plan phase 5, unit 5A; VAL-08). The accepted Esc gesture is swallowed
/// whole: its keyDown, autorepeats and keyUp. When the overlay closes while
/// that Esc is still held, the tap stays until the keyUp, or `keyUpBound`.
@MainActor
public final class EscapeContainment {
    public typealias Schedule = @MainActor (Duration, @escaping @MainActor () -> Void) -> Void
    /// How long a closed overlay keeps the tap for the keyUp of an accepted Esc.
    public static let keyUpBound = Duration.seconds(2)

    private let tap: any KeyEventTap
    private let schedule: Schedule
    private let onEscape: @MainActor () -> Void
    /// An accepted Esc whose keyUp has not arrived.
    private var escapeHeld = false
    private var closed = false
    private var removed = false

    public init(tap: any KeyEventTap, schedule: @escaping Schedule, onEscape: @escaping @MainActor () -> Void) {
        self.tap = tap
        self.schedule = schedule
        self.onEscape = onEscape
    }

    /// Installs the tap. False when it cannot be created: the overlay must
    /// not be shown, because nothing would catch Esc.
    public func start() -> Bool {
        tap.install { [weak self] event in self?.handle(event) ?? false }
    }

    /// The overlay closed (any exit). Removes the tap now, or after the held Esc's keyUp.
    public func finish() {
        closed = true
        guard escapeHeld else { return removeTap() }
        // Strong on purpose: the closed overlay drops its reference, and the
        // tap must still be removed after the keyUp or at the bound.
        schedule(Self.keyUpBound) { self.removeTap() }
    }

    private func handle(_ event: KeyEvent) -> Bool {
        guard event.isEscape, !removed else { return false }
        switch event.phase {
        case .down:
            if escapeHeld { return true } // autorepeat of the accepted Esc
            // A repeat without an accepted keyDown: Esc was held before the overlay opened.
            guard !closed, !event.isRepeat else { return false }
            escapeHeld = true
            onEscape()
            return true
        case .up:
            // An Esc pressed before the overlay opened reached the source; so does its keyUp.
            guard escapeHeld else { return false }
            escapeHeld = false
            if closed { removeTap() }
            return true
        }
    }

    private func removeTap() {
        guard !removed else { return }
        removed = true
        tap.remove()
    }
}
