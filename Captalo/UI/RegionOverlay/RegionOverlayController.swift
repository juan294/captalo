import AppKit
import CaptaloCore

/// The region overlay (plan phase 5, unit 5A; gate 0 choices in the notes).
/// One borderless, non-activating panel per screen that never becomes key,
/// so the source app stays frontmost with its key window. Esc is caught by a
/// session event tap (Accessibility is already granted) and swallowed whole,
/// keyDown and keyUp, so it never reaches the source app (VAL-08). Every
/// exit tears down in one place.
@MainActor
final class RegionOverlayController {
    enum Outcome {
        case selected(RegionSelection)
        case cancelled
        /// The Esc tap could not be created; no panel was shown.
        case escapeUnavailable
    }

    private var panels: [RegionPanel] = []
    private var tracker: RegionSelectionTracker?
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var screenObserver: NSObjectProtocol?
    private var escape: EscapeContainment?
    /// Set by a cancel that arrives before the overlay is shown.
    private var cancelled = false

    /// Shows the overlay and returns the selected region or why there is none.
    func select() async -> Outcome {
        if cancelled { return .cancelled }
        // The tap comes first: panels without a working Esc are never shown.
        let escape = EscapeContainment(tap: SessionKeyTap(), schedule: { delay, body in
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                body()
            }
        }) { [weak self] in
            // Torn down after the tap callback returns, not inside it.
            DispatchQueue.main.async { self?.tracker?.handle(.escape) }
        }
        guard escape.start() else { return .escapeUnavailable }
        self.escape = escape
        let selection = await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
        return selection.map(Outcome.selected) ?? .cancelled
    }

    /// A newer input superseded the region press (before or after the overlay opened).
    func cancel() {
        cancelled = true
        tracker?.handle(.superseded)
    }

    private func show() {
        let displays = NSScreen.screens.map { screen in
            DisplayInfo(id: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                        frame: screen.frame, scale: screen.backingScaleFactor)
        }
        let tracker = RegionSelectionTracker(displays: displays) { [weak self] selection in
            self?.tearDown(selection)
        }
        self.tracker = tracker
        panels = NSScreen.screens.map { screen in
            let panel = RegionPanel(screen: screen) { [weak self] event in
                guard let self, let tracker = self.tracker else { return }
                tracker.handle(event)
                self.panels.forEach { $0.draw(tracker.dragRect) }
            }
            panel.orderFrontRegardless()
            return panel
        }
        NSCursor.crosshair.push()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tracker?.handle(.screensChanged) }
        }
    }

    private func tearDown(_ selection: RegionSelection?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.pop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        // Kept until a held Esc's keyUp (bounded), so the source never sees it.
        escape?.finish()
        escape = nil
        tracker = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: selection)
    }
}

/// A full-screen, nearly transparent panel that receives mouse events
/// without activating Cáptalo or becoming key.
@MainActor
final class RegionPanel: NSPanel {
    private let view: RegionView

    init(screen: NSScreen, onEvent: @escaping (RegionSelectionTracker.Event) -> Void) {
        view = RegionView(onEvent: onEvent)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        // Fully transparent pixels pass clicks through; this tint keeps the mouse.
        backgroundColor = NSColor.black.withAlphaComponent(0.01)
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func draw(_ rect: CGRect?) {
        view.selection = rect.map { convertFromScreen($0) }
    }
}

@MainActor
final class RegionView: NSView {
    private let onEvent: (RegionSelectionTracker.Event) -> Void
    var selection: CGRect? {
        didSet {
            guard selection != oldValue else { return }
            // Only the old and new rectangles need repainting, not the whole screen.
            for rect in [oldValue, selection].compactMap({ $0 }) { setNeedsDisplay(rect.insetBy(dx: -2, dy: -2)) }
        }
    }

    init(onEvent: @escaping (RegionSelectionTracker.Event) -> Void) {
        self.onEvent = onEvent
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onEvent(.mouseDown(NSEvent.mouseLocation)) }
    override func mouseDragged(with event: NSEvent) { onEvent(.mouseDragged(NSEvent.mouseLocation)) }
    override func mouseUp(with event: NSEvent) { onEvent(.mouseUp(NSEvent.mouseLocation)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        selection.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

/// A session `CGEventTap` for keyDown and keyUp, on the main run loop.
/// `EscapeContainment` decides what it swallows.
@MainActor
final class SessionKeyTap: KeyEventTap {
    private var source: CFRunLoopSource?
    private let box = Box()

    nonisolated final class Box: @unchecked Sendable {
        var handler: (@MainActor (KeyEvent) -> Bool)?
        var tap: CFMachPort?
    }

    func install(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let box = Unmanaged<SessionKeyTap.Box>.fromOpaque(info).takeUnretainedValue()
            // The system disables a tap that is slow or interrupted; turn it back on.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let phase: KeyEvent.Phase
            switch type {
            case .keyDown: phase = .down
            case .keyUp: phase = .up
            default: return Unmanaged.passUnretained(event)
            }
            let key = KeyEvent(phase: phase, keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                               isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            // The run loop source is on the main run loop, so this is the main thread.
            let swallow = MainActor.assumeIsolated { box.handler?(key) ?? false }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(box).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        box.handler = handler
        box.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// A tap dropped without `remove()` must not outlive the box its callback reads.
    isolated deinit {
        remove()
    }

    func remove() {
        if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        box.tap = nil
        box.handler = nil
    }
}
