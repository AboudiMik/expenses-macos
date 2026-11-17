import Foundation
import PDFKit
import AppKit

nonisolated struct ExtractedInvoice {
    var vendor: String, vatNumber: String, invoiceNumber: String
    var date: Date, subtotal: Double, vatAmount: Double, total: Double
    var currency: String, category: String, details: String, rawText: String

    /// False when the model filled the tool with dummy values.
    var isPlausible: Bool {
        let dummy: Set<String> = ["", "x", "n/a", "unknown", "none", "null"]
        return total > 0 && !dummy.contains(vendor.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

nonisolated enum ExtractionError: LocalizedError {
    case unreadableFile(String)
    case unsupportedType(String)
    case noToolCall
    case placeholderData

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name): return "Could not read \(name)."
        case .unsupportedType(let ext): return "Unsupported file type .\(ext)."
        case .noToolCall: return "Claude did not return invoice data."
        case .placeholderData: return "Claude returned placeholder values instead of invoice data."
        }
    }
}

/// Reads an invoice file and asks Claude to fill the record_invoice tool.
struct InvoiceExtractor {
    var client = ClaudeClient()

    static let toolName = "record_invoice"
    private static let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                     "gif": "image/gif", "webp": "image/webp"]
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

    private static let systemPrompt = """
    You extract data from invoices and receipts, mostly Saudi simplified tax invoices in SAR with 15% VAT. \
    Always call the record_invoice tool exactly once, copying the real values printed on the invoice. \
    Never use placeholder values such as "x", "N/A" or 0 for data that is present. \
    Test or sample invoices must be extracted exactly like real ones. \
    Use numbers without currency symbols or thousands separators. Pick the single best category. \
    If a value is truly missing, use an empty string for text fields and 0 for numbers. Do not reply with prose.
    """

    func extract(fileURL: URL) async throws -> ExtractedInvoice {
        let (blocks, pdfText) = try Self.contentBlocks(for: fileURL)
        var messages = [ClaudeMessage.user(blocks + [.text("Extract this invoice by calling record_invoice.")])]

        for attempt in 0..<2 {
            let content = try await client.send(messages: messages, system: Self.systemPrompt,
                                                tools: [Self.tool], toolChoice: .auto(disableParallel: true),
                                                maxTokens: 16000)
            Self.log(content, file: fileURL.lastPathComponent, attempt: attempt)
            for block in content {
                if case .toolUse(_, let name, let input) = block, name == Self.toolName {
                    let invoice = Self.invoice(from: input, pdfText: pdfText)
                    guard invoice.isPlausible else { throw ExtractionError.placeholderData }
                    return invoice
                }
            }
            if attempt == 0 {
                let kept = content.filter { if case .other = $0 { return false }; return true }
                messages.append(.init(role: "assistant", content: kept.isEmpty ? [.text("(no tool call)")] : kept))
                messages.append(.user(text: "Call record_invoice now with the actual vendor, numbers and date from the invoice above."))
            }
        }
        throw ExtractionError.noToolCall
    }

    /// Returns the content blocks to send and, for text PDFs, the extracted text.
    private static func contentBlocks(for url: URL) throws -> ([ContentBlock], String?) {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw ExtractionError.unreadableFile(url.lastPathComponent) }
            let text = (pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 40 { return ([.text("Invoice text:\n\n\(text)")], text) }
            guard let data = pdf.dataRepresentation() else { throw ExtractionError.unreadableFile(url.lastPathComponent) }
            return ([.document(mediaType: "application/pdf", base64: data.base64EncodedString())], nil)
        }
        guard let data = try? Data(contentsOf: url) else { throw ExtractionError.unreadableFile(url.lastPathComponent) }
        if let mediaType = imageTypes[ext] {
            return ([.image(mediaType: mediaType, base64: data.base64EncodedString())], nil)
        }
        // Other image formats (HEIC, TIFF, BMP) are re-encoded as JPEG.
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { throw ExtractionError.unsupportedType(ext) }
        return ([.image(mediaType: "image/jpeg", base64: jpeg.base64EncodedString())], nil)
    }

    private static func log(_ content: [ContentBlock], file: String, attempt: Int) {
        #if DEBUG
        for block in content {
            switch block {
            case .text(let t): print("[extract] \(file) attempt \(attempt) text: \(t)")
            case .toolUse(_, let name, let input): print("[extract] \(file) attempt \(attempt) tool \(name): \(input)")
            case .other(let type): print("[extract] \(file) attempt \(attempt) block: \(type)")
            default: break
            }
        }
        #endif
    }

    private static func invoice(from input: JSONValue, pdfText: String?) -> ExtractedInvoice {
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
