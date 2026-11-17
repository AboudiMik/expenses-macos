import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var expenses: [Expense]   // triggers refresh on insert/delete; numbers come from ExpenseStore

    var body: some View {
        @Bindable var appState = appState
        let data = DashboardData.load(store: ExpenseStore(context: modelContext), state: appState)
        let _ = expenses.count
        ScrollView {
            if !data.hasAnyData {
                ContentUnavailableView("Nothing to show yet", systemImage: "chart.pie",
                                       description: Text("Import a few invoices and the dashboard will fill in."))
                    .frame(minHeight: 400)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    kpiRow(data)
                    filters($appState)
                    if data.periodIsEmpty, let span = data.dataSpan { emptyPeriodBanner(span) }
                    TimelineChart(rows: data.timeline, granularity: appState.granularity, period: appState.period,
                                  range: appState.dateRange)
                    HStack(alignment: .top, spacing: 20) {
                        CategoryChart(rows: data.byCategory, total: data.periodTotal)
                        VendorChart(rows: data.topVendors)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Dashboard")
    }

    private func kpiRow(_ data: DashboardData) -> some View {
        HStack(spacing: 16) {
            KPICard(title: "This month", amount: data.thisMonth)
            KPICard(title: "Last month", amount: data.lastMonth)
            KPICard(title: "This year", amount: data.thisYear)
            KPICard(title: "Invoices", count: data.invoiceCount)
        }
    }

    private func emptyPeriodBanner(_ span: (first: Date, last: Date)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
            Text("No invoices in this period. Your data runs from \(span.first, format: .dateTime.day().month(.abbreviated).year()) to \(span.last, format: .dateTime.day().month(.abbreviated).year()).")
            Spacer()
            Button("Show all time") { appState.showAllTime() }
            Button("Show that range") { appState.showCustom(from: span.first, to: span.last) }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func filters(_ appState: Bindable<AppState>) -> some View {
        HStack(spacing: 16) {
            Picker("Period", selection: appState.period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 480)
            if appState.wrappedValue.period == .custom {
                DatePicker("From", selection: appState.customFrom, displayedComponents: .date).labelsHidden()
                Text("to").foregroundStyle(.secondary)
                DatePicker("To", selection: appState.customTo, in: appState.wrappedValue.customFrom..., displayedComponents: .date).labelsHidden()
            }
            Picker("Granularity", selection: appState.granularity) {
                ForEach(Granularity.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 200)
            Spacer()
            Picker("Category", selection: appState.category) {
                Text("All categories").tag(String?.none)
                ForEach(ExpenseCategory.allCases, id: \.rawValue) { Text($0.rawValue).tag(String?.some($0.rawValue)) }
            }
            .frame(maxWidth: 200)
        }
    }
}

struct KPICard: View {
    var title: String
    var amount: Double? = nil
    var count: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            if let amount {
                Text(amount, format: .currency(code: Config.defaultCurrency).precision(.fractionLength(0)))
                    .font(.title2.weight(.semibold)).monospacedDigit()
            } else if let count {
                Text(count, format: .number).font(.title2.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
