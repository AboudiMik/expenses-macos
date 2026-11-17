import SwiftUI
import SwiftData

struct ExpenseEditView: View {
    @Bindable var expense: Expense
    let store: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Invoice") {
                    TextField("Vendor", text: $expense.vendor)
                    TextField("VAT number", text: $expense.vatNumber)
                    TextField("Invoice number", text: $expense.invoiceNumber)
                    DatePicker("Date", selection: $expense.date, displayedComponents: .date)
                    Picker("Category", selection: $expense.category) {
                        ForEach(ExpenseCategory.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                }
                Section("Amounts") {
                    TextField("Subtotal", value: $expense.subtotal, format: .number.precision(.fractionLength(2)))
                    TextField("VAT amount", value: $expense.vatAmount, format: .number.precision(.fractionLength(2)))
                    TextField("Total", value: $expense.total, format: .number.precision(.fractionLength(2)))
                    TextField("Currency", text: $expense.currency)
                }
                Section("Details") {
                    TextField("Line items", text: $expense.details, axis: .vertical).lineLimit(2...6)
                    LabeledContent("File", value: expense.fileName)
                }
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }
            HStack {
                Spacer()
                Button("Cancel") { store.context.rollback(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
    }

    private func save() {
        do {
            try store.update(expense)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
