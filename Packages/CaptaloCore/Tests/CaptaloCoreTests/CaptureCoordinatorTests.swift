import AppKit
import Foundation
import Testing
@testable import CaptaloCore

/// Accessibility is not owned code, so it is faked. The fake answers per
/// attribute and records every attribute write.
final class FakeAX: SelectionAccessibility, @unchecked Sendable {
    var trusted = true
    var selectedText: AXRead<String> = .unsupported
    var range: AXRead<AXTextRange> = .unsupported
    var rangeString: AXRead<String> = .unsupported
    var marker: AXRead<String> = .unsupported
    /// Returned by the reads that follow an AXManualAccessibility write
    /// (Chromium builds its tree then); `manualReadsAfterWrite` reads see it.
    var afterManual: AXRead<String>?
    var manualReadsAfterWrite = 1
    /// The tree appears only after this many reads following the write.
    var manualDelayReads = 0
    private(set) var writes: [String] = []
    private(set) var reads = 0
    private var manualReadsLeft = 0
    private var delayLeft = 0

    func isProcessTrusted() -> Bool { trusted }
    func selectedText(_ element: ElementRef) -> AXRead<String> {
        reads += 1
        if delayLeft > 0 { delayLeft -= 1; return selectedText }
        if manualReadsLeft > 0, let afterManual { manualReadsLeft -= 1; return afterManual }
        return selectedText
    }
    func selectedTextRange(_ element: ElementRef) -> AXRead<AXTextRange> { range }
    func string(for range: AXTextRange, in element: ElementRef) -> AXRead<String> { rangeString }
    func textMarkerSelection(_ element: ElementRef) -> AXRead<String> { marker }
    func setApplicationAttribute(_ name: String, to value: Bool, pid: Int32) -> Bool {
        writes.append(name)
        if name == AXSelectionLayer.manualAccessibilityAttribute {
            manualReadsLeft = manualReadsAfterWrite
            delayLeft = manualDelayReads
        }
        return true
    }
}

final class FakeMenu: MenuCopyAccess, @unchecked Sendable {
    var state: MenuCopyState = .absent
    var onPress: () -> Void = {}
    private(set) var presses = 0
    func copyItemState(pid: Int32) -> MenuCopyState { state }
    func pressCopy(pid: Int32) -> Bool {
        presses += 1
        MainActor.assumeIsolated { onPress() }
        return true
    }
}

final class FakeKeys: KeyEventPosting, @unchecked Sendable {
    var released = true
    var releasedProvider: (() -> Bool)?
    var onPost: () -> Void = {}
    private(set) var posts = 0
    func shortcutModifiersReleased() -> Bool { releasedProvider?() ?? released }
    func postCopy() {
        posts += 1
        MainActor.assumeIsolated { onPost() }
    }
}

final class FakeFocus: FocusEnvironment, @unchecked Sendable {
    var pid: Int32? = 101
    var element: ElementRef? = ElementRef("field-a")
    func frontmostPID() -> Int32? { pid }
    func focusedElement(pid: Int32) -> ElementRef? { element }
}

@MainActor
@Suite(.serialized) final class CaptureCoordinatorTests {
    let board = NSPasteboard(name: NSPasteboard.Name("captalo-capture-test-\(UUID().uuidString)"))
    let ax = FakeAX()
    let menu = FakeMenu()
    let keys = FakeKeys()
    let focus = FakeFocus()
    let token = InputToken(inputGeneration: 1, kind: .selection, source: sourceA, startedAt: .now)

    isolated deinit {
        board.releaseGlobally()
    }

    func coordinator(current: Bool = true) -> CaptureCoordinator {
        let board = self.board
        var limits = ClipboardTransaction.Limits()
        limits.copyWindow = .milliseconds(100)
        limits.pollInterval = .milliseconds(5)
        let lock = AsyncSerialLock()
        return CaptureCoordinator(
            ax: ax, menu: menu, keys: keys, focus: focus,
            transaction: { ClipboardTransaction(pasteboard: SystemPasteboard(board), lock: lock, limits: limits) },
            isCurrent: { _ in current },
            sleep: { _ in }
        )
    }

    func sourceAppCopies(_ text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
    }

    @Test func axTextWinsAndPasteboardUntouched() async {
        board.clearContents()
        board.setString("keep", forType: .string)
        let before = board.changeCount
        ax.selectedText = .value("Selected via AX")
        menu.state = .enabled
        #expect(await coordinator().capture(token) == .text("Selected via AX", layer: .accessibility))
        #expect(board.changeCount == before)
        #expect(menu.presses == 0)
        #expect(keys.posts == 0)
    }

    @Test func axVariantsAreTriedInOrder() async {
        ax.selectedText = .value("")
        ax.range = .value(AXTextRange(location: 0, length: 4))
        ax.rangeString = .value("from range")
        #expect(await coordinator().capture(token) == .text("from range", layer: .accessibility))
        ax.range = .unsupported
        ax.marker = .value("from markers")
        #expect(await coordinator().capture(token) == .text("from markers", layer: .accessibility))
    }

    @Test func confirmedEmptyNeverReachesCopy() async {
        menu.state = .enabled
        ax.selectedText = .value("")
        #expect(await coordinator().capture(token) == .nothingSelected)
        ax.selectedText = .unsupported
        ax.range = .value(AXTextRange(location: 3, length: 0))
        #expect(await coordinator().capture(token) == .nothingSelected)
        #expect(menu.presses == 0)
        #expect(keys.posts == 0)
    }

    @Test func unavailableUsesMenuCopyWhenPolicyAllows() async {
        ax.selectedText = .error
        menu.state = .enabled
        menu.onPress = { self.sourceAppCopies("menu copied") }
        #expect(await coordinator().capture(token) == .text("menu copied", layer: .menuCopy))
        #expect(menu.presses == 1)
        #expect(keys.posts == 0)
    }

    @Test func copyPolicyBlocksVSCodeWithUnsupported() async {
        let vscode = InputToken(inputGeneration: 1, kind: .selection,
                                source: InputSource(pid: 101, bundleID: "com.microsoft.VSCode", focusedElement: ElementRef("field-a")),
                                startedAt: .now)
        menu.state = .enabled
        #expect(await coordinator().capture(vscode) == .unsupported(.copyMayNotReflectSelection))
        #expect(menu.presses == 0)
        #expect(keys.posts == 0)
    }

    @Test func disabledCopyItemMeansNothingSelectedAndNoKeyEvent() async {
        menu.state = .disabled
        #expect(await coordinator().capture(token) == .nothingSelected)
        #expect(menu.presses == 0)
        #expect(keys.posts == 0)
    }

    @Test func syntheticCopyOnlyWhenNoCopyItem() async {
        menu.state = .absent
        keys.onPost = { self.sourceAppCopies("synthetic copied") }
        #expect(await coordinator().capture(token) == .text("synthetic copied", layer: .syntheticCopy))
        #expect(keys.posts == 1)
        menu.state = .enabled
        menu.onPress = { self.sourceAppCopies("menu") }
        _ = await coordinator().capture(token)
        #expect(keys.posts == 1)
    }

    @Test func modifierTimeoutAbortsSyntheticCopy() async {
        menu.state = .absent
        keys.released = false
        let before = board.changeCount
        #expect(await coordinator().capture(token) == .unsupported(.modifiersHeld))
        #expect(keys.posts == 0)
        #expect(board.changeCount == before)
    }

    @Test func sourceChangedBeforeCopyAborts() async {
        menu.state = .enabled
        focus.pid = 999
        #expect(await coordinator().capture(token) == .failed(.sourceChanged))
        focus.pid = 101
        focus.element = ElementRef("another-field")
        #expect(await coordinator().capture(token) == .failed(.sourceChanged))
        #expect(menu.presses == 0)
    }

    @Test func chromiumGetsManualAccessibilityOnce() async {
        let chrome = InputToken(inputGeneration: 1, kind: .selection,
                                source: InputSource(pid: 303, bundleID: "com.google.Chrome", focusedElement: ElementRef("web")),
                                startedAt: .now)
        ax.selectedText = .value("")
        ax.afterManual = .value("web text")
        // The tree appears two re-queries after the write (asynchronous build).
        ax.manualDelayReads = 2
        let coordinator = coordinator()
        #expect(await coordinator.capture(chrome) == .text("web text", layer: .accessibility))
        // A later press that misses on its first probe does not set the attribute again.
        #expect(await coordinator.capture(chrome) == .nothingSelected)
        #expect(ax.writes == [AXSelectionLayer.manualAccessibilityAttribute])
    }

    @Test func nonzeroRangeWithUnreadableTextIsNotEmpty() async {
        ax.selectedText = .value("")
        ax.range = .value(AXTextRange(location: 0, length: 12))
        ax.rangeString = .error
        menu.state = .enabled
        menu.onPress = { self.sourceAppCopies("copied instead") }
        #expect(await coordinator().capture(token) == .text("copied instead", layer: .menuCopy))
    }

    @Test func unreadableMenuSendsNoKeyEvent() async {
        menu.state = .unknown
        #expect(await coordinator().capture(token) == .failed(.menuUnreadable))
        #expect(keys.posts == 0)
        #expect(menu.presses == 0)
    }

    @Test func modifiersHeldAgainAtPostSendNoKeyEvent() async {
        menu.state = .absent
        var polls = 0
        keys.releasedProvider = {
            polls += 1
            return polls == 1 // released for the wait, held again at the post
        }
        let result = await coordinator().capture(token)
        #expect(keys.posts == 0)
        #expect(result == .failed(.noCopyResult))
    }

    @Test func neverSetsEnhancedUserInterface() async {
        for bundle in AXSelectionLayer.manualAccessibilityBundles {
            let source = InputSource(pid: Int32(bundle.count), bundleID: bundle, focusedElement: ElementRef(bundle))
            _ = await coordinator().capture(InputToken(inputGeneration: 1, kind: .selection, source: source, startedAt: .now))
        }
        #expect(!ax.writes.isEmpty)
        #expect(!ax.writes.contains("AXEnhancedUserInterface"))
    }

    @Test func untrustedReturnsPermissionMissingBeforeAnyLayer() async {
        ax.trusted = false
        menu.state = .enabled
        #expect(await coordinator().capture(token) == .permissionMissing)
        #expect(ax.reads == 0)
        #expect(menu.presses == 0)
        #expect(keys.posts == 0)
    }

    @Test func cancelledInputSendsNoCopy() async {
        menu.state = .enabled
        #expect(await coordinator(current: false).capture(token) == .cancelled)
        #expect(menu.presses == 0)
    }
}
