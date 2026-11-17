import SwiftUI
import Charts

private let currency = Config.defaultCurrency

struct ChartCard<Content: View>: View {
    var title: String
    var isEmpty: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if isEmpty {
                Text("No expenses in this period.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                content
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TimelineChart: View {
    var rows: [AggregateRow]
    var granularity: Granularity
    var period: Period

    var body: some View {
        ChartCard(title: "Spending per \(granularity.rawValue.lowercased()), \(period.rawValue.lowercased())",
                  isEmpty: rows.isEmpty) {
            Chart(rows) { row in
                BarMark(x: .value("Period", row.key), y: .value("Total", row.total), width: .ratio(0.6))
                    .foregroundStyle(ChartStyle.accent)
                    .cornerRadius(3)
            }
            .chartYAxis { AxisMarks(position: .leading) { AxisGridLine(); AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.notation(.compactName)) } }
            .chartXAxis { AxisMarks { AxisValueLabel() } }
            .frame(height: 220)
        }
    }
}

struct CategoryChart: View {
    var rows: [AggregateRow]
    var total: Double

    var body: some View {
        ChartCard(title: "By category", isEmpty: rows.isEmpty) {
            Chart(rows) { row in
                SectorMark(angle: .value("Total", row.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(by: .value("Category", row.key))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: ChartStyle.categoryOrder, range: ChartStyle.categoryColors)
            .chartLegend(position: .trailing, alignment: .center, spacing: 12)
            .chartBackground { proxy in
                GeometryReader { geo in
                    let frame = geo[proxy.plotFrame!]
                    VStack(spacing: 2) {
                        Text("Total").font(.caption).foregroundStyle(.secondary)
                        Text(total, format: .currency(code: currency).precision(.fractionLength(0)))
                            .font(.headline).monospacedDigit()
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(height: 240)
        }
    }
}

struct VendorChart: View {
    var rows: [AggregateRow]

    var body: some View {
        ChartCard(title: "Top vendors", isEmpty: rows.isEmpty) {
            Chart(rows) { row in
                BarMark(x: .value("Total", row.total), y: .value("Vendor", row.key), height: .ratio(0.6))
                    .foregroundStyle(ChartStyle.accent)
                    .cornerRadius(3)
                    .annotation(position: .trailing, spacing: 6) {
                        Text(row.total, format: .currency(code: currency).precision(.fractionLength(0)))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
            }
            .chartYScale(domain: rows.map(\.key))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { AxisValueLabel() } }
            .frame(height: 240)
        }
    }
}
