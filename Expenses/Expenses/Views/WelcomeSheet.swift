import SwiftUI

/// Shown on launch while no Claude API key is stored.
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Welcome to Expenses", systemImage: "doc.text.magnifyingglass").font(.title2.weight(.semibold))
            Text("Importing invoices and chatting use Claude. Add a Claude API key in Settings to get started. The key is stored in your Keychain and never leaves this Mac except to call the Anthropic API.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Get a key at console.anthropic.com → API Keys.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
                SettingsLink { Text("Open Settings") }.keyboardShortcut(.defaultAction)
                    .simultaneousGesture(TapGesture().onEnded { dismiss() })
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
