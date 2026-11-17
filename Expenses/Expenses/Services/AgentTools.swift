import Foundation
import SwiftData

/// Tool definitions and their execution against ExpenseStore, RAGService and AppState.
@MainActor
struct AgentTools {
    let store: ExpenseStore
    let appState: AppState
    /// Short session ids ("E1", "E2") the model uses to refer to expenses.
    var ids: [String: PersistentIdentifier] = [:]
    var pendingDelete: Expense?

    private static let categories = JSONValue.array(ExpenseCategory.allCases.map { .string($0.rawValue) })
    private static let date: JSONValue = ["type": "string", "description": "YYYY-MM-DD"]

    static let definitions: [ClaudeTool] = [
        ClaudeTool(name: "query_spending",
                   description: "Spending totals from the database. Use for any amount, sum, count or comparison. group_by 'total' returns one row.",
                   inputSchema: ["type": "object", "properties": [
                       "group_by": ["type": "string", "enum": ["total", "day", "month", "year", "category", "vendor"]],
                       "start_date": date, "end_date": date,
                       "category": ["type": "string", "enum": categories],
                       "vendor": ["type": "string", "description": "Case-insensitive substring of the vendor name"],
                   ], "required": ["group_by"]], strict: false),
        ClaudeTool(name: "list_expenses",
                   description: "List individual expenses, newest first, with their ids for update_expense and delete_expense.",
                   inputSchema: ["type": "object", "properties": [
                       "start_date": date, "end_date": date,
                       "category": ["type": "string", "enum": categories],
                       "vendor": ["type": "string"], "limit": ["type": "integer", "description": "Default 20"],
                   ]], strict: false),
        ClaudeTool(name: "search_invoices",
                   description: "Semantic search over the text of stored invoices. Use only for what an invoice contains (items, descriptions), never for totals.",
                   inputSchema: ["type": "object", "properties": ["question": ["type": "string"]], "required": ["question"]], strict: false),
        ClaudeTool(name: "add_expense",
                   description: "Add a manual expense. If subtotal and vatAmount are omitted, the total is treated as VAT-inclusive at 15%.",
                   inputSchema: ["type": "object", "properties": [
                       "vendor": ["type": "string"], "total": ["type": "number"], "date": date,
                       "category": ["type": "string", "enum": categories], "details": ["type": "string"],
                       "subtotal": ["type": "number"], "vatAmount": ["type": "number"],
                       "currency": ["type": "string"], "invoiceNumber": ["type": "string"], "vatNumber": ["type": "string"],
                   ], "required": ["vendor", "total", "date", "category"]], strict: false),
        ClaudeTool(name: "update_expense",
                   description: "Change fields of an expense identified by an id from list_expenses. Only provided fields change.",
                   inputSchema: ["type": "object", "properties": [
                       "id": ["type": "string"], "vendor": ["type": "string"], "total": ["type": "number"], "date": date,
                       "category": ["type": "string", "enum": categories], "details": ["type": "string"],
                       "subtotal": ["type": "number"], "vatAmount": ["type": "number"], "invoiceNumber": ["type": "string"],
                   ], "required": ["id"]], strict: false),
        ClaudeTool(name: "delete_expense",
                   description: "Ask to delete an expense by id. The user must confirm with a button; tell them to confirm.",
                   inputSchema: ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]], strict: false),
        ClaudeTool(name: "show_chart",
                   description: "Switch to the Dashboard and set its period, granularity and category filter. Give start_date and end_date for a specific range (period becomes Custom).",
                   inputSchema: ["type": "object", "properties": [
                       "period": ["type": "string", "enum": ["This month", "Last 3 months", "Past year", "All time", "Custom"]],
                       "start_date": date, "end_date": date,
                       "granularity": ["type": "string", "enum": ["Day", "Month", "Year"]],
                       "category": ["type": "string", "description": "A category name, or 'all'"],
                   ]], strict: false),
        ClaudeTool(name: "open_screen",
                   description: "Show a screen of the app.",
                   inputSchema: ["type": "object", "properties": ["name": ["type": "string", "enum": ["Dashboard", "Invoices"]]],
                                 "required": ["name"]], strict: false),
    ]

    mutating func run(_ name: String, _ input: JSONValue) -> String {
        do {
            switch name {
            case "query_spending": return try querySpending(input)
            case "list_expenses": return try listExpenses(input)
            case "search_invoices": return try searchInvoices(input)
            case "add_expense": return try addExpense(input)
            case "update_expense": return try updateExpense(input)
            case "delete_expense": return try deleteExpense(input)
            case "show_chart": return showChart(input)
            case "open_screen":
                appState.screen = input["name"]?.stringValue == "Invoices" ? .invoices : .dashboard
                return "Showing \(appState.screen.rawValue)."
            default: return "Error: unknown tool \(name)"
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func querySpending(_ input: JSONValue) throws -> String {
        let (from, to) = Self.dates(input)
        let category = input["category"]?.stringValue, vendor = input["vendor"]?.stringValue
        let group = input["group_by"]?.stringValue ?? "total"
        if let grouping = Grouping(rawValue: group) {
            let rows = try store.aggregate(by: grouping, from: from, to: to, category: category, vendor: vendor)
            return rows.isEmpty ? "No expenses match." : rows.map { "\($0.key): \(Self.money($0.total)) (\($0.count) invoices)" }.joined(separator: "\n")
        }
        let total = try store.total(from: from, to: to, category: category, vendor: vendor)
        let count = try store.list(ExpenseFilter(from: from, to: to, category: category, vendorContains: vendor)).count
        return "total: \(Self.money(total)) across \(count) invoices"
    }

    private mutating func listExpenses(_ input: JSONValue) throws -> String {
        let (from, to) = Self.dates(input)
        let filter = ExpenseFilter(from: from, to: to, category: input["category"]?.stringValue, vendorContains: input["vendor"]?.stringValue)
        let limit = Int(input["limit"]?.doubleValue ?? 20)
        let rows = try store.list(filter).prefix(max(limit, 1))
        if rows.isEmpty { return "No expenses match." }
        return rows.map { "\(id(for: $0)) | \(Self.day($0.date)) | \($0.vendor) | \($0.category) | \(Self.money($0.total)) | \($0.invoiceNumber)" }
            .joined(separator: "\n")
    }

    private func searchInvoices(_ input: JSONValue) throws -> String {
        let passages = try store.rag.search(input["question"]?.stringValue ?? "")
        if passages.isEmpty { return "No matching invoice text." }
        return passages.map { "[\($0.vendor), \(Self.day($0.date)), \($0.invoiceNumber)]\n\($0.text)" }.joined(separator: "\n---\n")
    }

    private func addExpense(_ input: JSONValue) throws -> String {
        let total = input["total"]?.doubleValue ?? 0
        let subtotal = input["subtotal"]?.doubleValue ?? (total / 1.15 * 100).rounded() / 100
        let extracted = ExtractedInvoice(
            vendor: input["vendor"]?.stringValue ?? "", vatNumber: input["vatNumber"]?.stringValue ?? "",
            invoiceNumber: input["invoiceNumber"]?.stringValue ?? "",
            date: Self.parse(input["date"]?.stringValue) ?? .now, subtotal: subtotal,
            vatAmount: input["vatAmount"]?.doubleValue ?? ((total - subtotal) * 100).rounded() / 100, total: total,
            currency: input["currency"]?.stringValue?.uppercased() ?? Config.defaultCurrency,
            category: ExpenseCategory.normalized(input["category"]?.stringValue),
            details: input["details"]?.stringValue ?? "", rawText: input["details"]?.stringValue ?? "")
        let expense = try store.add(extracted, fileName: "manual")
        return "Added \(expense.vendor) \(Self.money(expense.total)) on \(Self.day(expense.date)) as \(expense.category)."
    }

    private func updateExpense(_ input: JSONValue) throws -> String {
        guard let expense = expense(for: input["id"]?.stringValue) else { return "Error: unknown id. Call list_expenses first." }
        if let v = input["vendor"]?.stringValue { expense.vendor = v }
        if let v = input["total"]?.doubleValue { expense.total = v }
        if let v = input["subtotal"]?.doubleValue { expense.subtotal = v }
        if let v = input["vatAmount"]?.doubleValue { expense.vatAmount = v }
        if let v = input["category"]?.stringValue { expense.category = v }
        if let v = input["details"]?.stringValue { expense.details = v }
        if let v = input["invoiceNumber"]?.stringValue { expense.invoiceNumber = v }
        if let v = Self.parse(input["date"]?.stringValue) { expense.date = v }
        try store.update(expense)
        return "Updated \(expense.vendor) \(Self.money(expense.total)) on \(Self.day(expense.date))."
    }

    private mutating func deleteExpense(_ input: JSONValue) throws -> String {
        guard let expense = expense(for: input["id"]?.stringValue) else { return "Error: unknown id. Call list_expenses first." }
        pendingDelete = expense
        return "Pending: deletion of \(expense.vendor) \(Self.money(expense.total)) on \(Self.day(expense.date)) needs the user's confirmation via the button shown in the chat. Do not claim it is deleted."
    }

    private func showChart(_ input: JSONValue) -> String {
        if let p = input["period"]?.stringValue, let period = Period(rawValue: p) { appState.period = period }
        if let from = Self.parse(input["start_date"]?.stringValue), let to = Self.parse(input["end_date"]?.stringValue) {
            appState.showCustom(from: from, to: to)
        }
        if let g = input["granularity"]?.stringValue, let granularity = Granularity(rawValue: g) { appState.granularity = granularity }
        if let c = input["category"]?.stringValue {
            appState.category = c.lowercased() == "all" ? nil : ExpenseCategory.normalized(c)
        }
        appState.screen = .dashboard
        return "Dashboard shows \(appState.period.rawValue) by \(appState.granularity.rawValue.lowercased()), category \(appState.category ?? "all")."
    }

    private mutating func id(for expense: Expense) -> String {
        if let existing = ids.first(where: { $0.value == expense.persistentModelID }) { return existing.key }
        let key = "E\(ids.count + 1)"
        ids[key] = expense.persistentModelID
        return key
    }

    private func expense(for id: String?) -> Expense? {
        guard let id, let pid = ids[id] else { return nil }
        return store.context.model(for: pid) as? Expense
    }

    private static func dates(_ input: JSONValue) -> (Date?, Date?) {
        let from = parse(input["start_date"]?.stringValue)
        let to = parse(input["end_date"]?.stringValue).map { Calendar.current.date(byAdding: .day, value: 1, to: $0)!.addingTimeInterval(-1) }
        return (from, to)
    }

    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: text)
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: date)
    }

    static func money(_ value: Double) -> String {
        String(format: "%.2f %@", value, Config.defaultCurrency)
    }
}
