import CaptaloCore
import Combine
import SwiftUI

/// The tab the panel shows. `StatusItemController` sets it on every open.
final class PanelSelection: ObservableObject {
    @Published var tab: PanelTab = .read
}

/// The panel in the menu-bar popover: the app's state drawn through `PanelModel`.
struct LivePanelView: View {
    @EnvironmentObject private var state: CaptaloAppState
    @ObservedObject var selection: PanelSelection

    var body: some View {
        PanelRootView(model: .make(state.panelInput), actions: state.panelActions, tab: $selection.tab)
    }
}
