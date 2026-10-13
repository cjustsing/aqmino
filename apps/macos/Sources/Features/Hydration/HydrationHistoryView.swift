import AqminoCore
import Charts
import SwiftUI

struct HydrationHistoryView: View {
    @ObservedObject var model: AppModel
    @Binding var period: HydrationHistoryPeriod

    private var history: HydrationHistory {
        HydrationHistory(records: model.state.records, period: period, now: model.now, calendar: .autoupdatingCurrent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("饮水记录", "Water history")).font(.title2.weight(.semibold))
                Spacer()
                if let undo = model.undo, undo.expiresAt > model.now {
                    Button(L10n.text("撤销", "Undo")) { model.undoLast() }
                        .disabled(!model.canWrite).keyboardShortcut("z", modifiers: .command)
                }
            }
            Picker(L10n.text("记录范围", "History period"), selection: $period) {
                ForEach(HydrationHistoryPeriod.allCases) { period in
                    Text(title(period)).tag(period)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("history-period")
            if model.canShowRecords {
                let summary = history
                Text(rangeLabel(summary)).font(.caption).foregroundStyle(.secondary)
                metrics(summary)
                if period.dayCount > 1 {
                    trend(summary)
                    FieldNote(text: L10n.text("包含今日，日均按全部 \(period.dayCount) 个自然日计算；无记录日计为 0。", "Includes today. The average uses all \(period.dayCount) calendar days; days without records count as 0."))
                }
                Divider()
                if summary.count == 0 {
                    VStack(spacing: 10) {
                        Image(systemName: "drop").font(.system(size: 30, weight: .light)).foregroundStyle(AppStyle.accent)
                        Text(period == .today ? L10n.text("今天还没有记录", "No records today") : L10n.text("这段时间没有记录", "No records in this period"))
                        Text(L10n.text("从菜单栏记录一杯水，开始持续追踪。", "Record a glass from the menu bar to start tracking."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(summary.days.reversed().filter { !$0.records.isEmpty }) { day in
                                if period.dayCount > 1 {
                                    HStack {
                                        Text(L10n.date(day.date)).fontWeight(.medium)
                                        Spacer()
                                        Text("\(day.totalMl) ml · " + L10n.count(day.count)).foregroundStyle(.secondary)
                                    }.font(.caption).padding(.top, 16).padding(.bottom, 4)
                                }
                                ForEach(day.records) { record in recordRow(record) }
                            }
                        }
                    }.frame(minHeight: 112).accessibilityIdentifier("history-records")
                }
            } else if model.storageIssue == nil {
                ProgressView(L10n.text("正在读取记录…", "Loading records…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { Spacer() }
            if let issue = model.storageIssue {
                FieldNote(text: issue, error: true)
                HStack {
                    Button(model.deletionPending ? L10n.text("继续清理", "Complete deletion") : L10n.text("重试", "Retry")) { model.retryStorage() }.disabled(model.busy)
                    if model.backupAvailable { Button(L10n.text("恢复有效备份", "Restore backup")) { model.restoreBackup() }.disabled(model.busy) }
                }
            } else if model.inlineOccurrence != nil { InlineReminderView(model: model) }
            else if let notice = model.notice { FieldNote(text: notice) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).tint(AppStyle.accent)
    }

    private func title(_ period: HydrationHistoryPeriod) -> String {
        switch period {
        case .today: return L10n.text("今日", "Today")
        case .yesterday: return L10n.text("昨日", "Yesterday")
        case .last7Days: return L10n.text("近 7 日", "7 days")
        case .last30Days: return L10n.text("近 30 日", "30 days")
        }
    }

    private func rangeLabel(_ summary: HydrationHistory) -> String {
        guard let first = summary.days.first, let last = summary.days.last else { return "" }
        return summary.days.count == 1 ? L10n.date(first.date) : L10n.date(first.date) + " – " + L10n.date(last.date)
    }

    private func metrics(_ summary: HydrationHistory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            metric(L10n.text("饮水总量", "Total water"), value: "\(summary.totalMl.formatted())", unit: "ml")
            if period.dayCount > 1 {
                metric(L10n.text("日均饮水", "Daily average"), value: "\(summary.averageMl.formatted())", unit: "ml")
                metric(L10n.text("有记录的天数", "Days recorded"), value: "\(summary.recordedDayCount)", unit: "/ \(summary.days.count)")
            } else {
                metric(L10n.text("记录次数", "Records"), value: "\(summary.count)", unit: L10n.text("次", ""))
            }
        }.accessibilityIdentifier("history-summary")
    }

    private func metric(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func trend(_ summary: HydrationHistory) -> some View {
        Chart(summary.days) { day in
            BarMark(x: .value(L10n.text("日期", "Date"), day.date, unit: .day),
                    y: .value(L10n.text("饮水量", "Water"), day.totalMl))
                .foregroundStyle(AppStyle.accent)
                .cornerRadius(3)
                .accessibilityLabel(L10n.date(day.date))
                .accessibilityValue("\(day.totalMl) ml")
        }
        .chartYScale(domain: 0...max(250, summary.days.map(\.totalMl).max() ?? 0))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: period == .last30Days ? 6 : 1)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 128)
        .accessibilityLabel(L10n.text("每日饮水量趋势，毫升", "Daily water trend in milliliters"))
    }

    private func recordRow(_ record: HydrationRecord) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "drop").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(L10n.time(record.recordedAt)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("\(record.amountMl) ml").fontWeight(.medium)
                Button { model.enqueue(.deleteRecord(record.id)) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).disabled(!model.canWrite)
                    .accessibilityLabel(L10n.text("删除 \(L10n.date(record.recordedAt)) \(L10n.time(record.recordedAt)) 的 \(record.amountMl) ml 记录", "Delete \(record.amountMl) ml on \(L10n.date(record.recordedAt)) at \(L10n.time(record.recordedAt))"))
            }.padding(.vertical, 10)
            Divider()
        }
    }
}
