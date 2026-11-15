import SwiftUI

@main
struct CaptaloApp: App {
    @NSApplicationDelegateAdaptor(CaptaloApplicationDelegate.self) private var applicationDelegate
    @StateObject private var state: CaptaloAppState

    init() {
        _state = StateObject(wrappedValue: CaptaloAppState.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            CaptaloMenuBarView()
                .environmentObject(state)
        } label: {
            Image(nsImage: state.statusIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)
    }
}
