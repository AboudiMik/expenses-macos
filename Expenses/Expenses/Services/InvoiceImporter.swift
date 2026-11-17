import Foundation
import Observation

nonisolated struct ImportFailure: Identifiable {
    var id = UUID()
    var fileName: String
    var message: String
}

/// Runs invoice extraction for a batch of files, a few at a time, and reports progress.
@MainActor
@Observable
final class InvoiceImporter {
    var isRunning = false
    var completed = 0
    var total = 0
    var currentFiles: [String] = []
    var failures: [ImportFailure] = []

    private let extractor = InvoiceExtractor()

    func importFiles(_ urls: [URL], into store: ExpenseStore) async {
        guard !isRunning, !urls.isEmpty else { return }
        isRunning = true
        completed = 0
        total = urls.count
        failures = []
        defer { isRunning = false; currentFiles = [] }

        var pending = urls.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Config.maxConcurrentImports {
                if let url = pending.next() { group.addTask { await self.process(url, store: store) } }
            }
            while await group.next() != nil {
                if let url = pending.next() { group.addTask { await self.process(url, store: store) } }
            }
        }
    }

    private func process(_ url: URL, store: ExpenseStore) async {
        let name = url.lastPathComponent
        currentFiles.append(name)
        defer {
            currentFiles.removeAll { $0 == name }
            completed += 1
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let extracted = try await extractor.extract(fileURL: url)
            try store.add(extracted, fileName: name)
        } catch {
            failures.append(ImportFailure(fileName: name, message: error.localizedDescription))
        }
    }
}
