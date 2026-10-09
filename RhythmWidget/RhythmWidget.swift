//
//  RhythmWidget.swift
//  RhythmWidget
//

import WidgetKit
import SwiftUI

struct RhythmWidget: Widget {
    let kind = "RhythmWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RhythmWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rhythm 计时")
        .description("显示工作 / 休息循环倒计时与生效时段。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RhythmWidgetEntryView: View {
    var entry: RhythmEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.phase.symbolName)
                Text(entry.phase.displayName)
                    .font(.headline)
            }

            switch entry.phase {
            case .idle:
                Text("未启用")
                    .font(.title3)
                    .bold()
                if let next = entry.nextWindowStart {
                    Text("下次 \(Self.timeFormatter.string(from: next))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .work, .rest:
                if entry.paused {
                    Text("已暂停")
                        .font(.title3)
                        .bold()
                } else {
                    Text(timerInterval: entry.phaseStart...entry.phaseEnd, countsDown: true)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }

            if family == .systemMedium, let next = entry.nextWindowStart, entry.phase != .idle {
                Text("下次时段 \(Self.timeFormatter.string(from: next))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
