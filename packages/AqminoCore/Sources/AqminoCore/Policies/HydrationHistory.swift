import Foundation

public enum HydrationHistoryPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, yesterday, last7Days, last30Days
    public var id: String { rawValue }
    public var dayCount: Int {
        switch self { case .today, .yesterday: return 1; case .last7Days: return 7; case .last30Days: return 30 }
    }
}

public struct HydrationDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let records: [HydrationRecord]
    public var id: Date { date }
    public var totalMl: Int { records.reduce(0) { $0 + $1.amountMl } }
    public var count: Int { records.count }
}

/// Calendar days in the current viewing time zone, including days with no records.
/// Multi-day periods include today; their averages use every day in the period.
public struct HydrationHistory: Equatable, Sendable {
    public let days: [HydrationDay]
    public var totalMl: Int { days.reduce(0) { $0 + $1.totalMl } }
    public var count: Int { days.reduce(0) { $0 + $1.count } }
    public var recordedDayCount: Int { days.filter { !$0.records.isEmpty }.count }
    public var averageMl: Int { days.isEmpty ? 0 : Int((Double(totalMl) / Double(days.count)).rounded()) }

    public init(records: [HydrationRecord], period: HydrationHistoryPeriod, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let lastDay = period == .yesterday ? calendar.date(byAdding: .day, value: -1, to: today) ?? today : today
        guard let firstDay = calendar.date(byAdding: .day, value: 1 - period.dayCount, to: lastDay),
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else { days = []; return }
        let included = records.filter { $0.recordedAt >= firstDay && $0.recordedAt < end }
        let grouped = Dictionary(grouping: included) { calendar.startOfDay(for: $0.recordedAt) }
        days = (0..<period.dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let entries = (grouped[day] ?? []).sorted {
                if $0.recordedAt == $1.recordedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.recordedAt > $1.recordedAt
            }
            return HydrationDay(date: day, records: entries)
        }
    }
}
