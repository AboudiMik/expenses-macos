import Foundation
import Observation

nonisolated struct ChatMessage: Identifiable {
    enum Role { case user, assistant, notice }
    var id = UUID()
    var role: Role
    var text: String
    var toolsUsed: [String] = []
    var pendingDeleteId: UUID? = nil
}

/// Runs the chat: a Claude tool-use loop over AgentTools, keeping history for the session.
@MainActor
@Observable
final class AgentService {
    var messages: [ChatMessage] = []
    var isWorking = false
    private(set) var pendingDelete: Expense?

    private var tools: AgentTools
    private var history: [ClaudeMessage] = []
    private var notes: [String] = []
    private let client = ClaudeClient()
    static let maxSteps = 6

    init(store: ExpenseStore, appState: AppState) {
        tools = AgentTools(store: store, appState: appState)
    }

    private var systemPrompt: String {
        """
        You are the assistant inside Expenses, a macOS expense tracker. Today is \(AgentTools.day(.now)). \
        The currency is \(Config.defaultCurrency). Every number you state (totals, counts, averages, comparisons) \
        must come from a query_spending or list_expenses result in this conversation; never estimate or recall one. \
        Use search_invoices only for questions about what an invoice contains. \
        "Last month" means the previous calendar month; "this year" means from January 1. \
        Changing data happens only through tools; a deletion is only pending until the user confirms it. \
        Answer briefly in plain sentences, and use the tools without asking permission first.
        """
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        messages.append(ChatMessage(role: .user, text: trimmed))
        let prefix = notes.isEmpty ? "" : notes.map { "(\($0))" }.joined(separator: " ") + "\n"
        notes = []
        let historyStart = history.count
        history.append(.user(text: prefix + trimmed))

        var toolsUsed: [String] = []
        var answer = ""
        do {
            for _ in 0..<Self.maxSteps {
                let content = try await client.send(messages: history, system: systemPrompt,
                                                    tools: AgentTools.definitions, toolChoice: .auto(), maxTokens: 8000)
                let kept = content.filter { if case .other = $0 { return false }; return true }
                history.append(ClaudeMessage(role: "assistant", content: kept.isEmpty ? [.text("…")] : kept))

                var results: [ContentBlock] = []
                for block in kept {
                    switch block {
                    case .text(let t): answer = t
                    case .toolUse(let id, let name, let input):
                        toolsUsed.append(name)
                        let result = tools.run(name, input)
                        if name == "delete_expense" { pendingDelete = tools.pendingDelete }
                        results.append(.toolResult(toolUseId: id, content: result, isError: result.hasPrefix("Error")))
                    default: break
                    }
                }
                if results.isEmpty { break }
                history.append(.user(results))
            }
        } catch {
            answer = answer.isEmpty ? error.localizedDescription : answer + "\n\n" + error.localizedDescription
            history.removeSubrange(historyStart...)   // keep history valid for the next turn
        }
        var reply = ChatMessage(role: .assistant, text: answer.isEmpty ? "Done." : answer, toolsUsed: toolsUsed)
        if pendingDelete != nil { reply.pendingDeleteId = reply.id }
        messages.append(reply)
    }

    func confirmDelete() {
        guard let expense = pendingDelete else { return }
        let label = "\(expense.vendor) \(AgentTools.money(expense.total))"
        do {
            try tools.store.delete(expense)
            messages.append(ChatMessage(role: .notice, text: "Deleted \(label)."))
            notes.append("The user confirmed and \(label) was deleted")
        } catch {
            messages.append(ChatMessage(role: .notice, text: "Delete failed: \(error.localizedDescription)"))
        }
        clearPending()
    }

    func cancelDelete() {
        messages.append(ChatMessage(role: .notice, text: "Deletion cancelled."))
        notes.append("The user cancelled the deletion")
        clearPending()
    }

    private func clearPending() {
        pendingDelete = nil
        tools.pendingDelete = nil
        for i in messages.indices { messages[i].pendingDeleteId = nil }
    }
}
