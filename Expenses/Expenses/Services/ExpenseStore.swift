import Foundation
import SwiftData

nonisolated struct ExpenseFilter {
    var from: Date? = nil
    var to: Date? = nil
    var category: String? = nil
    var vendorContains: String? = nil
}

nonisolated enum Grouping: String, CaseIterable {
    case day, month, year, category, vendor
}

nonisolated struct AggregateRow: Identifiable {
    var key: String
    var total: Double
    var count: Int
    var id: String { key }
}

/// All reads and writes of Expense go through here. Numbers in the app come from these functions.
@MainActor
final class ExpenseStore {
    let context: ModelContext
    let rag: RAGService

    init(context: ModelContext) {
        self.context = context
        self.rag = RAGService(context: context)
    }

    @discardableResult
    func add(_ extracted: ExtractedInvoice, fileName: String) throws -> Expense {
        let expense = Expense(
            vendor: extracted.vendor, vatNumber: extracted.vatNumber,
            invoiceNumber: extracted.invoiceNumber, date: extracted.date,
            subtotal: extracted.subtotal, vatAmount: extracted.vatAmount, total: extracted.total,
            currency: extracted.currency, category: extracted.category, details: extracted.details,
            fileName: fileName, rawText: extracted.rawText)
        context.insert(expense)
        try context.save()
        try rag.index(expense)
        return expense
    }

    /// Call after editing an Expense's properties in place.
    func update(_ expense: Expense) throws {
        expense.category = ExpenseCategory.normalized(expense.category)
        try context.save()
    }

    func delete(_ expense: Expense) throws {
        context.delete(expense)
        try context.save()
    }

    func delete(_ expenses: [Expense]) throws {
        expenses.forEach { context.delete($0) }
        try context.save()
    }

    func list(_ filter: ExpenseFilter = ExpenseFilter()) throws -> [Expense] {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let from = filter.from, let to = filter.to {
            descriptor.predicate = #Predicate { $0.date >= from && $0.date <= to }
        } else if let from = filter.from {
            descriptor.predicate = #Predicate { $0.date >= from }
        } else if let to = filter.to {
            descriptor.predicate = #Predicate { $0.date <= to }
        }
        var result = try context.fetch(descriptor)
        if let category = filter.category, !category.isEmpty {
            result = result.filter { $0.category == category }
        }
        if let vendor = filter.vendorContains, !vendor.isEmpty {
            result = result.filter { $0.vendor.localizedCaseInsensitiveContains(vendor) }
        }
        return result
    }

    /// Totals grouped by day, month, year, category or vendor, sorted by key.
    func aggregate(by grouping: Grouping, from: Date? = nil, to: Date? = nil,
                   category: String? = nil, vendor: String? = nil) throws -> [AggregateRow] {
        let expenses = try list(ExpenseFilter(from: from, to: to, category: category, vendorContains: vendor))
        let formatter = DateFormatter()
        switch grouping {
        case .day: formatter.dateFormat = "yyyy-MM-dd"
        case .month: formatter.dateFormat = "yyyy-MM"
        case .year: formatter.dateFormat = "yyyy"
        case .category, .vendor: break
        }
        var rows: [String: AggregateRow] = [:]
        for expense in expenses {
            let key: String
            switch grouping {
            case .category: key = expense.category
            case .vendor: key = expense.vendor
            default: key = formatter.string(from: expense.date)
            }
            var row = rows[key] ?? AggregateRow(key: key, total: 0, count: 0)
            row.total += expense.total
            row.count += 1
            rows[key] = row
        }
        return rows.values.sorted { $0.key < $1.key }
    }

    func total(from: Date? = nil, to: Date? = nil, category: String? = nil, vendor: String? = nil) throws -> Double {
        try list(ExpenseFilter(from: from, to: to, category: category, vendorContains: vendor)).reduce(0) { $0 + $1.total }
    }
}
