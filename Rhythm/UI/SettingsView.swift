//
//  SettingsView.swift
//  Rhythm
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    private let weekdaySymbols: [(Int, String)] = [
        (2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"),
        (6, "周五"), (7, "周六"), (1, "周日"),
    ]

    var body: some View {
        Form {
            Section("时长") {
                durationRow(title: "工作时长", keyPath: \.workMinutes, range: 1...240)
                durationRow(title: "休息时长", keyPath: \.restMinutes, range: 1...120)
            }

            Section("生效时段") {
                ForEach(Array(controller.settings.ranges.enumerated()), id: \.element.id) { index, range in
                    HStack {
                        DatePicker(
                            "开始",
                            selection: startTimeBinding(index),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Text("–")
                        DatePicker(
                            "结束",
                            selection: endTimeBinding(index),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Spacer()
                        if !range.isValid {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help("开始时间必须早于结束时间（暂不支持跨天）")
                        }
                        Button {
                            controller.settings.ranges.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    addRange()
                } label: {
                    Label("添加时段", systemImage: "plus")
                }
                if hasInvalidRanges {
                    Text("存在无效时段：开始时间必须早于结束时间。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if hasOverlap {
                    Text("存在重叠时段，请调整。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("生效日") {
                HStack {
                    ForEach(weekdaySymbols, id: \.0) { weekday, label in
                        Toggle(label, isOn: weekdayBinding(weekday))
                            .toggleStyle(.button)
                    }
                }
            }

            Section("通知") {
                Toggle("工作 / 休息切换时提醒", isOn: $controller.settings.notifyOnPhaseEnd)
                Toggle("时段结束时提醒", isOn: $controller.settings.notifyOnWindowEnd)
                Toggle("播放提示音", isOn: $controller.settings.soundEnabled)
            }

            Section("熄屏") {
                Toggle("熄屏时暂停计时", isOn: $controller.settings.pauseOnScreenSleep)
                Picker("恢复时机", selection: $controller.settings.screenSleepResume) {
                    Text("点亮").tag(ScreenSleepResumeTrigger.screenWake)
                    Text("解锁后").tag(ScreenSleepResumeTrigger.unlock)
                }
                .disabled(!controller.settings.pauseOnScreenSleep)
            }

            Section("快捷键") {
                ShortcutRecorderView()
            }

            Section("通用") {
                Toggle("开机自动启动", isOn: $controller.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    // MARK: - 校验

    private func durationRow(
        title: String,
        keyPath: WritableKeyPath<AppSettings, Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: minutesBinding(keyPath, range: range), format: .number)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Text("分钟")
                .foregroundStyle(.secondary)
            Stepper("", value: minutesBinding(keyPath, range: range), in: range)
                .labelsHidden()
        }
    }

    private func minutesBinding(
        _ keyPath: WritableKeyPath<AppSettings, Int>,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { controller.settings[keyPath: keyPath] },
            set: { controller.settings[keyPath: keyPath] = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private var hasInvalidRanges: Bool {
        controller.settings.ranges.contains { !$0.isValid }
    }

    private var hasOverlap: Bool {
        let sorted = controller.settings.ranges.sorted { $0.startMinutes < $1.startMinutes }
        for index in 1..<sorted.count where sorted[index].startMinutes < sorted[index - 1].endMinutes {
            return true
        }
        return false
    }

    private func addRange() {
        let range = TimeRange(startHour: 9, startMinute: 0, endHour: 18, endMinute: 0)
        controller.settings.ranges.append(range)
        controller.settings.ranges.sort { $0.startMinutes < $1.startMinutes }
    }

    // MARK: - 绑定

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func startTimeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                date(
                    hour: controller.settings.ranges[index].startHour,
                    minute: controller.settings.ranges[index].startMinute
                )
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                controller.settings.ranges[index].startHour = components.hour ?? 0
                controller.settings.ranges[index].startMinute = components.minute ?? 0
            }
        )
    }

    private func endTimeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                date(
                    hour: controller.settings.ranges[index].endHour,
                    minute: controller.settings.ranges[index].endMinute
                )
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                controller.settings.ranges[index].endHour = components.hour ?? 0
                controller.settings.ranges[index].endMinute = components.minute ?? 0
            }
        )
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { controller.settings.activeWeekdays.contains(weekday) },
            set: { isOn in
                if isOn {
                    controller.settings.activeWeekdays.insert(weekday)
                } else {
                    controller.settings.activeWeekdays.remove(weekday)
                }
            }
        )
    }
}
