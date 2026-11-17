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
    @State private var searchText = ""
    @State private var period: Period = .allTime
    @State private var sortOrder = [KeyPathComparator(\Expense.date, order: .reverse)]

    private var visibleExpenses: [Expense] {
        let range = period.range()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return expenses.filter { expense in
            (!reviewOnly || expense.needsReview)
            && (range.from.map { expense.date >= $0 } ?? true)
            && (range.to.map { expense.date <= $0 } ?? true)
            && (query.isEmpty || expense.vendor.localizedCaseInsensitiveContains(query)
                || expense.invoiceNumber.localizedCaseInsensitiveContains(query)
                || expense.details.localizedCaseInsensitiveContains(query)
                || expense.category.localizedCaseInsensitiveContains(query))
        }
        .sorted(using: sortOrder)
    }

    private var selectedExpenses: [Expense] { expenses.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            if importer.isRunning { progressBar }
            table
        }
        .navigationTitle("Invoices")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Vendor, invoice number, item or category")
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
        ExpenseTable(expenses: visibleExpenses, selection: $selection, sortOrder: $sortOrder,
                     onEdit: { editFirst(of: $0) },
                     onDelete: { selection = $0; confirmingDelete = true })
        .overlay {
            if expenses.isEmpty && !importer.isRunning {
                ContentUnavailableView("No invoices yet", systemImage: "doc.text",
                                       description: Text("Click Import to add PDF or image invoices."))
            } else if visibleExpenses.isEmpty {
                ContentUnavailableView(reviewOnly ? "Nothing needs review" : "No matching invoices",
                                       systemImage: reviewOnly ? "checkmark.circle" : "magnifyingglass")
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
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .help("Show only invoices dated in this period")
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
