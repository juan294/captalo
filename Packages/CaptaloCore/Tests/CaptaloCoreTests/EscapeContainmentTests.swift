import Testing
@testable import CaptaloCore

/// The system event tap is not owned code, so it is faked.
@MainActor
final class FakeKeyTap: KeyEventTap {
    var canInstall = true
    private(set) var installs = 0
    private(set) var removals = 0
    private var handler: (@MainActor (KeyEvent) -> Bool)?

    var isInstalled: Bool { handler != nil }

    func install(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> Bool {
        installs += 1
        guard canInstall else { return false }
        self.handler = handler
        return true
    }

    func remove() {
        removals += 1
        handler = nil
    }

    /// Delivers an event; true when the tap swallowed it (the source app never sees it).
    func send(_ event: KeyEvent) -> Bool { handler?(event) ?? false }
}

/// VAL-08: the whole accepted Esc gesture is swallowed, and a tap that
/// cannot be created is reported instead of leaving an overlay without Esc.
@MainActor
@Suite struct EscapeContainmentTests {
    static let escDown = KeyEvent(phase: .down, keyCode: KeyEvent.escapeKeyCode)
    static let escRepeat = KeyEvent(phase: .down, keyCode: KeyEvent.escapeKeyCode, isRepeat: true)
    static let escUp = KeyEvent(phase: .up, keyCode: KeyEvent.escapeKeyCode)

    /// Records scheduled bounds (fired by hand) and Esc callbacks.
    final class Box {
        var scheduled: [(Duration, @MainActor () -> Void)] = []
        var escapes = 0
    }

    let tap = FakeKeyTap()
    let box = Box()

    func containment() -> EscapeContainment {
        let box = self.box
        return EscapeContainment(tap: tap, schedule: { box.scheduled.append(($0, $1)) }) { box.escapes += 1 }
    }

    @Test func escKeyDownAndKeyUpAreBothSwallowed() {
        let containment = containment()
        #expect(containment.start())
        #expect(tap.send(Self.escDown))
        #expect(box.escapes == 1)
        // The overlay tears down on the keyDown; the tap stays for the keyUp.
        containment.finish()
        #expect(tap.isInstalled)
        #expect(tap.send(Self.escRepeat))
        #expect(box.escapes == 1)
        #expect(tap.send(Self.escUp))
        #expect(!tap.isInstalled)
    }

    /// The overlay drops its reference at teardown; the containment lives
    /// on until the keyUp or the bound, and still removes the tap.
    @Test func closedContainmentOutlivesItsOverlay() {
        var containment: EscapeContainment? = containment()
        #expect(containment?.start() == true)
        #expect(tap.send(Self.escDown))
        containment?.finish()
        containment = nil
        #expect(tap.send(Self.escUp))
        #expect(!tap.isInstalled)
    }

    @Test func otherKeysAndAnEarlierEscPass() {
        let containment = containment()
        #expect(containment.start())
        #expect(!tap.send(KeyEvent(phase: .down, keyCode: 0)))
        #expect(!tap.send(KeyEvent(phase: .up, keyCode: 0)))
        // Esc pressed before the overlay opened: the source saw its keyDown, so it gets the keyUp.
        #expect(!tap.send(Self.escUp))
        #expect(box.escapes == 0)
        containment.finish()
        #expect(!tap.isInstalled)
        #expect(box.scheduled.isEmpty)
    }

    /// Esc was already held when the overlay opened: its autorepeats and
    /// keyUp belong to the source, and they do not close the overlay.
    @Test func escHeldBeforeOverlayPasses() {
        let containment = containment()
        #expect(containment.start())
        #expect(!tap.send(Self.escRepeat))
        #expect(box.escapes == 0)
        #expect(!tap.send(Self.escUp))
        // A fresh press afterwards is accepted.
        #expect(tap.send(Self.escDown))
        #expect(box.escapes == 1)
    }

    /// The keyUp never comes (or the tap misses it): teardown is bounded.
    @Test func missingKeyUpIsBounded() {
        let containment = containment()
        #expect(containment.start())
        #expect(tap.send(Self.escDown))
        containment.finish()
        #expect(tap.isInstalled)
        #expect(box.scheduled.map(\.0) == [EscapeContainment.keyUpBound])
        box.scheduled.first?.1()
        #expect(!tap.isInstalled)
        // The bound firing after the keyUp already removed the tap is harmless.
        box.scheduled.first?.1()
        #expect(tap.removals == 1)
    }

    @Test func tapCreationFailureIsReported() {
        tap.canInstall = false
        let containment = containment()
        #expect(containment.start() == false)
        #expect(!tap.isInstalled)
        #expect(!tap.send(Self.escDown))
        #expect(box.escapes == 0)
    }
}
