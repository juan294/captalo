import SwiftUI

@main
struct CaptaloApp: App {
    @NSApplicationDelegateAdaptor(CaptaloApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        // The window is the app's own; no default "Settings…" (Cmd+,) item.
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}
