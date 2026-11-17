import SwiftUI
import Charts

/// Spending over time on a real date axis, so sparse days stay readable and labels thin out automatically.
struct TimelineChart: View {
    var rows: [AggregateRow]
    var granularity: Granularity
    var period: Period
    var range: (from: Date?, to: Date?)
    @State private var selectedDate: Date?

    private struct Point: Identifiable {
        var date: Date, total: Double, count: Int
        var id: Date { date }
    }

    private var unit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .month: return .month
        case .year: return .year
        }
    }

    private var points: [Point] {
        let f = DateFormatter()
        f.dateFormat = granularity == .day ? "yyyy-MM-dd" : granularity == .month ? "yyyy-MM" : "yyyy"
        return rows.compactMap { row in f.date(from: row.key).map { Point(date: $0, total: row.total, count: row.count) } }
    }

    private var selected: Point? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.date, equalTo: selectedDate, toGranularity: unit) }
    }

    private var domain: ClosedRange<Date>? {
        guard let from = range.from, let to = range.to, from < to else { return nil }
        return from...to
    }

    var body: some View {
        ChartCard(title: "Spending per \(granularity.rawValue.lowercased()), \(period.rawValue.lowercased())",
                  isEmpty: rows.isEmpty) {
            chart
        }
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(x: .value("Period", point.date, unit: unit), y: .value("Total", point.total))
                .foregroundStyle(ChartStyle.accent)
                .opacity(selected == nil || selected?.date == point.date ? 1 : 0.45)
                .cornerRadius(3)
            if let selected {
                RuleMark(x: .value("Selected", selected.date, unit: unit))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: label(for: selected.date), total: selected.total, count: selected.count)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .modifier(DateDomain(domain: domain))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) {
                AxisGridLine()
                AxisValueLabel(format: axisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.notation(.compactName))
            }
        }
        .frame(height: 220)
    }

    private var axisFormat: Date.FormatStyle {
        switch granularity {
        case .day: return .dateTime.day().month(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).year(.twoDigits)
        case .year: return .dateTime.year()
        }
    }

    private func label(for date: Date) -> String {
        switch granularity {
        case .day: return date.formatted(.dateTime.day().month(.abbreviated).year())
        case .month: return date.formatted(.dateTime.month(.wide).year())
        case .year: return date.formatted(.dateTime.year())
        }
    }
}

/// Applies a fixed date domain only when the period is bounded.
private struct DateDomain: ViewModifier {
    var domain: ClosedRange<Date>?
    func body(content: Content) -> some View {
        if let domain { content.chartXScale(domain: domain) } else { content }
    }
}

struct ChartTooltip: View {
    var title: String
    var total: Double
    var count: Int
    var share: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(total, format: .currency(code: Config.defaultCurrency).precision(.fractionLength(2)))
                .font(.callout.weight(.semibold)).monospacedDigit()
            Text(share.map { "\(count) invoice\(count == 1 ? "" : "s") · \($0.formatted(.percent.precision(.fractionLength(0))))" }
                 ?? "\(count) invoice\(count == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
    }
}
