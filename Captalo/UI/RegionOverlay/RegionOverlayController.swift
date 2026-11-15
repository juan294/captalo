import AppKit
import CaptaloCore

/// The region overlay (plan phase 5, unit 5A; gate 0 choices in the notes).
/// One borderless, non-activating panel per screen that never becomes key,
/// so the source app stays frontmost with its key window. Esc is caught by a
/// session event tap (Accessibility is already granted) and swallowed, so it
/// never reaches the source app. Every exit tears down in one place.
@MainActor
final class RegionOverlayController {
    private var panels: [RegionPanel] = []
    private var tracker: RegionSelectionTracker?
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var screenObserver: NSObjectProtocol?
    private var escapeTap: EscapeTap?
    /// Set by a cancel that arrives before the overlay is shown.
    private var cancelled = false

    /// Shows the overlay and returns the selected region, or nil for any cancel.
    func select() async -> RegionSelection? {
        if cancelled { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
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
        escapeTap = EscapeTap { [weak self] in
            self?.tracker?.handle(.escape)
        }
    }

    private func tearDown(_ selection: RegionSelection?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.pop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        escapeTap?.invalidate()
        escapeTap = nil
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

/// Swallows Esc while the overlay is visible, so the source app never sees it.
@MainActor
final class EscapeTap {
    private var source: CFRunLoopSource?
    private let box: Box

    final class Box {
        let onEscape: () -> Void
        var tap: CFMachPort?
        init(_ onEscape: @escaping () -> Void) { self.onEscape = onEscape }
    }

    init(onEscape: @escaping () -> Void) {
        box = Box(onEscape)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let box = Unmanaged<EscapeTap.Box>.fromOpaque(info).takeUnretainedValue()
            // The system disables a tap that is slow or interrupted; turn it back on.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 else {
                return Unmanaged.passUnretained(event)
            }
            DispatchQueue.main.async { box.onEscape() }
            return nil
        }
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(box).toOpaque())
        box.tap = tap
        if let tap {
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func invalidate() {
        if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        box.tap = nil
    }
}
