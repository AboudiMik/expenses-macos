import Foundation
import Observation

/// Session-wide token counts, fed by ClaudeClient.
@MainActor
@Observable
final class UsageTracker {
    static let shared = UsageTracker()
    private(set) var requests = 0
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0

    func record(input: Int, output: Int) {
        requests += 1
        inputTokens += input
        outputTokens += output
    }
}
