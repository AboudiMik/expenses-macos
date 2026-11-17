import Foundation
import Observation

nonisolated enum Screen: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case invoices = "Invoices"
    var id: String { rawValue }
    var systemImage: String { self == .dashboard ? "chart.bar.xaxis" : "doc.text" }
}

nonisolated enum Period: String, CaseIterable, Identifiable {
    case thisMonth = "This month"
    case lastThreeMonths = "Last 3 months"
    case pastYear = "Past year"
    case allTime = "All time"
    var id: String { rawValue }

    /// Start and end dates for the period; nil means unbounded.
    func range(now: Date = .now, calendar: Calendar = .current) -> (from: Date?, to: Date?) {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        switch self {
        case .thisMonth: return (startOfMonth, now)
        case .lastThreeMonths: return (calendar.date(byAdding: .month, value: -2, to: startOfMonth), now)
        case .pastYear: return (calendar.date(byAdding: .month, value: -11, to: startOfMonth), now)
        case .allTime: return (nil, nil)
        }
    }
}

nonisolated enum Granularity: String, CaseIterable, Identifiable {
    case day = "Day", month = "Month", year = "Year"
    var id: String { rawValue }
    var grouping: Grouping {
        switch self {
        case .day: return .day
        case .month: return .month
        case .year: return .year
        }
    }
}

/// UI state that both the user and, later, the agent can change.
@MainActor
@Observable
final class AppState {
    var screen: Screen = .dashboard
    var period: Period = .pastYear
    var granularity: Granularity = .month
    var category: String? = nil
}
