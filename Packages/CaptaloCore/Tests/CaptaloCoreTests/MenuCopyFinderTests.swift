import Foundation
import Testing
@testable import CaptaloCore

/// A fake menu tree: Accessibility is not owned code. Elements are names.
final class FakeMenuTree: MenuTreeReading, @unchecked Sendable {
    var menuBar: AXRead<String> = .value("bar")
    var children: [String: AXRead<[String]>] = [:]
    var keys: [String: AXRead<MenuKeyEquivalent>] = [:]
    var enabled: AXRead<Bool> = .value(true)
    var onPress: () -> Void = {}
    private(set) var pressed: [String] = []

    func menuBar(pid: Int32) -> AXRead<String> { menuBar }
    func children(_ element: String) -> AXRead<[String]> { children[element] ?? .unsupported }
    func keyEquivalent(_ item: String) -> AXRead<MenuKeyEquivalent> {
        keys[item] ?? .value(MenuKeyEquivalent(character: nil, modifiers: nil))
    }
    func isEnabled(_ item: String) -> AXRead<Bool> { enabled }
    func press(_ item: String) -> Bool {
        pressed.append(item)
        MainActor.assumeIsolated { onPress() }
        return true
    }

    /// File > (New, Close); Edit > (Undo, `editItem`).
    static func standard(editItem: String = "copy", editKey: AXRead<MenuKeyEquivalent> = .value(cmd("c"))) -> FakeMenuTree {
        let tree = FakeMenuTree()
        tree.children = [
            "bar": .value(["file", "edit"]),
            "file": .value(["file-menu"]), "file-menu": .value(["new", "close"]),
            "edit": .value(["edit-menu"]), "edit-menu": .value(["undo", editItem]),
        ]
        tree.keys = ["new": .value(cmd("n")), "close": .value(cmd("w")), "undo": .value(cmd("z")), editItem: editKey]
        return tree
    }

    static func cmd(_ character: String) -> MenuKeyEquivalent { MenuKeyEquivalent(character: character, modifiers: 0) }
}

/// VAL-02: the production traversal classifies the menu; only an
/// established absence of Copy authorizes the synthetic Cmd+C.
extension CaptureCoordinatorTests {
    @Test func menuChildrenTimeoutIsUnreadable() async {
        let tree = FakeMenuTree.standard()
        // The Edit menu's item list times out: Copy may be there.
        tree.children["edit-menu"] = .error
        let finder = MenuCopyFinder(tree: tree)
        #expect(finder.copyItemState(pid: sourceA.pid) == .unknown)
        #expect(await coordinator(menu: finder).capture(token) == .failed(.menuUnreadable))
        #expect(keys.posts == 0)
        #expect(tree.pressed.isEmpty)
    }

    @Test func keyEquivalentErrorIsUnreadable() async {
        let tree = FakeMenuTree.standard(editItem: "mystery", editKey: .error)
        let finder = MenuCopyFinder(tree: tree)
        #expect(finder.copyItemState(pid: sourceA.pid) == .unknown)
        #expect(await coordinator(menu: finder).capture(token) == .failed(.menuUnreadable))
        #expect(keys.posts == 0)
    }

    @Test func readableTreeWithCopyPressesTheItem() async {
        let tree = FakeMenuTree.standard()
        // An unreadable item elsewhere does not hide a Copy item that was found.
        tree.children["file-menu"] = .error
        tree.onPress = { self.sourceAppCopies("copied by menu") }
        let finder = MenuCopyFinder(tree: tree)
        #expect(await coordinator(menu: finder).capture(token) == .text("copied by menu", layer: .menuCopy))
        #expect(tree.pressed == ["copy"])
        #expect(keys.posts == 0)
    }

    @Test func readableTreeWithoutCopyAllowsSyntheticCopy() async {
        // Leaves without children (unsupported) and an item without a key
        // equivalent are established absences, not unknowns.
        let tree = FakeMenuTree.standard(editItem: "paste", editKey: .value(FakeMenuTree.cmd("v")))
        tree.keys["undo"] = .unsupported
        keys.onPost = { self.sourceAppCopies("copied by key") }
        let finder = MenuCopyFinder(tree: tree)
        #expect(finder.copyItemState(pid: sourceA.pid) == .absent)
        #expect(await coordinator(menu: finder).capture(token) == .text("copied by key", layer: .syntheticCopy))
        #expect(keys.posts == 1)
    }

    @Test func copyKeyNeedsCommandOnly() {
        #expect(FakeMenuTree.cmd("C").isCopy)
        #expect(!MenuKeyEquivalent(character: "c", modifiers: 1).isCopy) // Shift
        #expect(!MenuKeyEquivalent(character: "c", modifiers: nil).isCopy)
        #expect(!MenuKeyEquivalent(character: nil, modifiers: 0).isCopy)
    }
}
