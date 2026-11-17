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

struct CategoryChart: View {
    var rows: [AggregateRow]
    var total: Double
    @State private var selectedAngle: Double?

    /// The sector under the pointer, found by walking cumulative totals.
    private var selected: AggregateRow? {
        guard let selectedAngle else { return nil }
        var cumulative = 0.0
        for row in rows {
            cumulative += row.total
            if selectedAngle <= cumulative { return row }
        }
        return nil
    }

    var body: some View {
        ChartCard(title: "By category", isEmpty: rows.isEmpty) {
            Chart(rows) { row in
                SectorMark(angle: .value("Total", row.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(by: .value("Category", row.key))
                    .opacity(selected == nil || selected?.key == row.key ? 1 : 0.4)
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: ChartStyle.categoryOrder, range: ChartStyle.categoryColors)
            .chartLegend(position: .trailing, alignment: .center, spacing: 12)
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { proxy in
                GeometryReader { geo in
                    let frame = geo[proxy.plotFrame!]
                    VStack(spacing: 2) {
                        Text(selected?.key ?? "Total").font(.caption).foregroundStyle(.secondary)
                        Text(selected?.total ?? total, format: .currency(code: currency).precision(.fractionLength(0)))
                            .font(.headline).monospacedDigit()
                        if let selected, total > 0 {
                            Text("\(selected.count) inv · \((selected.total / total).formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
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
    @State private var selectedVendor: String?

    var body: some View {
        ChartCard(title: "Top vendors", isEmpty: rows.isEmpty) {
            Chart(rows) { row in
                BarMark(x: .value("Total", row.total), y: .value("Vendor", row.key), height: .ratio(0.6))
                    .foregroundStyle(ChartStyle.accent)
                    .opacity(selectedVendor == nil || selectedVendor == row.key ? 1 : 0.45)
                    .cornerRadius(3)
                    .annotation(position: .trailing, spacing: 6) {
                        Text(selectedVendor == row.key
                             ? "\(row.total.formatted(.currency(code: currency).precision(.fractionLength(2)))) · \(row.count) inv"
                             : row.total.formatted(.currency(code: currency).precision(.fractionLength(0))))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
            }
            .chartYSelection(value: $selectedVendor)
            .chartYScale(domain: rows.map(\.key))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { AxisValueLabel() } }
            .frame(height: 240)
        }
    }
}
