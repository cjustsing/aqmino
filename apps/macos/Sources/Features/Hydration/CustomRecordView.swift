import SwiftUI

struct CustomRecordView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var amount = ""
    @FocusState private var focused: Bool
    private var value: Int? { Int(amount).flatMap { (1...2000).contains($0) ? $0 : nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("记录饮水", "Record water")).font(.title3.weight(.semibold))
            HStack {
                TextField(L10n.text("容量", "Amount"), text: $amount).textFieldStyle(.roundedBorder)
                    .focused($focused).onSubmit(record).accessibilityLabel(L10n.text("容量，毫升", "Amount in milliliters"))
                Text("ml").foregroundStyle(.secondary)
            }
            FieldNote(text: L10n.text("输入 1–2000 ml 的整数。", "Enter a whole number from 1–2000 ml."), error: value == nil && !amount.isEmpty)
            InlineReminderView(model: model)
            if let issue = model.storageIssue {
                FieldNote(text: issue, error: true)
                Button(L10n.text("重试保存", "Retry saving")) { model.retryStorage() }.disabled(model.busy)
            }
            HStack {
                Spacer()
                Button(L10n.text("取消", "Cancel"), action: close).keyboardShortcut(.cancelAction)
                Button(L10n.text("记录", "Record"), action: record).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(value == nil || !model.canWrite)
            }
        }.padding(24).frame(width: 320).tint(AppStyle.accent)
        .onAppear { amount = "\(model.state.preferences.lastAmount)"; focused = true }
    }
    private func record() {
        guard let value, model.canWrite else { return }
        model.enqueue(.record(amount: value, source: .custom)) { success in if success { close() } }
    }
}
