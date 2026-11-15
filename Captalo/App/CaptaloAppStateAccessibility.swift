extension CaptaloAppState {
    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = accessibility.isProcessTrusted()
        guard !accessibilityPermissionGranted else { return }
        onAccessibilityPermissionRequired?()
    }

    func openAccessibilitySettings() {
        accessibility.openAccessibilitySettings()
    }
}
