import Foundation

/// A menu item's key equivalent. A nil field is an attribute the item does
/// not have (an established absence, not a read error).
public struct MenuKeyEquivalent: Equatable, Sendable {
    public let character: String?
    /// The `AXMenuItemCmdModifiers` mask; 0 means Command only.
    public let modifiers: Int?

    public init(character: String?, modifiers: Int?) {
        self.character = character
        self.modifiers = modifiers
    }

    /// Cmd+C with no other modifier.
    public var isCopy: Bool {
        character?.caseInsensitiveCompare("c") == .orderedSame && modifiers == 0
    }
}

/// The Accessibility reads the Copy-item search needs. The app reads
/// `AXUIElement`s; tests use a fake tree. `.unsupported` is an established
/// absence; `.error` (timeout, cannot complete) is unknown.
public protocol MenuTreeReading: Sendable {
    associatedtype Element
    func menuBar(pid: Int32) -> AXRead<Element>
    func children(_ element: Element) -> AXRead<[Element]>
    func keyEquivalent(_ item: Element) -> AXRead<MenuKeyEquivalent>
    func isEnabled(_ item: Element) -> AXRead<Bool>
    func press(_ item: Element) -> Bool
}

/// Finds the app's own Copy menu item (Cmd+C, no other modifiers).
/// Language-independent: it matches the key equivalent, not the title.
public final class MenuCopyFinder<Tree: MenuTreeReading>: MenuCopyAccess, @unchecked Sendable {
    private let tree: Tree
    /// The item found by the last state query, pressed without a second menu
    /// walk. Elements need not be Sendable, so the slot is guarded by a lock.
    private let lock = NSLock()
    private var lastItem: (pid: Int32, item: Tree.Element)?

    public init(tree: Tree) {
        self.tree = tree
    }

    public func copyItemState(pid: Int32) -> MenuCopyState {
        let state: MenuCopyState
        var found: Tree.Element?
        switch copyItem(pid: pid) {
        case .absent: state = .absent
        case .unreadable: state = .unknown
        case let .found(item):
            found = item
            switch tree.isEnabled(item) {
            case let .value(enabled): state = enabled ? .enabled : .disabled
            case .unsupported, .error: state = .unknown
            }
        }
        lock.withLock { lastItem = found.map { (pid, $0) } }
        return state
    }

    public func pressCopy(pid: Int32) -> Bool {
        let item = lock.withLock { () -> Tree.Element? in
            defer { lastItem = nil }
            return lastItem?.pid == pid ? lastItem?.item : nil
        }
        guard let item else { return false }
        return tree.press(item)
    }

    private enum Lookup {
        case found(Tree.Element)
        case absent
        case unreadable
    }

    /// `.absent` only when every read in the walk established its answer and
    /// no Copy item exists. A read error anywhere (a child list or a key
    /// equivalent) keeps the answer unknown, so no synthetic key is sent.
    /// A Copy item that was found is used even if another part was unreadable.
    private func copyItem(pid: Int32) -> Lookup {
        let menuBar: Tree.Element
        switch tree.menuBar(pid: pid) {
        case let .value(element): menuBar = element
        case .unsupported: return .absent
        case .error: return .unreadable
        }
        var unknown = false
        func children(_ element: Tree.Element) -> [Tree.Element] {
            switch tree.children(element) {
            case let .value(children): return children
            case .unsupported: return []
            case .error: unknown = true; return []
            }
        }
        for topLevel in children(menuBar) {
            for menu in children(topLevel) {
                for item in children(menu) {
                    switch tree.keyEquivalent(item) {
                    case let .value(key) where key.isCopy: return .found(item)
                    case .value, .unsupported: continue
                    case .error: unknown = true
                    }
                }
            }
        }
        return unknown ? .unreadable : .absent
    }
}
