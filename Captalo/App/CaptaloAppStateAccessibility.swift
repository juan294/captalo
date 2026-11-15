extension CaptaloAppState {
    func requestAccessibilityPermission() {
        refreshAccessibilityPermission()
    }

    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = accessibility.isProcessTrusted()
        guard !accessibilityPermissionGranted else { return }

        updateStatus("Accessibility access required")
        onAccessibilityPermissionRequired?()
    }

    func openAccessibilitySettings() {
        accessibility.openAccessibilitySettings()
    }
}
