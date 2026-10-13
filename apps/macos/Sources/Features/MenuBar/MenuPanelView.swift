import AqminoCore
import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @State private var custom = false
    @State private var more = false
    @State private var hoveredMoreAction: MoreAction?
    @FocusState private var focusedMoreAction: MoreAction?
    @FocusState private var focusedMoreTrigger: Bool

    private enum MoreAction: String, CaseIterable { case settings, support, quit }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.brand).font(.title3.weight(.semibold))
                    Text(L10n.chinese ? "Aqmino" : "水序").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                moreTrigger
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("今日已记录", "Recorded today")).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.loaded && !model.deletionPending ? "\(model.summary.totalMl)" : "—")
                        .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text("ml").font(.title3).foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 8)
                    if model.loaded && !model.deletionPending {
                        Text(model.summary.count == 0 ? L10n.text("今天还没有记录", "No records today") : L10n.count(model.summary.count))
                            .font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }.accessibilityElement(children: .combine)
                if model.loaded && !model.deletionPending {
                    if let progress = model.summary.progress, let goal = model.summary.goalMl {
                        ProgressView(value: progress).tint(AppStyle.accent).padding(.top, 6)
                        Text(L10n.text("自定目标 \(goal) ml · \(Int(progress * 100))%", "Your goal: \(goal) ml · \(Int(progress * 100))%"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.canShowRecords {
                    let activity = TodayActivity(records: model.summary.records, preferences: model.state.preferences,
                                                 calendar: .autoupdatingCurrent)
                    Button { model.openRecords?() } label: { TodayActivityChart(activity: activity) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("查看今日饮水分布", "View today's water activity"))
                        .accessibilityValue(activity.details)
                        .accessibilityHint(L10n.text("打开饮水记录", "Opens water history"))
                        .accessibilityIdentifier("today-activity-chart")
                        .help(activity.details + "\n" + L10n.text("点击查看饮水记录", "Click to view water history"))
                }
            }
            Divider()
            statusArea
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("记录一杯", "Record a glass")).font(.callout.weight(.medium))
                    Spacer()
                    Button(L10n.text("自定义…", "Custom…")) { custom = true }
                        .buttonStyle(.borderless).disabled(!model.canWrite)
                }
                HStack(spacing: 8) {
                    ForEach(model.state.preferences.quickAmounts, id: \.self) { amount in
                        if amount == primaryQuickAmount {
                            quickButton(amount).buttonStyle(.borderedProminent)
                        } else { quickButton(amount).buttonStyle(.bordered) }
                    }
                }
            }
            if let token = model.undo, token.expiresAt > model.now {
                HStack {
                    Image(systemName: "checkmark.circle").foregroundStyle(AppStyle.accent).accessibilityHidden(true)
                    Text(model.notice ?? L10n.text("操作已保存", "Change saved")).font(.caption)
                    Spacer()
                    Button(L10n.text("撤销", "Undo")) { model.undoLast() }
                        .buttonStyle(.borderless).keyboardShortcut("z", modifiers: .command).disabled(!model.canWrite)
                }.accessibilityElement(children: .contain)
            } else if let notice = model.notice, model.storageIssue == nil {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(width: 360).fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(more)
        .overlay(alignment: .topTrailing) {
            if more {
                ZStack(alignment: .topTrailing) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { closeMore() }.accessibilityHidden(true)
                    moreActions.padding(.top, 52).padding(.trailing, 20)
                }
            }
        }
        .onExitCommand(perform: more ? closeMore : nil)
        .onMoveCommand(perform: more ? moveMoreSelection : nil)
        .tint(AppStyle.accent)
        .sheet(isPresented: $custom) { CustomRecordView(model: model) { custom = false } }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in closeMore() }
    }
    @ViewBuilder private var moreTrigger: some View {
        let button = Button {
            if more { closeMore() }
            else {
                more = true
                // Keep commands routed to this view without selecting a menu row.
                focusedMoreTrigger = true
            }
        } label: {
            Image(systemName: more ? "ellipsis.circle.fill" : "ellipsis.circle")
                .font(.title3).foregroundStyle(AppStyle.accent)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .focused($focusedMoreTrigger)
            .accessibilityLabel(L10n.text("更多操作", "More actions"))
            .accessibilityValue(more ? L10n.text("已展开", "Expanded") : L10n.text("已收起", "Collapsed"))
            .accessibilityIdentifier("more-actions-toggle")
        if #available(macOS 14, *) { button.focusEffectDisabled() }
        else { button }
    }
    private var moreActions: some View {
        VStack(spacing: 0) {
            moreAction(.settings, title: L10n.text("设置…", "Settings…"), icon: "gearshape", shortcut: "⌘,")
            moreAction(.support, title: L10n.text("捐赠支持…", "Support Aqmino…"), icon: "heart", shortcut: "")
            Divider().padding(.horizontal, 10)
            moreAction(.quit, title: L10n.text("退出水序", "Quit Aqmino"), icon: "power", shortcut: "⌘Q")
        }.padding(5).frame(width: 176)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("更多操作", "More actions"))
            .accessibilityIdentifier("more-actions")
    }
    private func moreAction(_ action: MoreAction, title: String, icon: String, shortcut: String) -> some View {
        Button {
            closeMore()
            switch action {
            case .settings: model.openSettings?(.reminders)
            case .support: model.openSettings?(.support)
            case .quit: NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(title)
                Spacer(minLength: 0)
                Text(shortcut).font(.caption2).foregroundStyle(.secondary)
            }.font(.callout).padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(hoveredMoreAction == action || focusedMoreAction == action ? AppStyle.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).focused($focusedMoreAction, equals: action)
            .keyboardShortcut((focusedMoreAction ?? .settings) == action ? .defaultAction : nil)
            .onHover { hovering in hoveredMoreAction = hovering ? action : nil }
            .accessibilityLabel(title)
            .accessibilityIdentifier("more-action-\(action.rawValue)")
    }
    private func closeMore() {
        more = false; hoveredMoreAction = nil; focusedMoreAction = nil; focusedMoreTrigger = false
    }
    private func moveMoreSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .up, .down:
            hoveredMoreAction = nil
            if focusedMoreAction == nil { focusedMoreAction = direction == .up ? .quit : .settings }
            else if let selected = focusedMoreAction, let index = MoreAction.allCases.firstIndex(of: selected) {
                let actions = MoreAction.allCases
                let step = direction == .up ? -1 : 1
                focusedMoreAction = actions[(index + step + actions.count) % actions.count]
            }
        default: break
        }
    }
    private func quickButton(_ amount: Int) -> some View {
        Button { model.enqueue(.record(amount: amount, source: .quick)) } label: {
            Text(L10n.amount(amount)).frame(maxWidth: .infinity).padding(.vertical, 3)
        }.disabled(!model.canWrite).accessibilityLabel(L10n.text("记录 \(amount) 毫升", "Record \(amount) milliliters"))
    }
    private var primaryQuickAmount: Int {
        let p = model.state.preferences
        return p.quickAmounts.contains(p.lastAmount) ? p.lastAmount : p.quickAmounts[1]
    }
    @ViewBuilder private var statusArea: some View {
        if let issue = model.storageIssue {
            VStack(alignment: .leading, spacing: 8) {
                Label(issue, systemImage: "exclamationmark.triangle").font(.callout)
                HStack {
                    Button(model.deletionPending ? L10n.text("继续清理", "Complete deletion") : L10n.text("重试", "Retry")) { model.retryStorage() }
                    if model.backupAvailable { Button(L10n.text("恢复有效备份", "Restore backup")) { model.restoreBackup() } }
                }.buttonStyle(.borderless).disabled(model.busy)
            }
        } else if !model.loaded {
            ProgressView(L10n.text("正在读取…", "Loading…")).controlSize(.small)
        } else if let occurrence = model.inlineOccurrence {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Label(L10n.text("喝口水，稍作休息。", "Take a sip. Take a moment."), systemImage: "drop")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    pauseControl
                }
                Button(L10n.text("10 分钟后", "In 10 minutes")) { model.enqueue(.snooze(occurrence.id)) }
                    .buttonStyle(.borderless).disabled(!model.canWrite)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon).font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(model.dispatchFailed ? L10n.text("提醒暂时未能发出", "Reminder could not be sent") : statusTitle).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        pauseControl
                    }
                    Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                    statusAction
                }
            }
        }
    }
    @ViewBuilder private var pauseControl: some View {
        if model.state.preferences.remindersEnabled {
            if model.hasPause {
                Button(L10n.text("恢复提醒", "Resume reminders")) { model.enqueue(.resume) }
                    .buttonStyle(.borderless).font(.callout).fixedSize().disabled(!model.canWrite)
                    .accessibilityLabel(L10n.text("恢复提醒", "Resume reminders"))
            } else {
                Menu {
                    Button(L10n.text("暂停 30 分钟", "Pause for 30 minutes")) { model.enqueue(.pause(minutes: 30)) }
                    Button(L10n.text("暂停 1 小时", "Pause for 1 hour")) { model.enqueue(.pause(minutes: 60)) }
                    Divider()
                    Button(L10n.text("今日不再提醒", "Pause for today")) { model.enqueue(.pauseToday) }
                } label: { Text(L10n.text("暂停提醒", "Pause reminders")).font(.callout) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(!model.canWrite)
                    .accessibilityLabel(L10n.text("暂停提醒", "Pause reminders"))
            }
        }
    }
    private var statusIcon: String {
        switch model.plan.status { case .pausedUntil, .pausedToday: return "pause.circle"; case .goalReached: return "checkmark.circle"; case .permissionDenied, .needsPermission: return "bell.slash"; default: return "clock" }
    }
    private var statusTitle: String {
        switch model.plan.status {
        case .setupRequired: return L10n.text("准备开始记录", "Ready to start")
        case .disabled: return L10n.text("提醒已关闭", "Reminders are off")
        case .sessionInactive: return L10n.text("恢复工作后继续提醒", "Reminders resume with your session")
        case .goalReached: return L10n.text("目标已完成", "Goal reached")
        case let .pausedUntil(date): return L10n.text("已暂停，\(L10n.time(date)) 恢复", "Paused until \(L10n.time(date))")
        case .pausedToday: return L10n.text("今日已暂停", "Paused for today")
        case let .outsideWindow(date): return date.map { L10n.text("下次提醒 \(L10n.time($0, weekday: true))", "Next reminder \(L10n.time($0, weekday: true))") } ?? L10n.text("当前没有提醒计划", "No reminder scheduled")
        case .needsPermission: return L10n.text("开启通知后接收喝水提醒", "Enable notifications for reminders")
        case .permissionDenied: return L10n.text("通知已关闭，仍可记录饮水", "Notifications are off. Keep recording water.")
        case let .snoozed(date): return L10n.text("将在 \(L10n.time(date)) 再提醒", "Remind me again at \(L10n.time(date))")
        case let .scheduled(date): return L10n.text("下一次提醒 \(L10n.time(date))", "Next reminder \(L10n.time(date))")
        case .centerOnly: return L10n.text("提醒将显示在通知中心", "Reminders appear in Notification Center")
        }
    }
    private var statusDetail: String {
        if model.dispatchFailed, let next = model.state.runtime.nextReminder { return L10n.text("下一次提醒 \(L10n.time(next, weekday: !Calendar.current.isDateInToday(next)))", "Next reminder \(L10n.time(next, weekday: !Calendar.current.isDateInToday(next)))") }
        switch model.plan.status {
        case .goalReached: return L10n.text("今日提醒已停止，仍可记录。", "Today's reminders have stopped. You can still record.")
        case .pausedUntil: return L10n.text("恢复后经过完整间隔再提醒。", "A full interval follows the pause.")
        case .pausedToday: return L10n.text("下一天按提醒计划恢复。", "Resumes next day within your schedule.")
        case .needsPermission, .permissionDenied: return L10n.text("饮水记录仅保存在本机。", "Water records stay on this Mac.")
        case let .centerOnly(date): return L10n.text("下一次提醒 \(L10n.time(date))", "Next reminder \(L10n.time(date))")
        default:
            let p = model.state.preferences
            return String(format: "%02d:%02d–%02d:%02d · ", p.startMinute / 60, p.startMinute % 60, p.endMinute / 60, p.endMinute % 60)
                + L10n.text("每 \(p.intervalMinutes) 分钟", "every \(p.intervalMinutes) minutes")
        }
    }
    @ViewBuilder private var statusAction: some View {
        if model.dispatchFailed { Button(L10n.text("查看提醒设置", "Reminder settings")) { model.openSettings?(.reminders) }.buttonStyle(.borderless) }
        else {
            switch model.plan.status {
            case .needsPermission: Button(L10n.text("开启通知", "Enable notifications")) { model.requestNotifications() }.buttonStyle(.borderless)
            case .permissionDenied, .centerOnly: Button(L10n.text("查看系统通知设置", "Notification settings")) { model.notificationSettings() }.buttonStyle(.borderless)
            case .disabled: Button(L10n.text("开启提醒", "Enable reminders")) { var p = model.state.preferences; p.remindersEnabled = true; model.enqueue(.preferences(p)) }.buttonStyle(.borderless).disabled(!model.canWrite)
            case .goalReached: Button(L10n.text("修改目标", "Edit goal")) { model.openSettings?(.records) }.buttonStyle(.borderless)
            default: EmptyView()
            }
        }
    }
}

/// Uses the reminder plan's inclusive start and exclusive end; the daily total still includes all records.
struct TodayActivity {
    struct Bucket: Identifiable {
        let startMinute: Int
        let endMinute: Int
        var records: [HydrationRecord] = []
        var id: Int { startMinute }
        var amountMl: Int { records.reduce(0) { $0 + $1.amountMl } }
        var range: String { "\(TodayActivity.time(startMinute))–\(TodayActivity.time(endMinute))" }
    }
    let startMinute: Int
    let endMinute: Int
    let buckets: [Bucket]
    let outsideRecords: [HydrationRecord]
    let latest: HydrationRecord?

    init(records: [HydrationRecord], preferences: ReminderPreferences, calendar: Calendar) {
        startMinute = preferences.startMinute; endMinute = preferences.endMinute
        latest = records.max { $0.recordedAt < $1.recordedAt }
        var bins: [Bucket] = []
        var cursor = startMinute
        while cursor < endMinute {
            let end = min(endMinute, (cursor / 60 + 1) * 60)
            bins.append(Bucket(startMinute: cursor, endMinute: end)); cursor = end
        }
        var outside: [HydrationRecord] = []
        for record in records {
            let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: record.recordedAt)
            let minute = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
                + Double(components.second ?? 0) / 60 + Double(components.nanosecond ?? 0) / 60_000_000_000
            if let index = bins.indices.first(where: { minute >= Double(bins[$0].startMinute)
                && minute < Double(bins[$0].endMinute) }) {
                bins[index].records.append(record)
            } else { outside.append(record) }
        }
        buckets = bins; outsideRecords = outside
    }
    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    var range: String { "\(Self.time(startMinute))–\(Self.time(endMinute))" }
    var duration: Double { Double(max(endMinute - startMinute, 1)) }
    var maximumMl: Int { buckets.map(\.amountMl).max() ?? 0 }
    var insideTotalMl: Int { buckets.reduce(0) { $0 + $1.amountMl } }
    var outsideTotalMl: Int { outsideRecords.reduce(0) { $0 + $1.amountMl } }
    var outsideText: String {
        L10n.text("时段外 \(outsideRecords.count) 次 · \(outsideTotalMl) ml",
                  "Outside hours: \(outsideRecords.count) · \(outsideTotalMl) ml")
    }
    var latestText: String? {
        latest.map { L10n.text("最近 \(L10n.time($0.recordedAt)) · \($0.amountMl) ml",
                              "Latest \(L10n.time($0.recordedAt)) · \($0.amountMl) ml") }
    }
    var details: String {
        var lines = [range + " · " + L10n.text("按小时汇总，单位 ml", "Hourly totals in ml")]
        lines += buckets.filter { $0.amountMl > 0 }.map { "\($0.range): \($0.amountMl) ml · " + L10n.count($0.records.count) }
        if let latestText { lines.append(latestText) }
        if !outsideRecords.isEmpty { lines.append(outsideText) }
        if latest == nil { lines.append(L10n.text("暂无记录", "No records")) }
        return lines.joined(separator: "\n")
    }
}

private struct TodayActivityChart: View {
    let activity: TodayActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(L10n.text("今日分布", "Today")).font(.caption.weight(.medium))
                Text(activity.buckets.count > 12 && activity.maximumMl > 0
                     ? L10n.text("最高 \(activity.maximumMl) ml", "Max \(activity.maximumMl) ml")
                     : L10n.text("按小时 · ml", "Hourly · ml"))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let latest = activity.latestText {
                    Text(latest).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let maximum = max(activity.maximumMl, 1)
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
                    ForEach(activity.buckets) { bucket in
                        let width = geometry.size.width * Double(bucket.endMinute - bucket.startMinute) / activity.duration
                        VStack(spacing: 1) {
                            if bucket.amountMl > 0 && width >= 25 {
                                Text("\(bucket.amountMl)").font(.system(size: 9)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.secondary)
                            }
                            RoundedRectangle(cornerRadius: 2)
                                .fill(bucket.amountMl == 0 ? Color.secondary.opacity(0.2) : AppStyle.accent)
                                .frame(width: max(2, min(20, width - 4)),
                                       height: bucket.amountMl == 0 ? 1 : max(3, 25 * Double(bucket.amountMl) / Double(maximum)))
                        }.frame(width: width, height: 38, alignment: .bottom)
                            .position(x: geometry.size.width * (Double(bucket.startMinute + bucket.endMinute) / 2 - Double(activity.startMinute)) / activity.duration,
                                      y: 19)
                            .help("\(bucket.range) · \(bucket.amountMl) ml · " + L10n.count(bucket.records.count))
                    }
                    if activity.insideTotalMl == 0 {
                        Text(activity.latest == nil ? L10n.text("暂无记录", "No records") : L10n.text("时段内暂无记录", "No records in these hours"))
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }.frame(height: 38)
            HStack {
                Text(TodayActivity.time(activity.startMinute))
                Spacer(minLength: 0)
                Text(TodayActivity.time((activity.startMinute + activity.endMinute) / 2))
                Spacer(minLength: 0)
                Text(TodayActivity.time(activity.endMinute))
            }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            if !activity.outsideRecords.isEmpty {
                Text(activity.outsideText).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(6).frame(maxWidth: .infinity)
            .background(AppStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Normal states have no scroll container. Exceptionally tall content still fits a small display.
struct MenuPopoverContent: View {
    @ObservedObject var model: AppModel
    let maximumHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    @State private var contentHeight: CGFloat = 440

    private var panel: some View {
        MenuPanelView(model: model).background(GeometryReader { geometry in
            Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
        })
    }

    var body: some View {
        Group {
            if contentHeight > maximumHeight { ScrollView { panel } }
            else { panel }
        }.frame(width: 360, height: min(ceil(contentHeight), maximumHeight))
            .onPreferenceChange(PanelHeightKey.self) { height in
                guard height > 0 else { return }
                contentHeight = height
                onHeightChange(min(ceil(height), maximumHeight))
            }
    }
}
