import AqminoCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var draft: SettingsDraft
    let close: () -> Void
    @State private var confirmDelete = false
    @State private var historyPeriod: HydrationHistoryPeriod = .today
    @FocusState private var focusedSection: SettingsSection?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(SettingsSection.allCases) { section in
                        if section == .reminders || section == .support { Divider().padding(.vertical, 7) }
                        Button { draft.section = section } label: {
                            Label(section.title, systemImage: section.symbol)
                                .font(.system(size: 13, weight: draft.section == section ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 11)
                                .foregroundStyle(draft.section == section ? AppStyle.accent : Color.primary)
                                .background(draft.section == section ? AppStyle.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .focused($focusedSection, equals: section)
                            .accessibilityAddTraits(draft.section == section ? .isSelected : [])
                            .accessibilityIdentifier("settings-section-\(section.rawValue)")
                    }
                    Spacer()
                    Text("Aqmino 0.1").font(.caption2).foregroundStyle(.tertiary).padding(10)
                }.padding(12).frame(width: 158).background(.thinMaterial)
                Divider()
                if draft.section == .history {
                    HydrationHistoryView(model: model, period: $historyPeriod)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                } else if draft.section == .support {
                    ScrollView { SupportView().padding(24) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                } else { settingsContent }
            }
            Divider()
            HStack(spacing: 10) {
                if model.inlineOccurrence != nil, draft.section != .history { InlineReminderView(model: model) }
                else if draft.section == .reminders, let feedback = model.testNotificationFeedback {
                    Text(feedback).font(.caption)
                        .foregroundStyle(model.testNotificationFailed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("notification-test-feedback")
                }
                else if draft.dirty { Text(L10n.text("有未保存的更改", "Unsaved changes")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                if draft.section == .reminders || draft.section == .records || draft.dirty {
                    Button(L10n.text("取消", "Cancel")) { draft.reset(model.state.preferences); close() }.keyboardShortcut(.cancelAction)
                    Button(L10n.text("保存", "Save")) {
                        guard let preferences = draft.candidate else { return }
                        model.enqueue(.preferences(preferences)) { success in if success { draft.reset(model.state.preferences) } }
                    }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
                        .disabled(!draft.dirty || draft.candidate == nil || !model.canWrite)
                } else {
                    Button(L10n.text("完成", "Done")) { close() }.keyboardShortcut(.cancelAction)
                }
            }.padding(.horizontal, 20).padding(.vertical, 14).background(.bar)
        }.frame(minWidth: 680, minHeight: 580).tint(AppStyle.accent)
        .onChange(of: model.loaded) { loaded in
            if loaded { draft.reset(model.state.preferences) }
        }
        .onChange(of: draft.section) { section in
            if focusedSection != nil { focusedSection = section }
        }
        .alert(L10n.text("删除全部饮水记录？", "Delete all water records?"), isPresented: $confirmDelete) {
            Button(L10n.text("取消", "Cancel"), role: .cancel) { }
            Button(L10n.text("删除", "Delete"), role: .destructive) { model.enqueue(.clearRecords) }
        } message: {
            Text(L10n.text("将删除 \(model.state.records.count) 条记录，且无法恢复。提醒设置会保留。", "All \(model.state.records.count) records will be permanently deleted. Reminder settings will be kept."))
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text(draft.section.title).font(.title2.weight(.semibold)).padding(.bottom, 2)
                if !model.loaded && model.storageIssue == nil {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("正在读取设置…", "Loading settings…")).foregroundStyle(.secondary)
                    }
                }
                Group {
                    switch draft.section {
                    case .history, .support: EmptyView()
                    case .reminders: ReminderSettingsView(model: model, draft: draft)
                    case .records: recordsPage
                    case .general: generalPage
                    case .data: dataPage
                    }
                }.disabled(!model.loaded)
                if let issue = model.storageIssue {
                    FieldNote(text: issue, error: true)
                    Button(model.deletionPending ? L10n.text("继续清理", "Complete deletion") : L10n.text("重试", "Retry")) { model.retryStorage() }.disabled(model.busy)
                    if model.backupAvailable { Button(L10n.text("恢复有效备份", "Restore backup")) { model.restoreBackup() }.disabled(model.busy) }
                }
                if let notice = model.notice { FieldNote(text: notice) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var recordsPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.text("快捷记录", "Quick recording")).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("容量 \(i + 1)", "Amount \(i + 1)")).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            TextField("", text: $draft.amounts[i]).textFieldStyle(.roundedBorder)
                                .accessibilityLabel(L10n.text("快捷容量 \(i + 1)，毫升", "Quick amount \(i + 1) in milliliters"))
                            Text("ml").font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = draft.amountError(i) { FieldNote(text: error, error: true) }
                    }.frame(maxWidth: .infinity)
                }
            }
            FieldNote(text: L10n.text("三个不同容量，均为 1–2000 ml 的整数。", "Three different whole amounts, each from 1–2000 ml."))
            Divider().padding(.vertical, 2)
            SettingsToggle(title: L10n.text("启用自定每日目标", "Set a daily goal"), isOn: $draft.value.goalEnabled)
            if draft.value.goalEnabled {
                SettingsRow(title: L10n.text("每日目标", "Daily goal")) {
                    HStack {
                        TextField(L10n.text("自行填写", "Your amount"), text: $draft.goal).textFieldStyle(.roundedBorder).frame(width: 112)
                            .accessibilityLabel(L10n.text("自定每日目标，毫升", "Your daily goal in milliliters"))
                        Text("ml").foregroundStyle(.secondary)
                    }
                }
                if let error = draft.goalError { FieldNote(text: error, error: true) }
                SettingsToggle(title: L10n.text("达标后停止今日提醒", "Stop today's reminders when reached"), isOn: $draft.value.stopWhenGoalReached)
                FieldNote(text: L10n.text("仍可继续记录饮水。", "You can continue recording water."))
            } else {
                FieldNote(text: L10n.text("仅显示今日累计，不预设饮水目标。", "Shows today's total without a preset goal."))
            }
            FieldNote(text: L10n.text("目标由你自行决定，可随时关闭。", "Choose your own goal and turn it off at any time."))
        }
    }
    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggle(title: L10n.text("登录时启动水序", "Launch Aqmino at login"), isOn: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval }, set: { model.setLoginEnabled($0) }))
                .disabled(model.loginStatus == .unavailable)
                .accessibilityIdentifier("launch-at-login")
            if model.loginStatus == .requiresApproval {
                FieldNote(text: L10n.text("已请求登录启动，请在系统设置中允许水序。", "Launch at login was requested. Allow Aqmino in System Settings."))
                Button(L10n.text("打开系统设置…", "Open System Settings…")) { model.login.openSettings() }
            } else if model.loginStatus == .unavailable {
                FieldNote(text: L10n.text("系统暂未识别登录启动服务。", "The system has not recognized the login service."))
            }
            if let issue = model.loginIssue {
                FieldNote(text: issue, error: true).accessibilityIdentifier("login-item-error")
                Button(L10n.text("打开系统设置…", "Open System Settings…")) { model.login.openSettings() }
            }
            FieldNote(text: L10n.text("登录启动修改立即生效。", "Launch at login changes take effect immediately."))
            Divider().padding(.vertical, 8)
            SettingsRow(title: L10n.text("外观", "Appearance")) { Text(L10n.text("跟随系统", "System appearance")).foregroundStyle(.secondary) }
            Divider()
            SettingsRow(title: L10n.text("语言", "Language")) { Text(L10n.text("跟随系统 · 简体中文", "System language · English")).foregroundStyle(.secondary) }
            Divider()
            FieldNote(text: L10n.text("关闭面板后继续提醒。退出水序后停止新的提醒。", "Reminders continue when the panel closes. Quitting Aqmino stops new reminders."))
        }
    }
    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.text("保存在这台 Mac", "Stored on this Mac"), systemImage: "externaldrive").font(.headline)
            Text(L10n.text("饮水记录和提醒偏好仅保存在本机，不需要账号。", "Your records and reminder preferences stay on this Mac. No account is needed."))
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            SettingsRow(title: L10n.text("所有饮水记录", "All water records")) {
                Text(model.loaded && !model.deletionPending ? L10n.text("\(model.state.records.count) 条", "\(model.state.records.count) records") : "—").foregroundStyle(.secondary)
            }
            Button(L10n.text("查看数据位置…", "Show data folder…")) { NSWorkspace.shared.activateFileViewerSelecting([model.dataDirectory]) }
            Divider()
            Button(L10n.text("删除全部饮水记录…", "Delete all water records…"), role: .destructive) { confirmDelete = true }
                .disabled(!model.canWrite || model.state.records.isEmpty)
            FieldNote(text: L10n.text("删除无法撤销，提醒设置会保留。", "Deletion cannot be undone. Reminder settings will be kept."))
        }
    }
}
