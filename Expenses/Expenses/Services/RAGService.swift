import Foundation
import SwiftData
import NaturalLanguage

nonisolated struct RAGPassage {
    var text: String
    var vendor: String
    var date: Date
    var invoiceNumber: String
    var score: Double
}

/// Chunks and embeds invoice text so the agent can answer "what does this invoice contain" questions.
@MainActor
final class RAGService {
    let context: ModelContext
    nonisolated static let chunkSize = 500
    nonisolated static let topK = 4
    private let embedder = NLEmbedding.sentenceEmbedding(for: .english)

    init(context: ModelContext) {
        self.context = context
    }

    /// Replaces the chunks of an expense from its rawText.
    func index(_ expense: Expense) throws {
        expense.chunks.forEach { context.delete($0) }
        expense.chunks = []
        let header = "Vendor: \(expense.vendor) | Invoice: \(expense.invoiceNumber) | Date: \(Self.day(expense.date)) | Category: \(expense.category)"
        for (i, piece) in Self.split(expense.rawText).enumerated() {
            let text = header + "\n" + piece
            let vector = embedder?.vector(for: text) ?? []
            context.insert(InvoiceChunk(index: i, text: text, embedding: vector, expense: expense))
        }
        try context.save()
    }

    /// Indexes expenses that have text but no chunks yet (e.g. saved before RAG existed).
    func indexMissing() throws {
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        for expense in expenses where expense.chunks.isEmpty && !expense.rawText.isEmpty {
            try index(expense)
        }
    }

    func search(_ question: String, limit: Int = RAGService.topK) throws -> [RAGPassage] {
        let chunks = try context.fetch(FetchDescriptor<InvoiceChunk>())
        let queryVector = embedder?.vector(for: question)
        let terms = Self.terms(question)
        // Hybrid: keyword overlap always counts; cosine similarity is added when embeddings exist.
        let scored: [(InvoiceChunk, Double)] = chunks.compactMap { chunk in
            var score = Self.keywordScore(terms, in: chunk.text)
            if let queryVector, !chunk.embedding.isEmpty {
                score += Self.cosine(queryVector, chunk.embedding)
            }
            return score > 0 ? (chunk, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).compactMap { chunk, score in
            guard let expense = chunk.expense else { return nil }
            return RAGPassage(text: chunk.text, vendor: expense.vendor, date: expense.date,
                              invoiceNumber: expense.invoiceNumber, score: score)
        }
    }

    static func split(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if current.count + line.count + 1 > chunkSize, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { chunks.append(current) }
        if chunks.count > 1, chunks[chunks.count - 1].count < 120 {   // merge a tiny tail into the previous chunk
            let tail = chunks.removeLast()
            chunks[chunks.count - 1] += "\n" + tail
        }
        return chunks
    }

    private static let stopwords: Set<String> = ["what", "did", "buy", "from", "the", "and", "for", "how", "much",
                                                 "was", "were", "with", "that", "this", "invoice", "receipt", "bought"]

    private static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func terms(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    private static func keywordScore(_ terms: [String], in text: String) -> Double {
        guard !terms.isEmpty else { return 0 }
        let lower = text.lowercased()
        return Double(terms.filter { lower.contains($0) }.count) / Double(terms.count)
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }
}
