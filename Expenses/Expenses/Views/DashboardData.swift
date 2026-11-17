import Foundation

/// Everything the dashboard shows, computed from ExpenseStore for the current AppState.
nonisolated struct DashboardData {
    var thisMonth: Double = 0
    var lastMonth: Double = 0
    var thisYear: Double = 0
    var invoiceCount: Int = 0
    var timeline: [AggregateRow] = []
    var byCategory: [AggregateRow] = []
    var topVendors: [AggregateRow] = []
    var periodTotal: Double = 0
    var hasAnyData = false
    var dataSpan: (first: Date, last: Date)? = nil
    var periodIsEmpty: Bool { hasAnyData && timeline.isEmpty }

    @MainActor
    static func load(store: ExpenseStore, state: AppState, now: Date = .now) -> DashboardData {
        var data = DashboardData()
        let calendar = Calendar.current
        let category = state.category
        let range = state.dateRange
        do {
            let all = try store.list()
            data.hasAnyData = !all.isEmpty
            if let newest = all.first, let oldest = all.last { data.dataSpan = (oldest.date, newest.date) }
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
            let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!
            data.thisMonth = try store.total(from: monthStart, to: now, category: category)
            data.lastMonth = try store.total(from: lastMonthStart, to: monthStart.addingTimeInterval(-1), category: category)
            data.thisYear = try store.total(from: yearStart, to: now, category: category)
            data.invoiceCount = try store.list(ExpenseFilter(category: category)).count

            data.timeline = try store.aggregate(by: state.granularity.grouping, from: range.from, to: range.to, category: category)
            data.byCategory = try store.aggregate(by: .category, from: range.from, to: range.to, category: category)
                .sorted { ChartStyle.categoryOrder.firstIndex(of: $0.key) ?? 99 < ChartStyle.categoryOrder.firstIndex(of: $1.key) ?? 99 }
            data.topVendors = Array(try store.aggregate(by: .vendor, from: range.from, to: range.to, category: category)
                .sorted { $0.total > $1.total }.prefix(5))
            data.periodTotal = try store.total(from: range.from, to: range.to, category: category)
        } catch {
            print("[dashboard] load failed: \(error)")
        }
        return data
    }
}
