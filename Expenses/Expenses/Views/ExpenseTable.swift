import SwiftUI
import SwiftData

/// Sortable table of expenses with the review badge.
struct ExpenseTable: View {
    var expenses: [Expense]
    @Binding var selection: Set<PersistentIdentifier>
    @Binding var sortOrder: [KeyPathComparator<Expense>]
    var onEdit: (Set<PersistentIdentifier>) -> Void
    var onDelete: (Set<PersistentIdentifier>) -> Void

    var body: some View {
        Table(expenses, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { Text($0.date, format: .dateTime.day().month(.abbreviated).year()) }
                .width(min: 90, ideal: 100)
            TableColumn("Vendor", value: \.vendor) { expense in
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
            TableColumn("VAT", value: \.vatAmount) { Text($0.vatAmount, format: .number.precision(.fractionLength(2))) }
                .width(min: 70, ideal: 80)
            TableColumn("Total", value: \.total) { Text($0.total, format: .currency(code: $0.currency)) }
                .width(min: 100, ideal: 120)
            TableColumn("File", value: \.fileName)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Edit") { onEdit(ids) }.disabled(ids.count != 1)
            Button("Delete", role: .destructive) { onDelete(ids) }
        } primaryAction: { ids in
            onEdit(ids)
        }
    }
}
