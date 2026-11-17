import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            List(Screen.allCases, selection: $appState.screen) { screen in
                Label(screen.rawValue, systemImage: screen.systemImage).tag(screen)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch appState.screen {
            case .dashboard: DashboardView()
            case .invoices: InvoicesView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
