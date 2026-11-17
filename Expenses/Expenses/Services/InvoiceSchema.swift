import Foundation

/// The record_invoice tool schema and the conversion of its input into an ExtractedInvoice.
nonisolated enum InvoiceSchema {
    static let toolName = "record_invoice"
    private static let categories = ExpenseCategory.allCases.map { JSONValue.string($0.rawValue) }

    static let tool = ClaudeTool(
        name: toolName,
        description: "Record the structured data of one invoice or receipt.",
        inputSchema: [
            "type": "object", "additionalProperties": false,
            "properties": [
                "vendor": ["type": "string", "description": "Seller name as printed"],
                "vatNumber": ["type": "string", "description": "15-digit VAT registration number, or empty string"],
                "invoiceNumber": ["type": "string", "description": "Invoice or receipt number, or empty string"],
                "date": ["type": "string", "description": "Invoice date as YYYY-MM-DD"],
                "subtotal": ["type": "number", "description": "Amount before VAT"],
                "vatAmount": ["type": "number", "description": "VAT amount"],
                "total": ["type": "number", "description": "Amount including VAT"],
                "currency": ["type": "string", "description": "ISO currency code, e.g. SAR"],
                "category": ["type": "string", "enum": .array(categories)],
                "details": ["type": "string", "description": "Line items as 'description x qty = amount', separated by '; '"],
                "fullText": ["type": ["string", "null"],
                             "description": "Complete visible text of the invoice when it was given as an image or document; null when given as text"],
            ],
            "required": ["vendor", "vatNumber", "invoiceNumber", "date", "subtotal", "vatAmount",
                         "total", "currency", "category", "details", "fullText"],
        ])

    static func invoice(from input: JSONValue, pdfText: String?) -> ExtractedInvoice {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let currency = input["currency"]?.stringValue?.uppercased() ?? ""
        return ExtractedInvoice(
            vendor: input["vendor"]?.stringValue ?? "",
            vatNumber: input["vatNumber"]?.stringValue ?? "",
            invoiceNumber: input["invoiceNumber"]?.stringValue ?? "",
            date: input["date"]?.stringValue.flatMap { formatter.date(from: $0) } ?? .now,
            subtotal: input["subtotal"]?.doubleValue ?? 0,
            vatAmount: input["vatAmount"]?.doubleValue ?? 0,
            total: input["total"]?.doubleValue ?? 0,
            currency: currency.isEmpty ? Config.defaultCurrency : currency,
            category: ExpenseCategory.normalized(input["category"]?.stringValue),
            details: input["details"]?.stringValue ?? "",
            rawText: pdfText ?? input["fullText"]?.stringValue ?? "")
    }
}
