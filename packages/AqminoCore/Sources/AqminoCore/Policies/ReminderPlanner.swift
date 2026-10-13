import Foundation

public enum ReminderStatus: Equatable, Sendable {
    case setupRequired, disabled, sessionInactive, goalReached
    case pausedUntil(Date), pausedToday
    case outsideWindow(Date?), needsPermission, permissionDenied
    case snoozed(Date), scheduled(Date), centerOnly(Date)
}

public struct ReminderPlan: Equatable, Sendable {
    public let status: ReminderStatus
    /// Wake for a reminder or an eligibility transition, never a polling loop.
    public let wakeAt: Date?
    public let canDeliver: Bool
    public init(status: ReminderStatus, wakeAt: Date?, canDeliver: Bool) {
        self.status = status; self.wakeAt = wakeAt; self.canDeliver = canDeliver
    }
}

public enum ReminderPlanner {
    public static func dayID(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(c.era ?? 1)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    public static func windowID(_ day: Date, preferences: ReminderPreferences, calendar: Calendar) -> String {
        "\(dayID(day, calendar: calendar))|\(calendar.timeZone.identifier)|\(preferences.startMinute)-\(preferences.endMinute)|\(preferences.intervalMinutes)"
    }

    public static func window(on day: Date, preferences: ReminderPreferences, calendar: Calendar) -> DateInterval? {
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
        guard preferences.weekdays.contains(weekday) else { return nil }
        // .nextTime resolves missing DST wall times; .first resolves repeated wall times.
        let startOfDay = calendar.startOfDay(for: day)
        func boundary(_ minute: Int) -> Date? {
            calendar.nextDate(after: startOfDay.addingTimeInterval(-1),
                              matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
                              matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        guard let start = boundary(preferences.startMinute), let end = boundary(preferences.endMinute),
              calendar.isDate(start, inSameDayAs: day), calendar.isDate(end, inSameDayAs: day), start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    public static func nextCandidate(after now: Date, anchor: Date?, preferences: ReminderPreferences, calendar: Calendar) -> Date? {
        let interval = TimeInterval(preferences.intervalMinutes * 60)
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let window = window(on: day, preferences: preferences, calendar: calendar), now < window.end else { continue }
            let candidate: Date
            if now < window.start { candidate = window.start.addingTimeInterval(interval) }
            else { candidate = max(anchor ?? now, window.start).addingTimeInterval(interval) }
            if candidate < window.end { return candidate }
        }
        return nil
    }

    /// Eligibility to submit the occurrence already being handled is independent
    /// of whether the *following* reminder falls inside today's window.
    public static func isEligibleNow(_ state: StateSnapshot, context: RuleContext) -> Bool {
        let p = state.preferences, now = context.now
        guard p.onboardingComplete, p.remindersEnabled, context.sessionActive,
              context.notifications == .available || context.notifications == .centerOnly,
              !(DailySummary(state: state, now: now, calendar: context.calendar).goalReached && p.stopWhenGoalReached),
              state.runtime.pauseUntil.map({ $0 > now }) != true,
              state.runtime.pausedDay != dayID(now, calendar: context.calendar),
              let window = window(on: now, preferences: p, calendar: context.calendar) else { return false }
        return now >= window.start && now < window.end
    }

    /// Recovery never uses the normal timer's late-delivery grace. A future
    /// schedule can survive a small backward clock correction (up to 60 seconds).
    private static func hasValidRecoverySchedule(_ state: StateSnapshot, context: RuleContext) -> Bool {
        let p = state.preferences, now = context.now, calendar = context.calendar
        guard let next = state.runtime.nextReminder, next > now,
              let id = state.runtime.windowID,
              let targetWindow = window(on: next, preferences: p, calendar: calendar),
              next >= targetWindow.start, next < targetWindow.end else { return false }
        let currentID = windowID(now, preferences: p, calendar: calendar)
        let parts = id.split(separator: "|"), currentParts = currentID.split(separator: "|")
        guard parts.count == 4, parts.dropFirst() == currentParts.dropFirst() else { return false }
        let interval = TimeInterval(p.intervalMinutes * 60)
        let boundaryPlan = state.runtime.snoozeUntil == nil && next == targetWindow.start.addingTimeInterval(interval)
        guard id == currentID || boundaryPlan else { return false }
        if let snooze = state.runtime.snoozeUntil {
            return id == currentID && snooze == next && next.timeIntervalSince(now) <= 660
        }
        let inside = window(on: now, preferences: p, calendar: calendar).map { now >= $0.start && now < $0.end } ?? false
        if inside && next.timeIntervalSince(now) <= interval + 60 { return true }
        return boundaryPlan && next == nextCandidate(after: now, anchor: nil, preferences: p, calendar: calendar)
    }

    /// Mutates only derived runtime state. All callers inject clock/calendar/capability.
    public static func reconcile(_ state: inout StateSnapshot, context: RuleContext, reset: Bool = false, recovering: Bool = false) -> ReminderPlan {
        let p = state.preferences, now = context.now, calendar = context.calendar
        let day = dayID(now, calendar: calendar)
        let currentWindowID = windowID(now, preferences: p, calendar: calendar)
        let preservingFuture = recovering && hasValidRecoverySchedule(state, context: context)
        if recovering && !preservingFuture { state.runtime.invalidate(anchor: now) }
        if let pausedDay = state.runtime.pausedDay, pausedDay != day {
            state.runtime.pausedDay = nil; state.runtime.invalidate()
        }
        if let until = state.runtime.pauseUntil, until <= now {
            state.runtime.pauseUntil = nil
            state.runtime.invalidate(anchor: reset || recovering ? now : until)
        }
        if reset { state.runtime.invalidate(anchor: now) }
        let summary = DailySummary(state: state, now: now, calendar: calendar)
        let goalStopped = summary.goalReached && p.stopWhenGoalReached
        if goalStopped != state.runtime.wasGoalStopped {
            state.runtime.wasGoalStopped = goalStopped; state.runtime.invalidate(anchor: goalStopped ? nil : now)
        }
        if let id = state.runtime.windowID, id != currentWindowID, !preservingFuture {
            state.runtime.invalidate()
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        guard p.onboardingComplete else { state.runtime.nextReminder = nil; return ReminderPlan(status: .setupRequired, wakeAt: nil, canDeliver: false) }
        guard p.remindersEnabled else { state.runtime.nextReminder = nil; return ReminderPlan(status: .disabled, wakeAt: nil, canDeliver: false) }
        guard context.sessionActive else { return ReminderPlan(status: .sessionInactive, wakeAt: nil, canDeliver: false) }
        guard !goalStopped else { state.runtime.nextReminder = nil; state.runtime.snoozeUntil = nil; return ReminderPlan(status: .goalReached, wakeAt: nextDay, canDeliver: false) }
        if let until = state.runtime.pauseUntil, until > now {
            state.runtime.nextReminder = nil; return ReminderPlan(status: .pausedUntil(until), wakeAt: until, canDeliver: false)
        }
        if state.runtime.pausedDay == day {
            state.runtime.nextReminder = nil; return ReminderPlan(status: .pausedToday, wakeAt: nextDay, canDeliver: false)
        }
        let currentWindow = window(on: now, preferences: p, calendar: calendar)
        let inside = currentWindow.map { now >= $0.start && now < $0.end } ?? false
        if state.runtime.nextReminder == nil {
            state.runtime.nextReminder = nextCandidate(after: now, anchor: state.runtime.anchor, preferences: p, calendar: calendar)
        }
        state.runtime.windowID = currentWindowID
        if !inside {
            let next = nextCandidate(after: now, anchor: nil, preferences: p, calendar: calendar)
            state.runtime.nextReminder = next; state.runtime.snoozeUntil = nil
            // Permission is refreshed again at the eligible window's first opportunity.
            return ReminderPlan(status: .outsideWindow(next), wakeAt: minDate(next, nextDay), canDeliver: false)
        }
        if context.notifications == .notDetermined {
            return ReminderPlan(status: .needsPermission, wakeAt: nextDay, canDeliver: false)
        }
        if context.notifications == .denied {
            return ReminderPlan(status: .permissionDenied, wakeAt: nextDay, canDeliver: false)
        }
        if let snooze = state.runtime.snoozeUntil {
            if let currentWindow, snooze < currentWindow.end {
                state.runtime.nextReminder = snooze
                return ReminderPlan(status: .snoozed(snooze), wakeAt: snooze, canDeliver: true)
            }
            state.runtime.snoozeUntil = nil
        }
        guard let next = state.runtime.nextReminder ?? nextCandidate(after: now, anchor: now, preferences: p, calendar: calendar) else {
            return ReminderPlan(status: .outsideWindow(nil), wakeAt: nextDay, canDeliver: false)
        }
        state.runtime.nextReminder = next
        if let currentWindow, next >= currentWindow.end {
            return ReminderPlan(status: .outsideWindow(next), wakeAt: minDate(next, nextDay), canDeliver: false)
        }
        let status: ReminderStatus = context.notifications == .centerOnly ? .centerOnly(next) : .scheduled(next)
        return ReminderPlan(status: status, wakeAt: minDate(next, nextDay), canDeliver: next < (currentWindow?.end ?? now))
    }

    private static func minDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) { case let (.some(a), .some(b)): return min(a, b); case let (.some(a), nil): return a; case let (nil, .some(b)): return b; default: return nil }
    }
}
