import AqminoCore
import Foundation

enum SettingsSection: Int, CaseIterable, Identifiable {
    case history, reminders, records, general, data, support
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .history: return L10n.text("饮水记录", "Water history")
        case .reminders: return L10n.text("提醒", "Reminders")
        case .records: return L10n.text("记录与目标", "Records & goal")
        case .general: return L10n.text("通用", "General")
        case .data: return L10n.text("数据管理", "Data management")
        case .support: return L10n.text("捐赠支持", "Support Aqmino")
        }
    }
    var symbol: String { switch self { case .history: return "chart.bar.xaxis"; case .reminders: return "bell"; case .records: return "drop"; case .general: return "gearshape"; case .data: return "externaldrive"; case .support: return "heart" } }
}

@MainActor
final class SettingsDraft: ObservableObject {
    @Published var section: SettingsSection = .reminders
    @Published var value = ReminderPreferences()
    @Published var amounts = ["150", "250", "350"]
    @Published var goal = ""
    @Published var interval = "45"
    private var baseline = ReminderPreferences()
    func reset(_ preferences: ReminderPreferences) {
        baseline = preferences; value = preferences; amounts = preferences.quickAmounts.map(String.init)
        goal = preferences.goalMl.map(String.init) ?? ""; interval = "\(preferences.intervalMinutes)"
    }
    var candidate: ReminderPreferences? {
        var p = value
        guard let minutes = Int(interval), amounts.allSatisfy({ Int($0) != nil }) else { return nil }
        p.intervalMinutes = minutes; p.quickAmounts = amounts.compactMap(Int.init)
        if p.goalEnabled { p.goalMl = Int(goal) }
        else { p.goalMl = Int(goal).flatMap { (1...10000).contains($0) ? $0 : nil } ?? baseline.goalMl }
        guard (try? p.validated()) != nil else { return nil }; return p
    }
    var dirty: Bool { candidate.map { $0 != baseline } ?? true }
    var intervalError: String? {
        guard let minutes = Int(interval), (15...180).contains(minutes) else { return L10n.text("请输入 15–180 分钟的整数。", "Enter a whole number from 15–180 minutes.") }
        if value.endMinute - value.startMinute <= minutes { return L10n.text("提醒时段须长于提醒间隔。", "The window must be longer than the interval.") }
        return nil
    }
    var windowError: String? { value.startMinute >= value.endMinute ? L10n.text("结束时间须晚于开始时间，首版不支持跨夜。", "End must follow start. Overnight windows are not supported.") : nil }
    var goalError: String? {
        guard value.goalEnabled else { return nil }
        return Int(goal).map { (1...10000).contains($0) } == true ? nil : L10n.text("请输入 1–10000 ml 的自定目标。", "Enter your goal from 1–10000 ml.")
    }
    func amountError(_ index: Int) -> String? {
        guard let amount = Int(amounts[index]), (1...2000).contains(amount) else { return L10n.text("容量须为 1–2000 ml 的整数。", "Use a whole number from 1–2000 ml.") }
        if amounts.compactMap(Int.init).filter({ $0 == amount }).count > 1 { return L10n.text("三个容量不能重复。", "Choose three different amounts.") }
        return nil
    }
}
