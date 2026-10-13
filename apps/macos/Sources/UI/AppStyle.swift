import AppKit
import SwiftUI

enum L10n {
    static var chinese: Bool { (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") }
    static func text(_ chinese: String, _ english: String) -> String { self.chinese ? chinese : english }
    static var brand: String { text("水序", "Aqmino") }
    static func time(_ date: Date, weekday: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale.autoupdatingCurrent; f.timeZone = .autoupdatingCurrent
        f.dateFormat = weekday ? "EEE HH:mm" : "HH:mm"; return f.string(from: date)
    }
    static func amount(_ ml: Int) -> String { "\(ml) ml" }
    static func count(_ n: Int) -> String { text("\(n) 次记录", "\(n) \(n == 1 ? "record" : "records")") }
    static func date(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.timeZone = .autoupdatingCurrent
        f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }
}

enum AppStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.22, green: 0.76, blue: 0.74, alpha: 1)
            : NSColor(srgbRed: 0, green: 0.50, blue: 0.51, alpha: 1)
    })
}

struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title).frame(width: 116, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 8)
    }
}

struct FieldNote: View {
    let text: String
    var error = false
    var body: some View {
        Text(text).font(.caption).foregroundStyle(error ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }.padding(.vertical, 4)
    }
}
