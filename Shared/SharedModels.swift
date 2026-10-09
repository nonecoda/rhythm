//
//  SharedModels.swift
//  Rhythm
//
//  两端（App 与 Widget）共用的纯数据模型。只依赖 Foundation，
//  全部 Codable，便于写入 App Group，保证 App 与挂件状态同步。
//

import Foundation

/// App Group 标识符（App 与挂件共用）。
public enum AppGroup {
    public static let identifier = "group.com.rhythm.app"
}

/// 计时阶段。
public enum Phase: String, Codable, Sendable, CaseIterable {
    case idle
    case work
    case rest

    public var displayName: String {
        switch self {
        case .idle: return "未启用"
        case .work: return "工作"
        case .rest: return "休息"
        }
    }

    /// SF Symbol 名称，用于菜单栏与挂件。
    public var symbolName: String {
        switch self {
        case .idle: return "moon.zzz"
        case .work: return "brain.head.profile"
        case .rest: return "cup.and.saucer"
        }
    }
}

/// 单条生效时段（同一天内的 start–end，v1 不支持跨天）。
public struct TimeRange: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int

    public init(
        id: UUID = UUID(),
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) {
        self.id = id
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    public init(id: UUID = UUID(), start: DateComponents, end: DateComponents) {
        self.init(
            id: id,
            startHour: start.hour ?? 0,
            startMinute: start.minute ?? 0,
            endHour: end.hour ?? 0,
            endMinute: end.minute ?? 0
        )
    }

    /// 从当天 00:00 起的分钟偏移。
    public var startMinutes: Int { startHour * 60 + startMinute }
    public var endMinutes: Int { endHour * 60 + endMinute }

    /// start 必须严格早于 end（v1 不支持跨天/零长度）。
    public var isValid: Bool { startMinutes < endMinutes }

    public func startComponents() -> DateComponents {
        DateComponents(hour: startHour, minute: startMinute)
    }

    public func endComponents() -> DateComponents {
        DateComponents(hour: endHour, minute: endMinute)
    }

    /// 规范化后的副本：将非法值裁剪到合法范围。
    public func normalized() -> TimeRange {
        var copy = self
        copy.startHour = min(max(startHour, 0), 23)
        copy.startMinute = min(max(startMinute, 0), 59)
        copy.endHour = min(max(endHour, 0), 24)
        copy.endMinute = min(max(endMinute, 0), 59)
        return copy
    }
}

/// 用户可配置设置，存入 App Group UserDefaults。
public struct AppSettings: Codable, Equatable, Sendable {
    /// 工作时长（分钟）。
    public var workMinutes: Int
    /// 休息时长（分钟）。
    public var restMinutes: Int
    /// 生效时段列表。
    public var ranges: [TimeRange]
    /// 生效星期：1=周日 … 7=周六（`Calendar` 的 weekday 语义）。默认周一至周五。
    public var activeWeekdays: Set<Int>
    /// 工作↔休息切换时通知。
    public var notifyOnPhaseEnd: Bool
    /// 时段结束时通知。
    public var notifyOnWindowEnd: Bool
    /// 通知声音开关。
    public var soundEnabled: Bool
    /// 开机自启（SMAppService）。
    public var launchAtLogin: Bool

    public init(
        workMinutes: Int = 40,
        restMinutes: Int = 5,
        ranges: [TimeRange] = AppSettings.defaultRanges,
        activeWeekdays: Set<Int> = AppSettings.weekdaysMondayToFriday,
        notifyOnPhaseEnd: Bool = true,
        notifyOnWindowEnd: Bool = false,
        soundEnabled: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.workMinutes = workMinutes
        self.restMinutes = restMinutes
        self.ranges = ranges
        self.activeWeekdays = activeWeekdays
        self.notifyOnPhaseEnd = notifyOnPhaseEnd
        self.notifyOnWindowEnd = notifyOnWindowEnd
        self.soundEnabled = soundEnabled
        self.launchAtLogin = launchAtLogin
    }

    public static let weekdaysMondayToFriday: Set<Int> = [2, 3, 4, 5, 6]

    public static let defaultRanges: [TimeRange] = [
        TimeRange(startHour: 9, startMinute: 0, endHour: 12, endMinute: 0),
        TimeRange(startHour: 13, startMinute: 30, endHour: 18, endMinute: 0),
    ]

    public static let `default` = AppSettings()

    /// 合法的工作时长（分钟），至少 1 分钟。
    public var workSeconds: TimeInterval { TimeInterval(max(workMinutes, 1) * 60) }
    public var restSeconds: TimeInterval { TimeInterval(max(restMinutes, 1) * 60) }
}

/// 供挂件读取的实时状态快照。
public struct TimerSnapshot: Codable, Equatable, Sendable {
    public var phase: Phase
    public var phaseStart: Date
    public var phaseEnd: Date
    /// 当前生效时段的结束时间（idle/自由运行时为 nil）。
    public var windowEnd: Date?
    /// idle 时展示的下一个时段开始时间。
    public var nextWindowStart: Date?
    public var paused: Bool
    /// 时段外临时启动标记。
    public var freeRun: Bool
    public var updatedAt: Date

    public init(
        phase: Phase,
        phaseStart: Date,
        phaseEnd: Date,
        windowEnd: Date?,
        nextWindowStart: Date?,
        paused: Bool,
        freeRun: Bool,
        updatedAt: Date
    ) {
        self.phase = phase
        self.phaseStart = phaseStart
        self.phaseEnd = phaseEnd
        self.windowEnd = windowEnd
        self.nextWindowStart = nextWindowStart
        self.paused = paused
        self.freeRun = freeRun
        self.updatedAt = updatedAt
    }
}
