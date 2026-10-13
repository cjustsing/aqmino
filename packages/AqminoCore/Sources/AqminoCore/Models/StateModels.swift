import Foundation

public enum RecordSource: String, Codable, Sendable { case quick, custom, notification }

public struct HydrationRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let operationID: UUID
    public let amountMl: Int
    public let recordedAt: Date
    public let timeZoneIDAtCreation: String
    public let source: RecordSource
    public let occurrenceID: UUID?

    public init(id: UUID = UUID(), operationID: UUID, amountMl: Int, recordedAt: Date,
                timeZoneIDAtCreation: String, source: RecordSource, occurrenceID: UUID? = nil) {
        self.id = id; self.operationID = operationID; self.amountMl = amountMl
        self.recordedAt = recordedAt; self.timeZoneIDAtCreation = timeZoneIDAtCreation
        self.source = source; self.occurrenceID = occurrenceID
    }
}

public struct ReminderPreferences: Codable, Equatable, Sendable {
    public var remindersEnabled = true
    /// ISO weekdays: Monday = 1, Sunday = 7.
    public var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    public var startMinute = 9 * 60
    public var endMinute = 18 * 60
    public var intervalMinutes = 45
    public var quickAmounts = [150, 250, 350]
    public var lastAmount = 250
    public var goalEnabled = false
    public var goalMl: Int? = nil
    public var stopWhenGoalReached = true
    public var soundEnabled = false
    public var onboardingComplete = false
    public init() {}

    public func validated() throws {
        guard !weekdays.isEmpty, weekdays.allSatisfy({ (1...7).contains($0) }) else { throw ValidationError.weekdays }
        guard (0..<1440).contains(startMinute), (1..<1440).contains(endMinute), startMinute < endMinute else { throw ValidationError.window }
        guard (15...180).contains(intervalMinutes), endMinute - startMinute > intervalMinutes else { throw ValidationError.interval }
        guard quickAmounts.count == 3, Set(quickAmounts).count == 3,
              quickAmounts.allSatisfy({ (1...2000).contains($0) }), (1...2000).contains(lastAmount) else { throw ValidationError.amount }
        if goalEnabled { guard let goalMl, (1...10000).contains(goalMl) else { throw ValidationError.goal } }
        if let goalMl, !(1...10000).contains(goalMl) { throw ValidationError.goal }
    }
}

public enum ValidationError: String, Error, Sendable { case weekdays, window, interval, amount, goal, unknownOccurrence, expiredUndo, unsupportedSchema, invalidSnapshot }

public struct ReminderRuntime: Codable, Equatable, Sendable {
    public var anchor: Date?
    public var nextReminder: Date?
    public var windowID: String?
    public var generation: UInt64 = 0
    public var pauseUntil: Date?
    public var pausedDay: String?
    public var snoozeUntil: Date?
    public var latestOccurrenceID: UUID?
    public var wasGoalStopped = false
    public init() {}
    public mutating func invalidate(anchor: Date? = nil) {
        generation &+= 1; self.anchor = anchor; nextReminder = nil; windowID = nil; snoozeUntil = nil
    }
}

public enum DeliveryResult: String, Codable, Sendable { case pending, inline, submitted, failed }

public struct ReminderOccurrence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let amountMl: Int
    public var interactionGeneration: UInt64
    public var delivery: DeliveryResult = .pending
    public var consumed = false
    public var invalidated = false
    public init(id: UUID, createdAt: Date, amountMl: Int, interactionGeneration: UInt64) {
        self.id = id; self.createdAt = createdAt; self.amountMl = amountMl
        self.interactionGeneration = interactionGeneration
    }
}

public struct CommandReceipt: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let recordID: UUID?
    public init(operationID: UUID, recordID: UUID? = nil) { self.operationID = operationID; self.recordID = recordID }
}

public struct StateSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision: UInt64 = 0
    public var preferences = ReminderPreferences()
    public var records: [HydrationRecord] = []
    public var runtime = ReminderRuntime()
    public var occurrences: [ReminderOccurrence] = []
    public var receipts: [CommandReceipt] = []
    public init() {}

    public func validated() throws {
        guard schemaVersion == 1 else { throw ValidationError.unsupportedSchema }
        try preferences.validated()
        guard Set(records.map(\.id)).count == records.count,
              Set(records.map(\.operationID)).count == records.count,
              Set(occurrences.map(\.id)).count == occurrences.count,
              Set(receipts.map(\.operationID)).count == receipts.count,
              records.allSatisfy({ (1...2000).contains($0.amountMl) && TimeZone(identifier: $0.timeZoneIDAtCreation) != nil }),
              occurrences.allSatisfy({ (1...2000).contains($0.amountMl) }),
              [runtime.anchor, runtime.nextReminder, runtime.pauseUntil, runtime.snoozeUntil].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              records.allSatisfy({ $0.recordedAt.timeIntervalSince1970.isFinite }) else { throw ValidationError.invalidSnapshot }
    }
}

public struct UndoToken: Sendable {
    public enum Kind: Sendable { case insertion, deletion }
    public let kind: Kind
    public let record: HydrationRecord
    public let previousRuntime: ReminderRuntime
    public let resultingGeneration: UInt64
    public let expiresAt: Date
    public init(kind: Kind, record: HydrationRecord, previousRuntime: ReminderRuntime, resultingGeneration: UInt64, expiresAt: Date) {
        self.kind = kind; self.record = record; self.previousRuntime = previousRuntime
        self.resultingGeneration = resultingGeneration; self.expiresAt = expiresAt
    }
}

public enum NotificationCapability: String, Sendable { case notDetermined, denied, centerOnly, available }

public struct RuleContext: Sendable {
    public var now: Date
    public var calendar: Calendar
    public var notifications: NotificationCapability
    public var sessionActive: Bool
    public init(now: Date, calendar: Calendar, notifications: NotificationCapability = .available, sessionActive: Bool = true) {
        self.now = now; self.calendar = calendar; self.notifications = notifications; self.sessionActive = sessionActive
    }
}
