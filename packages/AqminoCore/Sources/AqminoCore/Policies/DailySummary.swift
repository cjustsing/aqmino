import Foundation

public struct DailySummary: Equatable, Sendable {
    public let records: [HydrationRecord]
    public let totalMl: Int
    public let goalMl: Int?
    public var count: Int { records.count }
    public var goalReached: Bool { goalMl.map { totalMl >= $0 } ?? false }
    public var progress: Double? { goalMl.map { min(Double(totalMl) / Double($0), 1) } }

    public init(state: StateSnapshot, now: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .day, for: now)
        records = state.records.filter { record in
            guard let interval else { return false }
            return record.recordedAt >= interval.start && record.recordedAt < interval.end
        }.sorted { $0.recordedAt > $1.recordedAt }
        totalMl = records.reduce(0) { $0 + $1.amountMl }
        goalMl = state.preferences.goalEnabled ? state.preferences.goalMl : nil
    }
}
