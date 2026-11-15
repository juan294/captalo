import SwiftUI

@main
struct CaptaloApp: App {
    @NSApplicationDelegateAdaptor(CaptaloApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
