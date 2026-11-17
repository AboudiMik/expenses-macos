import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EvaluationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var extraction = ExtractionEvaluator()
    @State private var agent = AgentEvaluator()
    @State private var choosingFolder = false
    @State private var exporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                extractionSection
                Divider()
                agentSection
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 600)
        .navigationTitle("Evaluation")
        .toolbar {
            Button("Export Markdown…") { exporting = true }
                .disabled(extraction.results.isEmpty && agent.results.isEmpty)
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await extraction.run(folder: url) } }
        }
        .fileExporter(isPresented: $exporting, document: MarkdownFile(text: markdown),
                      contentType: .plainText, defaultFilename: "evaluation.md") { _ in }
    }

    private var markdown: String {
        let summary = extraction.results.isEmpty ? nil : ExtractionSummary(
            folder: extraction.folderName, files: extraction.results.count, errors: extraction.failures,
            overall: extraction.overallAccuracy, averageSeconds: extraction.averageSeconds, tokens: extraction.totalTokens,
            fields: extraction.fieldAccuracy, results: extraction.results)
        return EvaluationReport.markdown(extraction: summary, agent: agent.results, agentPassRate: agent.passRate)
    }

    private var extractionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Extraction test").font(.title3.weight(.semibold))
                Spacer()
                Button("Choose folder and run…") { choosingFolder = true }.disabled(extraction.isRunning)
            }
            Text("Runs the extractor on every PDF or image in the folder without saving anything. Scores against ground_truth.json when present.")
                .font(.callout).foregroundStyle(.secondary)
            if extraction.isRunning {
                ProgressView(value: Double(extraction.completed), total: Double(max(extraction.total, 1)))
                Text("\(extraction.completed)/\(extraction.total) files").font(.caption).foregroundStyle(.secondary)
            }
            if !extraction.results.isEmpty {
                HStack(spacing: 24) {
                    stat("Files", "\(extraction.results.count)")
                    if extraction.hasGroundTruth { stat("Overall accuracy", extraction.overallAccuracy.formatted(.percent.precision(.fractionLength(1)))) }
                    stat("Avg seconds / file", String(format: "%.1f", extraction.averageSeconds))
                    stat("Total tokens", extraction.totalTokens.formatted())
                    stat("Errors", "\(extraction.failures)")
                }
                if extraction.hasGroundTruth {
                    Table(extraction.fieldAccuracy) {
                        TableColumn("Field", value: \.field)
                        TableColumn("Correct") { Text("\($0.passed) / \($0.total)") }
                        TableColumn("Accuracy") { Text($0.rate, format: .percent.precision(.fractionLength(1))) }
                    }
                    .frame(height: 240)
                    mismatchList
                } else {
                    Text("No ground_truth.json in this folder, so only timing and token counts are shown.").foregroundStyle(.secondary)
                }
                ForEach(extraction.results.filter { $0.error != nil }) { r in
                    Text("\(r.fileName): \(r.error ?? "")").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var mismatchList: some View {
        let rows = extraction.results.flatMap { r in r.mismatches.map { MismatchRow(file: r.fileName, result: $0) } }
        return Group {
            Text(rows.isEmpty ? "No mismatches." : "Mismatches (\(rows.count))").font(.headline)
            if !rows.isEmpty {
                Table(rows) {
                    TableColumn("File", value: \.file)
                    TableColumn("Field", value: \.result.field)
                    TableColumn("Expected", value: \.result.expected)
                    TableColumn("Actual", value: \.result.actual)
                }
                .frame(height: min(400, CGFloat(rows.count) * 28 + 40))
            }
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agent test").font(.title3.weight(.semibold))
                Spacer()
                if agent.isRunning { ProgressView().controlSize(.small) }
                Button("Run 6 questions") {
                    Task { await agent.run(store: ExpenseStore(context: modelContext), appState: appState) }
                }
                .disabled(agent.isRunning)
            }
            Text("Each question is answered by the chat agent against the current database and checked against ExpenseStore.")
                .font(.callout).foregroundStyle(.secondary)
            if !agent.results.isEmpty {
                stat("Pass rate", agent.passRate.formatted(.percent.precision(.fractionLength(0))))
                ForEach(agent.results) { q in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(q.question, systemImage: q.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(q.passed ? .green : .red)
                        Text("Expected \(q.expectedNumber, format: .number.precision(.fractionLength(2))) · tools: \(q.toolsUsed.joined(separator: ", ")) · number \(q.numberPassed ? "found" : "missing")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(q.answer).font(.callout).textSelection(.enabled)
                    }
                    .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct MismatchRow: Identifiable {
    var file: String
    var result: FieldResult
    var id: String { file + result.field }
}

struct MarkdownFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
