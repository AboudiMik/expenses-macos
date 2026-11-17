import Foundation

/// One expected record from ground_truth.json. Text fields may list several accepted spellings.
nonisolated struct GroundTruthRecord: Decodable {
    var vendor: [String]?
    var vatNumber: [String]?
    var invoiceNumber: [String]?
    var category: [String]?
    var currency: [String]?
    var date: String?
    var subtotal: Double?
    var vatAmount: Double?
    var total: Double?

    private enum Keys: String, CodingKey { case vendor, vatNumber, invoiceNumber, category, currency, date, subtotal, vatAmount, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func texts(_ key: Keys) -> [String]? {
            if let one = try? c.decode(String.self, forKey: key) { return [one] }
            return try? c.decode([String].self, forKey: key)
        }
        func number(_ key: Keys) -> Double? {
            (try? c.decode(Double.self, forKey: key)) ?? (try? c.decode(String.self, forKey: key)).flatMap(Double.init)
        }
        vendor = texts(.vendor); vatNumber = texts(.vatNumber); invoiceNumber = texts(.invoiceNumber)
        category = texts(.category); currency = texts(.currency)
        date = try? c.decode(String.self, forKey: .date)
        subtotal = number(.subtotal); vatAmount = number(.vatAmount); total = number(.total)
    }

    static func load(folder: URL) -> [String: GroundTruthRecord]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("ground_truth.json")) else { return nil }
        return try? JSONDecoder().decode([String: GroundTruthRecord].self, from: data)
    }
}

nonisolated struct FieldResult: Identifiable {
    var field: String
    var expected: String
    var actual: String
    var passed: Bool
    var id: String { field }
}

nonisolated enum FieldComparer {
    static let amountTolerance = 0.05

    /// Compares every field the record has. Fields missing from the truth are skipped.
    static func compare(_ truth: GroundTruthRecord, with invoice: ExtractedInvoice) -> [FieldResult] {
        var results: [FieldResult] = []
        func text(_ name: String, _ expected: [String]?, _ actual: String) {
            guard let expected else { return }
            let hit = expected.contains { normalize($0) == normalize(actual) }
            results.append(FieldResult(field: name, expected: expected.joined(separator: " | "), actual: actual, passed: hit))
        }
        func amount(_ name: String, _ expected: Double?, _ actual: Double) {
            guard let expected else { return }
            results.append(FieldResult(field: name, expected: String(format: "%.2f", expected),
                                       actual: String(format: "%.2f", actual), passed: abs(expected - actual) <= amountTolerance))
        }
        text("vendor", truth.vendor, invoice.vendor)
        text("vatNumber", truth.vatNumber, invoice.vatNumber)
        text("invoiceNumber", truth.invoiceNumber, invoice.invoiceNumber)
        if let expected = truth.date {
            let actual = day(invoice.date)
            results.append(FieldResult(field: "date", expected: expected, actual: actual, passed: expected == actual))
        }
        amount("subtotal", truth.subtotal, invoice.subtotal)
        amount("vatAmount", truth.vatAmount, invoice.vatAmount)
        amount("total", truth.total, invoice.total)
        text("currency", truth.currency, invoice.currency)
        text("category", truth.category, invoice.category)
        return results
    }

    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "  ", with: " ")
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: date)
    }
}
