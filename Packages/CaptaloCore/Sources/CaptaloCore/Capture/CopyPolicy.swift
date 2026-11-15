/// Apps where Copy can produce content without a selection. Their Copy
/// layers are disabled (review R2). Other apps' preferences are never changed.
public enum CopyPolicy {
    public static let copyWithoutSelection: Set<String> = [
        // editor.emptySelectionClipboard (default on) copies the current line.
        "com.microsoft.VSCode",
    ]

    public static func allowsCopy(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return !copyWithoutSelection.contains(bundleID)
    }
}
