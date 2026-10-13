import SwiftUI

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "drop").font(.system(size: 36, weight: .light)).foregroundStyle(AppStyle.accent).accessibilityHidden(true)
            Text(L10n.text("让喝水成为自然的节奏。", "A natural rhythm for drinking water.")).font(.title2.weight(.semibold))
            Text(L10n.text("从菜单栏快捷记录，查看今日累计。提醒默认为工作日 09:00–18:00，每 45 分钟一次。", "Record water from the menu bar and see your daily total. Reminders default to weekdays, 09:00–18:00, every 45 minutes."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("目标默认关闭，数据仅保存在本机。通知可以稍后开启。", "Goals are off by default. Data stays on this Mac. Notifications can be enabled later."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let issue = model.storageIssue { FieldNote(text: issue, error: true); Button(L10n.text("重试", "Retry")) { model.retryStorage() } }
            HStack {
                Button(L10n.text("先开始记录", "Start recording")) { model.completeWelcome(enableNotifications: false) }
                Spacer()
                Button(L10n.text("开启通知…", "Enable notifications…")) { model.completeWelcome(enableNotifications: true) }
                    .buttonStyle(.borderedProminent)
            }.disabled(!model.canWrite)
        }.padding(28).frame(width: 420).tint(AppStyle.accent)
    }
}
