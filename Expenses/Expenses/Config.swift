import Foundation

/// App-wide constants. The API key is never stored here; see KeychainStore.
nonisolated enum Config {
    static let model = "claude-sonnet-5-5"
    static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"
    static let maxTokens = 4096
    static let keychainService = "magnaai.Expenses"
    static let keychainAccount = "anthropic-api-key"
    static let maxConcurrentImports = 3
    static let defaultCurrency = "SAR"
}
