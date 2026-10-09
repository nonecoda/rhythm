//
//  ScheduleEngine.swift
//  Rhythm
//
//  生效时段判定：纯函数、可注入 `Calendar`，便于单元测试。
//

import Foundation

/// 根据生效时段与星期，计算当前/下一个时段。
public struct ScheduleEngine: Sendable {
    public let ranges: [TimeRange]
    public let activeWeekdays: Set<Int>
    public let calendar: Calendar

    public init(ranges: [TimeRange], activeWeekdays: Set<Int>, calendar: Calendar) {
        self.ranges = ranges.sorted { $0.startMinutes < $1.startMinutes }
        self.activeWeekdays = activeWeekdays
        self.calendar = calendar
    }

    public init(settings: AppSettings, calendar: Calendar) {
        self.init(
            ranges: settings.ranges,
            activeWeekdays: settings.activeWeekdays,
            calendar: calendar
        )
    }

    // MARK: - 查询

    /// 返回 `now` 所在的时段（同一天内），不在任何时段则返回 nil。
    public func currentWindow(at now: Date) -> DateInterval? {
        guard isActive(day: now) else { return nil }
        let dayStart = calendar.startOfDay(for: now)
        for range in ranges {
            guard let start = date(dayStart: dayStart, minutes: range.startMinutes),
                  let end = date(dayStart: dayStart, minutes: range.endMinutes)
            else { continue }
            if now >= start && now < end {
                return DateInterval(start: start, end: end)
            }
        }
        return nil
    }

    /// `now` 之后（严格大于）最近的一个时段开始时间；未来 8 天内查找。
    public func nextWindowStart(after now: Date) -> Date? {
        let todayStart = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else {
                continue
            }
            guard isActive(day: dayStart) else { continue }
            for range in ranges {
                guard let start = date(dayStart: dayStart, minutes: range.startMinutes) else {
                    continue
                }
                if start > now {
                    return start
                }
            }
        }
        return nil
    }

    /// `now` 是否处于任意生效时段内。
    public func isActive(at now: Date) -> Bool {
        currentWindow(at: now) != nil
    }

    // MARK: - 私有

    /// `dayStart` 当天，`date` 是否属于生效星期。
    private func isActive(day date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return activeWeekdays.contains(weekday)
    }

    private func date(dayStart: Date, minutes: Int) -> Date? {
        calendar.date(byAdding: .minute, value: minutes, to: dayStart)
    }
}
