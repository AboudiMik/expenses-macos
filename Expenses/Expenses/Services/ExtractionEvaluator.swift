import Foundation
import Observation

nonisolated struct ExtractionFileResult: Identifiable {
    var fileName: String
    var fields: [FieldResult]
    var error: String?
    var seconds: Double
    var tokens: Int
    var id: String { fileName }
    var mismatches: [FieldResult] { fields.filter { !$0.passed } }
}

nonisolated struct FieldAccuracy: Identifiable {
    var field: String
    var passed: Int
    var total: Int
    var id: String { field }
    var rate: Double { total == 0 ? 0 : Double(passed) / Double(total) }
}

/// Runs InvoiceExtractor over a folder, 3 files at a time, and scores against ground_truth.json if present.
@MainActor
@Observable
final class ExtractionEvaluator {
    var isRunning = false
    var completed = 0
    var total = 0
    var results: [ExtractionFileResult] = []
    var hasGroundTruth = false
    var folderName = ""

    private let extractor = InvoiceExtractor()
    static let fileExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"]

    var fieldAccuracy: [FieldAccuracy] {
        var table: [String: FieldAccuracy] = [:]
        for result in results { for f in result.fields {
            var row = table[f.field] ?? FieldAccuracy(field: f.field, passed: 0, total: 0)
            row.total += 1; row.passed += f.passed ? 1 : 0
            table[f.field] = row
        } }
        let order = ["vendor", "vatNumber", "invoiceNumber", "date", "subtotal", "vatAmount", "total", "currency", "category"]
        return table.values.sorted { (order.firstIndex(of: $0.field) ?? 99) < (order.firstIndex(of: $1.field) ?? 99) }
    }
    var overallAccuracy: Double {
        let all = results.flatMap(\.fields)
        return all.isEmpty ? 0 : Double(all.filter(\.passed).count) / Double(all.count)
    }
    var averageSeconds: Double { results.isEmpty ? 0 : results.map(\.seconds).reduce(0, +) / Double(results.count) }
    var totalTokens: Int { results.map(\.tokens).reduce(0, +) }
    var failures: Int { results.filter { $0.error != nil }.count }

    func run(folder: URL) async {
        guard !isRunning else { return }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { Self.fileExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let truth = GroundTruthRecord.load(folder: folder)
        hasGroundTruth = truth != nil
        folderName = folder.lastPathComponent
        isRunning = true; completed = 0; total = files.count; results = []
        defer { isRunning = false }

        var pending = files.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Config.maxConcurrentImports {
                if let url = pending.next() { group.addTask { await self.evaluate(url, truth: truth) } }
            }
            while await group.next() != nil {
                if let url = pending.next() { group.addTask { await self.evaluate(url, truth: truth) } }
            }
        }
        results.sort { $0.fileName < $1.fileName }
    }

    private func evaluate(_ url: URL, truth: [String: GroundTruthRecord]?) async {
        let name = url.lastPathComponent
        let started = Date()
        defer { completed += 1 }
        do {
            let invoice = try await extractor.extract(fileURL: url)
            let fields = truth?[name].map { FieldComparer.compare($0, with: invoice) } ?? []
            results.append(ExtractionFileResult(fileName: name, fields: fields, error: nil,
                                                seconds: invoice.seconds, tokens: invoice.inputTokens + invoice.outputTokens))
        } catch {
            results.append(ExtractionFileResult(fileName: name, fields: [], error: error.localizedDescription,
                                                seconds: Date().timeIntervalSince(started), tokens: 0))
        }
    }
}
