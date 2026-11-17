import Foundation
import PDFKit
import AppKit

nonisolated struct ExtractedInvoice {
    var vendor: String, vatNumber: String, invoiceNumber: String
    var date: Date, subtotal: Double, vatAmount: Double, total: Double
    var currency: String, category: String, details: String, rawText: String
    var needsReview = false
    var reviewNotes = ""
    var wasCorrected = false
    var inputTokens = 0, outputTokens = 0, seconds = 0.0

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

    private static let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                     "gif": "image/gif", "webp": "image/webp"]

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
        let name = fileURL.lastPathComponent

        var usage = (input: 0, output: 0, seconds: 0.0)
        var invoice = try await requestInvoice(&messages, pdfText: pdfText, file: name, usage: &usage)
        var failures = InvoiceValidator.check(invoice)
        if !failures.isEmpty {
            // Self-correction: show the failed checks and the previous answer, ask for a re-read.
            let previous = "vendor \(invoice.vendor), date \(Self.day(invoice.date)), subtotal \(invoice.subtotal), VAT \(invoice.vatAmount), total \(invoice.total)"
            messages.append(.user(text: """
                Your previous answer (\(previous)) failed these checks:
                - \(failures.joined(separator: "\n- "))
                Re-read the document carefully and call record_invoice again with corrected values. \
                If the document itself is inconsistent, copy the printed values exactly.
                """))
            let second = try await requestInvoice(&messages, pdfText: pdfText, file: name, usage: &usage)
            let secondFailures = InvoiceValidator.check(second)
            invoice = second
            invoice.wasCorrected = secondFailures.isEmpty
            failures = secondFailures
        }
        invoice.needsReview = !failures.isEmpty
        invoice.reviewNotes = failures.joined(separator: "; ")
        invoice.inputTokens = usage.input; invoice.outputTokens = usage.output; invoice.seconds = usage.seconds
        return invoice
    }

    /// One extraction round trip; retries once if the model answers without the tool. Appends the assistant turn.
    private func requestInvoice(_ messages: inout [ClaudeMessage], pdfText: String?, file: String,
                                usage: inout (input: Int, output: Int, seconds: Double)) async throws -> ExtractedInvoice {
        for attempt in 0..<2 {
            let response = try await client.send(messages: messages, system: Self.systemPrompt,
                                                 tools: [InvoiceSchema.tool], toolChoice: .auto(disableParallel: true),
                                                 maxTokens: 16000, model: Config.extractionModel)
            usage.input += response.inputTokens; usage.output += response.outputTokens; usage.seconds += response.seconds
            Self.log(response.content, file: file, attempt: attempt)
            let kept = response.content.filter { if case .other = $0 { return false }; return true }
            messages.append(.init(role: "assistant", content: kept.isEmpty ? [.text("(no tool call)")] : kept))
            for block in kept {
                if case .toolUse(_, let name, let input) = block, name == InvoiceSchema.toolName {
                    let invoice = InvoiceSchema.invoice(from: input, pdfText: pdfText)
                    guard invoice.isPlausible else { throw ExtractionError.placeholderData }
                    return invoice
                }
            }
            if attempt == 0 {
                messages.append(.user(text: "Call record_invoice now with the actual vendor, numbers and date from the invoice above."))
            }
        }
        throw ExtractionError.noToolCall
    }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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
}
