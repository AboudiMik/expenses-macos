import Foundation

/// Arithmetic and sanity checks on an extracted or edited expense. Returns the failed checks.
nonisolated enum InvoiceValidator {
    static let tolerance = 0.05
    static let vatRate = 0.15

    static func check(vendor: String, date: Date, subtotal: Double, vatAmount: Double, total: Double,
                      now: Date = .now) -> [String] {
        var failures: [String] = []
        if vendor.trimmingCharacters(in: .whitespaces).isEmpty { failures.append("Vendor is missing") }
        if total <= 0 { failures.append("Total is missing or zero") }
        if abs(subtotal + vatAmount - total) > tolerance {
            failures.append(String(format: "Subtotal %.2f + VAT %.2f ≠ total %.2f", subtotal, vatAmount, total))
        }
        if abs(vatAmount - subtotal * vatRate) > tolerance {
            failures.append(String(format: "VAT %.2f is not 15%% of subtotal %.2f (expected %.2f)", vatAmount, subtotal, subtotal * vatRate))
        }
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: now) ?? now
        if date > endOfToday { failures.append("Date is in the future") }
        if date < fiveYearsAgo { failures.append("Date is more than 5 years old") }
        return failures
    }

    static func check(_ invoice: ExtractedInvoice) -> [String] {
        check(vendor: invoice.vendor, date: invoice.date, subtotal: invoice.subtotal,
              vatAmount: invoice.vatAmount, total: invoice.total)
    }

    static func check(_ expense: Expense) -> [String] {
        check(vendor: expense.vendor, date: expense.date, subtotal: expense.subtotal,
              vatAmount: expense.vatAmount, total: expense.total)
    }
}
