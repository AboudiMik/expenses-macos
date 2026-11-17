import Foundation
import SwiftData

nonisolated enum ExpenseCategory: String, CaseIterable, Codable {
    case food = "Food"
    case transport = "Transport"
    case utilities = "Utilities"
    case office = "Office"
    case software = "Software"
    case travel = "Travel"
    case health = "Health"
    case other = "Other"

    static func normalized(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespaces).capitalized
        return ExpenseCategory(rawValue: value)?.rawValue ?? ExpenseCategory.other.rawValue
    }
}

@Model
final class Expense {
    var vendor: String
    var vatNumber: String
    var invoiceNumber: String
    var date: Date
    var subtotal: Double
    var vatAmount: Double
    var total: Double
    var currency: String
    var category: String
    var details: String
    var fileName: String
    var rawText: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \InvoiceChunk.expense) var chunks: [InvoiceChunk] = []

    init(vendor: String, vatNumber: String, invoiceNumber: String, date: Date,
         subtotal: Double, vatAmount: Double, total: Double,
         currency: String = Config.defaultCurrency, category: String,
         details: String, fileName: String, rawText: String, createdAt: Date = .now) {
        self.vendor = vendor
        self.vatNumber = vatNumber
        self.invoiceNumber = invoiceNumber
        self.date = date
        self.subtotal = subtotal
        self.vatAmount = vatAmount
        self.total = total
        self.currency = currency
        self.category = category
        self.details = details
        self.fileName = fileName
        self.rawText = rawText
        self.createdAt = createdAt
    }
}
