//
//  TimerEngine.swift
//  Rhythm
//
//  循环计时状态机核心。所有转移函数显式接收 `now`，便于注入时钟做单元测试。
//  核心原则：剩余时间始终由绝对时间戳 `phaseEnd` 推导，绝不累减计数器，
//  因此休眠、时钟跳变后依然正确。
//

import Foundation
import Combine

/// 状态机对外抛出的事件（用于系统通知等副作用）。
public enum TimerEvent: Equatable, Sendable {
    case phaseChanged(from: Phase, to: Phase)
    case windowEnded
}

public final class TimerEngine: ObservableObject {

    // MARK: - 对外只读状态

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var phaseStart: Date
    @Published public private(set) var phaseEnd: Date
    @Published public private(set) var windowEnd: Date?
    @Published public private(set) var nextWindowStart: Date?
    @Published public private(set) var paused: Bool = false
    @Published public private(set) var freeRun: Bool = false

    /// 事件回调（在状态转移后同步触发）。
    public var onEvent: ((TimerEvent) -> Void)?

    // MARK: - 依赖

    private var settings: AppSettings
    private var schedule: ScheduleEngine
    private let calendar: Calendar
    private var pausedRemaining: TimeInterval?

    public init(settings: AppSettings, calendar: Calendar = .current, now: Date = Date()) {
        self.settings = settings
        self.calendar = calendar
        self.schedule = ScheduleEngine(settings: settings, calendar: calendar)
        self.phaseStart = now
        self.phaseEnd = now
    }

    // MARK: - 配置

    public func apply(settings newSettings: AppSettings) {
        self.settings = newSettings
        self.schedule = ScheduleEngine(settings: newSettings, calendar: calendar)
    }

    public var currentSettings: AppSettings { settings }

    // MARK: - 派生信息

    /// 当前阶段剩余秒数（暂停时返回冻结的剩余）。
    public func remaining(at now: Date) -> TimeInterval {
        guard phase != .idle else { return 0 }
        if paused, let remaining = pausedRemaining { return max(remaining, 0) }
        return max(phaseEnd.timeIntervalSince(now), 0)
    }

    /// 当前阶段的完整时长。
    public var phaseDuration: TimeInterval {
        switch phase {
        case .work: return settings.workSeconds
        case .rest: return settings.restSeconds
        case .idle: return 0
        }
    }

    /// 暂停时冻结的剩余秒数（未暂停为 nil）。
    public var pausedRemainingSeconds: TimeInterval? {
        paused ? pausedRemaining : nil
    }

    public func snapshot(now: Date) -> TimerSnapshot {
        TimerSnapshot(
            phase: phase,
            phaseStart: phaseStart,
            phaseEnd: phaseEnd,
            windowEnd: windowEnd,
            nextWindowStart: nextWindowStart,
            paused: paused,
            freeRun: freeRun,
            updatedAt: now
        )
    }

    // MARK: - 主循环（每 tick / 唤醒 / 时钟变更时调用）

    public func tick(now: Date) {
        let phaseAtStart = phase

        if paused {
            if phase == .idle {
                nextWindowStart = schedule.nextWindowStart(after: now)
            }
            return
        }

        let window = schedule.currentWindow(at: now)
        var windowDidEnd = false
        var hadPhaseChange = false

        if freeRun {
            if let w = window {
                // 时段开始 → 强制回到时段逻辑，从当前时刻重启完整工作循环。
                freeRun = false
                startWork(now: now, windowEnd: w.end)
            } else {
                (windowDidEnd, hadPhaseChange) = advance(now: now)
            }
        } else if let w = window {
            if phase == .idle {
                // 冷启动落入时段，或跨越时段起点进入新时段：一律从 now 重启。
                startWork(now: now, windowEnd: w.end)
            } else if windowEnd != w.end {
                // 时段切换/边界：结束旧循环，从当前时段起点重启。
                endCycle(now: now)
                windowDidEnd = true
                startWork(now: now, windowEnd: w.end)
            } else {
                (windowDidEnd, hadPhaseChange) = advance(now: now)
            }
        } else {
            // 时段外。
            if phase != .idle {
                endCycle(now: now)
                windowDidEnd = true
            }
            nextWindowStart = schedule.nextWindowStart(after: now)
        }

        // 合并补发：一次 tick 至多一条相位通知。
        if hadPhaseChange, phase != .idle, settings.notifyOnPhaseEnd {
            onEvent?(.phaseChanged(from: phaseAtStart, to: phase))
        }
        if windowDidEnd, settings.notifyOnWindowEnd {
            onEvent?(.windowEnded)
        }
    }

    // MARK: - 手动控制

    public func pause(now: Date) {
        guard phase != .idle, !paused else { return }
        pausedRemaining = max(phaseEnd.timeIntervalSince(now), 0)
        paused = true
    }

    public func resume(now: Date) {
        guard paused else { return }
        let remaining = pausedRemaining ?? 0
        paused = false
        pausedRemaining = nil
        guard phase != .idle else { return }
        let duration = phaseDuration
        phaseEnd = now.addingTimeInterval(remaining)
        phaseStart = phaseEnd.addingTimeInterval(-duration)
        tick(now: now)
    }

    /// 跳过当前阶段：工作 → 立即休息；休息 → 立即工作。仍受时段末裁剪。
    public func skip(now: Date) {
        switch phase {
        case .idle:
            if let w = schedule.currentWindow(at: now) {
                windowEnd = w.end
                startWork(now: now, windowEnd: w.end)
            }
        case .work:
            if let we = windowEnd, now >= we {
                endCycle(now: now)
            } else {
                toRest(now: now)
            }
        case .rest:
            if let we = windowEnd, now >= we {
                endCycle(now: now)
            } else {
                toWork(now: now)
            }
        }
    }

    /// 重置本轮：回到当前阶段（通常为工作）的完整倒计时。
    public func resetRound(now: Date) {
        if let w = schedule.currentWindow(at: now) {
            startWork(now: now, windowEnd: w.end)
        } else if freeRun {
            startWork(now: now, windowEnd: nil)
        } else if phase != .idle {
            startWork(now: now, windowEnd: windowEnd)
        }
    }

    /// 时段外临时启动一次不受时段约束的循环。
    public func temporaryStart(now: Date) {
        guard phase == .idle else { return }
        if let w = schedule.currentWindow(at: now) {
            startWork(now: now, windowEnd: w.end)
        } else {
            freeRun = true
            startWork(now: now, windowEnd: nil)
        }
    }

    /// 停止临时循环（仅对 freeRun 生效）。
    public func stop(now: Date) {
        guard freeRun || phase != .idle else { return }
        freeRun = false
        endCycle(now: now)
    }

    // MARK: - 内部转移

    private func advance(now: Date) -> (windowEnded: Bool, hadPhaseChange: Bool) {
        var hadPhaseChange = false
        while phase != .idle && phaseEnd <= now {
            switch phase {
            case .work:
                if let we = windowEnd, phaseEnd >= we {
                    endCycle(now: phaseEnd)
                    return (true, hadPhaseChange)
                }
                toRest(now: phaseEnd)
                hadPhaseChange = true
            case .rest:
                if let we = windowEnd, phaseEnd >= we {
                    endCycle(now: phaseEnd)
                    return (true, hadPhaseChange)
                }
                toWork(now: phaseEnd)
                hadPhaseChange = true
            case .idle:
                return (false, hadPhaseChange)
            }
        }
        if let we = windowEnd, phase != .idle, now >= we {
            endCycle(now: now)
            return (true, hadPhaseChange)
        }
        return (false, hadPhaseChange)
    }

    private func startWork(now: Date, windowEnd: Date?) {
        setPhase(.work, start: now, end: clamp(now.addingTimeInterval(settings.workSeconds), to: windowEnd), windowEnd: windowEnd)
    }

    private func toWork(now: Date) {
        setPhase(.work, start: now, end: clamp(now.addingTimeInterval(settings.workSeconds), to: windowEnd), windowEnd: windowEnd)
    }

    private func toRest(now: Date) {
        setPhase(.rest, start: now, end: clamp(now.addingTimeInterval(settings.restSeconds), to: windowEnd), windowEnd: windowEnd)
    }

    private func endCycle(now: Date) {
        setPhase(.idle, start: now, end: now, windowEnd: nil)
        freeRun = false
        nextWindowStart = schedule.nextWindowStart(after: now)
    }

    private func setPhase(_ newPhase: Phase, start: Date, end: Date, windowEnd: Date?) {
        phase = newPhase
        phaseStart = start
        phaseEnd = end
        self.windowEnd = windowEnd
        nextWindowStart = nil
        paused = false
        pausedRemaining = nil
    }

    private func clamp(_ date: Date, to windowEnd: Date?) -> Date {
        guard let windowEnd, windowEnd < date else { return date }
        return windowEnd
    }
}
