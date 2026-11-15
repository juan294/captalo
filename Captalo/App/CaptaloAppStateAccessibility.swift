extension CaptaloAppState {
    /// Updates the permission row; the window's opening is decided by `requireSetup()`.
    func refreshAccessibilityPermission() {
        let trusted = accessibility.isProcessTrusted()
        if trusted != accessibilityPermissionGranted { accessibilityPermissionGranted = trusted }
    }

    func openAccessibilitySettings() {
        accessibility.openAccessibilitySettings()
    }
}
