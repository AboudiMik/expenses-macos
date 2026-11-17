import Foundation
import Observation

nonisolated struct ImportFailure: Identifiable {
    var id = UUID()
    var fileName: String
    var message: String
}

nonisolated struct PendingDuplicate: Identifiable {
    var id = UUID()
    var fileName: String
    var vendor: String
    var invoiceNumber: String
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
    var skipped: [String] = []
    /// Set while the UI asks whether to skip a duplicate or keep both.
    var pendingDuplicate: PendingDuplicate?

    private let extractor = InvoiceExtractor()
    private var duplicateDecision: CheckedContinuation<Bool, Never>?

    func importFiles(_ urls: [URL], into store: ExpenseStore) async {
        guard !isRunning, !urls.isEmpty else { return }
        isRunning = true
        completed = 0
        total = urls.count
        failures = []
        skipped = []
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
            if try store.findDuplicate(vendor: extracted.vendor, invoiceNumber: extracted.invoiceNumber) != nil,
               await !shouldKeep(PendingDuplicate(fileName: name, vendor: extracted.vendor, invoiceNumber: extracted.invoiceNumber)) {
                skipped.append(name)
                return
            }
            try store.add(extracted, fileName: name)
        } catch {
            failures.append(ImportFailure(fileName: name, message: error.localizedDescription))
        }
    }

    /// Asks the user, one prompt at a time. Returns true to keep both.
    private func shouldKeep(_ duplicate: PendingDuplicate) async -> Bool {
        while pendingDuplicate != nil { try? await Task.sleep(for: .milliseconds(200)) }
        pendingDuplicate = duplicate
        return await withCheckedContinuation { duplicateDecision = $0 }
    }

    func resolveDuplicate(keep: Bool) {
        pendingDuplicate = nil
        duplicateDecision?.resume(returning: keep)
        duplicateDecision = nil
    }
}
