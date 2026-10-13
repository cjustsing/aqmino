import AppKit
import SwiftUI

struct SupportView: View {
    @State private var paymentMethod: SupportPaymentMethod = .wechat

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "heart").foregroundStyle(AppStyle.accent).accessibilityHidden(true)
                Text(L10n.text("捐赠支持", "Support Aqmino"))
            }.font(.title2.weight(.semibold))

            VStack(spacing: 12) {
                Text(L10n.text(
                    "如果水序帮到了你，欢迎请开发者喝杯咖啡。",
                    "If Aqmino helps you, you can buy the developer a coffee."
                ))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)

                Picker(L10n.text("选择支持方式", "Choose a support method"), selection: $paymentMethod) {
                    ForEach(SupportPaymentMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    .accessibilityIdentifier("support-payment-method")

                paymentCode

                Text(L10n.text(
                    "完全自愿，不解锁任何功能，也不影响软件使用或后续更新。",
                    "Support is entirely optional and does not unlock features or affect app usage or future updates."
                ))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("support-page")
    }

    @ViewBuilder private var paymentCode: some View {
        if let url = Bundle.main.url(forResource: paymentMethod.resourceName, withExtension: "png", subdirectory: "Support"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(width: 216, height: 216).padding(8).background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .accessibilityLabel(paymentMethod.accessibilityLabel)
                .accessibilityIdentifier("support-qr-\(paymentMethod.rawValue)")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "qrcode").font(.system(size: 42))
                Text(L10n.text("未能加载收款码", "Unable to load the payment code")).font(.callout)
            }.foregroundStyle(.secondary).frame(width: 232, height: 232)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("support-qr-unavailable")
        }
    }
}

private enum SupportPaymentMethod: String, CaseIterable, Identifiable {
    case wechat, alipay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wechat: return L10n.text("微信", "WeChat Pay")
        case .alipay: return L10n.text("支付宝", "Alipay")
        }
    }
    var resourceName: String { "\(rawValue)-support-qr" }
    var accessibilityLabel: String {
        L10n.text("\(title)捐赠支持二维码，使用\(title)扫一扫", "\(title) support QR code. Scan with \(title).")
    }
}
