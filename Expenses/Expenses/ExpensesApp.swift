import SwiftUI
import SwiftData

@main
struct ExpensesApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Expense.self, InvoiceChunk.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }
    }
}
