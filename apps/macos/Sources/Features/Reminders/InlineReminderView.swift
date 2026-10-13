import SwiftUI

struct InlineReminderView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let occurrence = model.inlineOccurrence, model.storageIssue == nil {
            HStack(spacing: 10) {
                Label(L10n.text("喝口水，稍作休息。", "Take a sip. Take a moment."), systemImage: "drop")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("10 分钟后", "In 10 minutes")) { model.enqueue(.snooze(occurrence.id)) }
                    .buttonStyle(.borderless).font(.caption).disabled(!model.canWrite)
            }
        }
    }
}
