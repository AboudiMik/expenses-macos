import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InvoicesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var importer = InvoiceImporter()
    @State private var selection = Set<PersistentIdentifier>()
    @State private var showingImporter = false
    @State private var editing: Expense?
    @State private var confirmingDelete = false
    @State private var reviewOnly = false

    private var visibleExpenses: [Expense] { reviewOnly ? expenses.filter(\.needsReview) : expenses }

    private var selectedExpenses: [Expense] { expenses.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            if importer.isRunning { progressBar }
            table
        }
        .navigationTitle("Invoices")
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await importer.importFiles(urls, into: ExpenseStore(context: modelContext)) }
            }
        }
        .sheet(item: $editing) { expense in
            ExpenseEditView(expense: expense, store: ExpenseStore(context: modelContext))
        }
        .confirmationDialog("Duplicate invoice", isPresented: duplicateShown, titleVisibility: .visible) {
            Button("Skip this file") { importer.resolveDuplicate(keep: false) }
            Button("Keep both") { importer.resolveDuplicate(keep: true) }
        } message: {
            if let d = importer.pendingDuplicate {
                Text("\(d.fileName) looks like an invoice already saved: \(d.vendor), invoice \(d.invoiceNumber).")
            }
        }
        .confirmationDialog("Delete \(selection.count) expense(s)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Import finished with notes", isPresented: failuresShown) {
            Button("OK") { importer.failures = []; importer.skipped = [] }
        } message: {
            Text((importer.failures.map { "\($0.fileName): \($0.message)" }
                  + importer.skipped.map { "\($0): skipped as duplicate" }).joined(separator: "\n"))
        }
    }

    private var failuresShown: Binding<Bool> {
        Binding(get: { !importer.isRunning && !(importer.failures.isEmpty && importer.skipped.isEmpty) },
                set: { if !$0 { importer.failures = []; importer.skipped = [] } })
    }

    private var duplicateShown: Binding<Bool> {
        Binding(get: { importer.pendingDuplicate != nil },
                set: { if !$0, importer.pendingDuplicate != nil { importer.resolveDuplicate(keep: false) } })
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(importer.completed), total: Double(max(importer.total, 1)))
            Text("Processing \(importer.completed)/\(importer.total): \(importer.currentFiles.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var table: some View {
        Table(visibleExpenses, selection: $selection) {
            TableColumn("Date") { Text($0.date, format: .dateTime.day().month(.abbreviated).year()) }
                .width(min: 90, ideal: 100)
            TableColumn("Vendor") { expense in
                HStack(spacing: 6) {
                    Text(expense.vendor)
                    if expense.needsReview {
                        Text("Needs review").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.25), in: Capsule()).help(expense.reviewNotes)
                    }
                }
            }
            TableColumn("Invoice #", value: \.invoiceNumber).width(min: 90, ideal: 120)
            TableColumn("Category", value: \.category).width(min: 80, ideal: 100)
            TableColumn("VAT") { Text($0.vatAmount, format: .number.precision(.fractionLength(2))) }
                .width(min: 70, ideal: 80)
            TableColumn("Total") { Text($0.total, format: .currency(code: $0.currency)) }
                .width(min: 100, ideal: 120)
            TableColumn("File", value: \.fileName)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Edit") { editFirst(of: ids) }.disabled(ids.count != 1)
            Button("Delete", role: .destructive) { selection = ids; confirmingDelete = true }
        } primaryAction: { ids in
            editFirst(of: ids)
        }
        .overlay {
            if expenses.isEmpty && !importer.isRunning {
                ContentUnavailableView("No invoices yet", systemImage: "doc.text",
                                       description: Text("Click Import to add PDF or image invoices."))
            } else if visibleExpenses.isEmpty {
                ContentUnavailableView("Nothing needs review", systemImage: "checkmark.circle")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { showingImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .disabled(importer.isRunning)
        }
        ToolbarItem {
            Toggle(isOn: $reviewOnly) { Label("Needs review", systemImage: "exclamationmark.triangle") }
                .help("Show only expenses that need review")
        }
        ToolbarItem {
            Button { editFirst(of: selection) } label: { Label("Edit", systemImage: "pencil") }
                .disabled(selection.count != 1)
        }
        ToolbarItem {
            Button { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                .disabled(selection.isEmpty)
        }
    }

    private func editFirst(of ids: Set<PersistentIdentifier>) {
        editing = expenses.first { ids.contains($0.id) }
    }

    private func deleteSelected() {
        try? ExpenseStore(context: modelContext).delete(selectedExpenses)
        selection = []
    }
}
