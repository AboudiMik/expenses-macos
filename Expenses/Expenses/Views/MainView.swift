import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var agent: AgentService?

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            List(Screen.allCases, selection: $appState.screen) { screen in
                Label(screen.rawValue, systemImage: screen.systemImage).tag(screen)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            HStack(spacing: 0) {
                Group {
                    switch appState.screen {
                    case .dashboard: DashboardView()
                    case .invoices: InvoicesView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                if let agent {
                    ChatView(agent: agent).frame(width: 340)
                }
            }
        }
        .frame(minWidth: 1180, minHeight: 600)
        .task {
            let store = ExpenseStore(context: modelContext)
            if agent == nil { agent = AgentService(store: store, appState: appState) }
            try? store.rag.indexMissing()
        }
    }
}
