/// Apps where Copy can produce content without a selection. Their Copy
/// layers are disabled (review R2). Other apps' preferences are never changed.
public enum CopyPolicy {
    public static let copyWithoutSelection: Set<String> = [
        // editor.emptySelectionClipboard (default on) copies the current line.
        "com.microsoft.VSCode",
    ]

    /// Apps that report an empty Accessibility selection and a disabled Copy
    /// item while text is selected (owner decision D31, 2026-11-19). Their
    /// empty answers are not evidence, so capture goes straight to a synthetic
    /// Copy. In Rex, a synthetic Cmd+C with nothing selected reaches no program
    /// and leaves the clipboard unchanged (owner check, 2026-11-19).
    public static let selectionHidden: Set<String> = [
        "com.superlogical.rex",
    ]

    public static func hidesSelection(bundleID: String?) -> Bool {
        bundleID.map(selectionHidden.contains) ?? false
    }

    public static func allowsCopy(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return !copyWithoutSelection.contains(bundleID)
    }
}
