import SwiftUI

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var hasStoredKey = KeychainStore.loadAPIKey()?.isEmpty == false
    @State private var status: String?
    private var usage: UsageTracker { UsageTracker.shared }

    var body: some View {
        Form {
            Section("Claude API") {
                SecureField("API key", text: $apiKey, prompt: Text("sk-ant-..."))
                    .textContentType(.password)
                HStack {
                    Button("Save key") { save() }.disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove key", role: .destructive) { remove() }.disabled(!hasStoredKey)
                    Spacer()
                    Label(hasStoredKey ? "Key stored in Keychain" : "No key stored",
                          systemImage: hasStoredKey ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(hasStoredKey ? .green : .secondary)
                }
                LabeledContent("Extraction model", value: Config.extractionModel)
                LabeledContent("Chat model", value: Config.agentModel)
            }
            Section("Usage this session") {
                LabeledContent("Requests", value: usage.requests, format: .number)
                LabeledContent("Input tokens", value: usage.inputTokens, format: .number)
                LabeledContent("Output tokens", value: usage.outputTokens, format: .number)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }

    private func save() {
        do {
            try KeychainStore.save(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            hasStoredKey = true
            status = "Saved."
        } catch {
            status = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try KeychainStore.deleteAPIKey()
            hasStoredKey = false
            status = "Removed."
        } catch {
            status = error.localizedDescription
        }
    }
}
