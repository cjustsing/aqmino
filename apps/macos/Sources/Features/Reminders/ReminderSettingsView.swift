import AqminoCore
import SwiftUI

struct ReminderSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var draft: SettingsDraft
    private let weekdayZH = ["一", "二", "三", "四", "五", "六", "日"]
    private let weekdayEN = ["M", "T", "W", "T", "F", "S", "S"]
    private let fullWeekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    @State private var customInterval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggle(title: L10n.text("开启提醒", "Enable reminders"), isOn: $draft.value.remindersEnabled)
            Divider().padding(.vertical, 5)
            Text(L10n.text("提醒计划", "Schedule")).font(.callout).foregroundStyle(.secondary)
            SettingsRow(title: L10n.text("提醒日期", "Reminder days")) {
                HStack(spacing: 5) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            if draft.value.weekdays.contains(day) { draft.value.weekdays.remove(day) }
                            else { draft.value.weekdays.insert(day) }
                        } label: {
                            Text(L10n.chinese ? weekdayZH[day - 1] : weekdayEN[day - 1])
                                .frame(width: 27, height: 28)
                                .foregroundStyle(draft.value.weekdays.contains(day) ? Color.white : Color.primary)
                                .background(draft.value.weekdays.contains(day) ? AppStyle.accent : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("周" + weekdayZH[day - 1], fullWeekdays[day - 1]))
                        .accessibilityValue(draft.value.weekdays.contains(day) ? L10n.text("已选择", "Selected") : L10n.text("未选择", "Not selected"))
                    }
                }
            }
            if draft.value.weekdays.isEmpty { FieldNote(text: L10n.text("至少选择一天。", "Select at least one day."), error: true) }
            SettingsRow(title: L10n.text("提醒时段", "Time window")) {
                HStack(spacing: 8) {
                    DatePicker("", selection: minuteBinding(start: true), displayedComponents: .hourAndMinute).labelsHidden()
                        .accessibilityLabel(L10n.text("开始时间", "Start time"))
                    Text(L10n.text("至", "to")).foregroundStyle(.secondary)
                    DatePicker("", selection: minuteBinding(start: false), displayedComponents: .hourAndMinute).labelsHidden()
                        .accessibilityLabel(L10n.text("结束时间", "End time"))
                }.datePickerStyle(.field)
            }
            if let error = draft.windowError { FieldNote(text: error, error: true) }
            SettingsRow(title: L10n.text("提醒间隔", "Interval")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: intervalBinding) {
                        ForEach([30, 45, 60, 90], id: \.self) { minutes in
                            Text(L10n.text("\(minutes) 分钟", "\(minutes) minutes")).tag(minutes)
                        }
                        Text(L10n.text("自定义…", "Custom…")).tag(-1)
                    }.labelsHidden().frame(maxWidth: 210).accessibilityLabel(L10n.text("提醒间隔", "Reminder interval"))
                    if customInterval || !["30", "45", "60", "90"].contains(draft.interval) {
                        HStack {
                            TextField("15–180", text: $draft.interval).textFieldStyle(.roundedBorder).frame(width: 76)
                                .accessibilityLabel(L10n.text("自定义间隔，分钟", "Custom interval in minutes"))
                            Text(L10n.text("分钟", "minutes")).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = draft.intervalError { FieldNote(text: error, error: true) }
            Divider().padding(.vertical, 5)
            Text(L10n.text("通知", "Notifications")).font(.callout).foregroundStyle(.secondary)
            SettingsRow(title: L10n.text("通知权限", "Permission")) {
                HStack {
                    Text(capabilityTitle).foregroundStyle(.secondary)
                    Spacer()
                    if model.capability == .notDetermined {
                        Button(L10n.text("开启通知…", "Enable…")) { model.requestNotifications() }
                    } else { Button(L10n.text("系统设置…", "System Settings…")) { model.notificationSettings() } }
                }
            }
            SettingsToggle(title: L10n.text("播放提示音", "Play a sound"), isOn: $draft.value.soundEnabled)
            HStack {
                Button(model.testingNotification ? L10n.text("正在发送…", "Sending…") : L10n.text("发送测试通知", "Send test notification")) {
                    model.testNotification(sound: draft.value.soundEnabled)
                }.disabled(model.testingNotification || model.capability == .denied || model.capability == .notDetermined)
                if model.testingNotification { ProgressView().controlSize(.small) }
                Spacer()
            }.padding(.top, 6)
            FieldNote(text: L10n.text("权限修改立即生效。专注模式或屏幕共享可能使通知静默。", "Permission changes take effect immediately. Focus or screen sharing may silence notifications."))
        }
    }
    private var intervalBinding: Binding<Int> {
        Binding(get: { customInterval ? -1 : ([30, 45, 60, 90].contains(Int(draft.interval) ?? -1) ? Int(draft.interval)! : -1) },
                set: { value in customInterval = value == -1; if value != -1 { draft.interval = "\(value)" } })
    }
    private func minuteBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minutes = start ? draft.value.startMinute : draft.value.endMinute
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if start { draft.value.startMinute = minutes } else { draft.value.endMinute = minutes }
        })
    }
    private var capabilityTitle: String {
        switch model.capability {
        case .notDetermined: return L10n.text("尚未开启", "Not enabled")
        case .denied: return L10n.text("已关闭", "Off")
        case .centerOnly: return L10n.text("仅通知中心", "Notification Center only")
        case .available: return L10n.text("已开启", "On")
        }
    }
}
