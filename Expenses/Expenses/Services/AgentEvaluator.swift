import Foundation
import Observation

nonisolated struct AgentQuestionResult: Identifiable {
    var question: String
    var expectedTool: String
    var expectedNumber: Double
    var toolsUsed: [String]
    var answer: String
    var toolPassed: Bool
    var numberPassed: Bool
    var id: String { question }
    var passed: Bool { toolPassed && numberPassed }
}

/// Asks AgentService six fixed questions and checks tool choice and the number in the answer against ExpenseStore.
@MainActor
@Observable
final class AgentEvaluator {
    var isRunning = false
    var results: [AgentQuestionResult] = []
    var passRate: Double { results.isEmpty ? 0 : Double(results.filter(\.passed).count) / Double(results.count) }

    func run(store: ExpenseStore, appState: AppState) async {
        guard !isRunning else { return }
        isRunning = true; results = []
        defer { isRunning = false }
        let cal = Calendar.current, now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let lastMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart)!
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
        let threeMonthsStart = cal.date(byAdding: .month, value: -2, to: monthStart)!

        let questions: [(String, String, () throws -> Double)] = [
            ("How much did I spend last month?", "query_spending",
             { try store.total(from: lastMonthStart, to: monthStart.addingTimeInterval(-1)) }),
            ("How much did I spend this year?", "query_spending",
             { try store.total(from: yearStart, to: now) }),
            ("What was my total spending in the past 3 months?", "query_spending",
             { try store.total(from: threeMonthsStart, to: now) }),
            ("Which category did I spend the most on this year, and how much?", "query_spending",
             { try store.aggregate(by: .category, from: yearStart, to: now).max { $0.total < $1.total }?.total ?? 0 }),
            ("Which vendor did I spend the most with overall, and how much?", "query_spending",
             { try store.aggregate(by: .vendor).max { $0.total < $1.total }?.total ?? 0 }),
            ("How many invoices do I have in total?", "query_spending",
             { Double(try store.list().count) }),
        ]
        for (question, tool, expected) in questions {
            let agent = AgentService(store: store, appState: appState)   // fresh history per question
            let value = (try? expected()) ?? 0
            await agent.send(question)
            let reply = agent.messages.last(where: { $0.role == .assistant })
            let answer = reply?.text ?? ""
            let tools = reply?.toolsUsed ?? []
            results.append(AgentQuestionResult(
                question: question, expectedTool: tool, expectedNumber: value, toolsUsed: tools, answer: answer,
                toolPassed: tools.contains(tool) || (tool == "query_spending" && tools.contains("list_expenses")),
                numberPassed: Self.contains(answer, value)))
        }
    }

    /// True if the answer contains the number in any common formatting.
    static func contains(_ answer: String, _ value: Double) -> Bool {
        let compact = answer.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "٬", with: "")
        var forms = [String(format: "%.2f", value), String(format: "%.1f", value), String(format: "%.0f", value)]
        if value == value.rounded() { forms.append(String(Int(value))) }
        return forms.contains { compact.contains($0) }
    }
}
