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
                    TimelineChart(rows: data.timeline, granularity: appState.granularity, period: appState.period)
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

    private func filters(_ appState: Bindable<AppState>) -> some View {
        HStack(spacing: 16) {
            Picker("Period", selection: appState.period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
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
