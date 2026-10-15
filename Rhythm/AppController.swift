//
//  AppController.swift
//  Rhythm
//
//  应用层协调器：驱动 1 秒心跳、持久化快照、刷新挂件、分发通知与全局快捷键。
//

import Foundation
import Darwin
import Combine
import WidgetKit
import KeyboardShortcuts

@MainActor
final class AppController: ObservableObject {

    /// 全局单例：供 `RhythmApp` 以普通属性持有，避免 App 层订阅秒级更新而导致场景抖动。
    static let shared = AppController()

    @Published var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    let engine: TimerEngine

    private let store: SharedStore
    private let notifications: NotificationService
    private let clockObserver = ClockObserver()
    private var timer: Timer?
    private var memoryLogTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastReloadSignature: String?
    private var started = false

    init(store: SharedStore = .shared, notifications: NotificationService = NotificationService()) {
        self.store = store
        self.notifications = notifications
        let loaded = store.loadSettings()
        self.settings = loaded
        self.engine = TimerEngine(settings: loaded, calendar: .current, now: Date())
        self.engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        // 引擎状态变化转发给观察者；引擎仅在相位/时段真正变化时发布，UI 不做秒级刷新。
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - 派生展示信息

    /// 菜单栏文本：固定 5 字符宽度风格（`mm:ss` / `--:--`），配合视图的等宽数字与固定宽度，避免抖动。
    /// 使用实时时间计算剩余量，由 `StatusBarController` 自身的 1 Hz 定时器驱动刷新，
    /// 不再经由 `@Published`，避免每秒向 SwiftUI/Combine 广播全局状态变化。
    var menuBarText: String {
        switch engine.phase {
        case .idle:
            return "--:--"
        case .work, .rest:
            if let frozen = engine.pausedRemainingSeconds {
                return Self.format(frozen)
            }
            return Self.format(engine.remaining(at: Date()))
        }
    }

    /// 菜单内状态描述。
    var statusText: String {
        switch engine.phase {
        case .idle:
            if let next = engine.nextWindowStart {
                return "未启用 · 下次 \(Self.timeFormatter.string(from: next))"
            }
            return "未启用"
        case .work, .rest:
            if let frozen = engine.pausedRemainingSeconds {
                return "\(engine.phase.displayName) · 已暂停 \(Self.format(frozen))"
            }
            return "\(engine.phase.displayName) · 剩余 \(Self.format(engine.remaining(at: Date())))"
        }
    }

    /// `mm:ss` 或 `h:mm:ss`。
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true

        notifications.requestAuthorization()
        LaunchAtLogin.set(settings.launchAtLogin)

        clockObserver.onEvent = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        clockObserver.onAway = { [weak self] in
            Task { @MainActor in self?.handleScreenAway() }
        }
        clockObserver.onWake = { [weak self] in
            Task { @MainActor in self?.handleScreenWake() }
        }
        clockObserver.onUnlock = { [weak self] in
            Task { @MainActor in self?.handleScreenUnlock() }
        }
        clockObserver.start()

        KeyboardShortcuts.onKeyUp(for: .skipRest) { [weak self] in
            self?.skip()
        }

        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        startMemoryLoggingIfRequested()
    }

    /// 诊断用：当环境变量 `RHYTHM_MEMORY_LOG=1` 时每 60s 记录 `phys_footprint`，
    /// 供修复前后对照。默认关闭，不影响正常运行。
    private func startMemoryLoggingIfRequested() {
        guard ProcessInfo.processInfo.environment["RHYTHM_MEMORY_LOG"] == "1" else { return }
        MemoryDiagnostics.logFootprint()
        let memoryTimer = Timer(timeInterval: 60, repeats: true) { _ in
            MemoryDiagnostics.logFootprint()
        }
        RunLoop.main.add(memoryTimer, forMode: .common)
        self.memoryLogTimer = memoryTimer
    }

    /// 每秒 / 唤醒 / 时钟变更时重算并持久化。
    ///
    /// 不再写入任何 `@Published` 属性：菜单栏每秒倒计时由 `StatusBarController`
    /// 自持定时器直接刷新，避免经由 Combine / SwiftUI 的全局发布 churn。
    func refresh() {
        let now = Date()
        engine.tick(now: now)
        persist(now: now)
    }

    // MARK: - 熄屏 / 睡眠自动暂停

    /// 熄屏或系统睡眠：自动暂停（仅当开启且正在计时、未处于手动暂停时）。
    private func handleScreenAway() {
        guard settings.pauseOnScreenSleep else { return }
        guard engine.phase != .idle, !engine.paused else { return }
        engine.pause(now: Date(), reason: .automatic)
        refresh()
    }

    /// 屏幕点亮或系统唤醒：按恢复规则恢复自动暂停。
    private func handleScreenWake() {
        switch settings.screenSleepResume {
        case .screenWake:
            engine.resumeIfAutomatic(now: Date())
        case .unlock:
            // 亮屏但仍在锁屏 → 等待解锁；否则（未启用锁屏）直接恢复。
            guard !clockObserver.isScreenLockedNow() else { return }
            engine.resumeIfAutomatic(now: Date())
        }
        refresh()
    }

    /// 屏幕解锁：仅解锁规则下恢复自动暂停。
    private func handleScreenUnlock() {
        guard settings.screenSleepResume == .unlock else { return }
        engine.resumeIfAutomatic(now: Date())
        refresh()
    }

    // MARK: - 手动控制

    func pauseOrResume() {
        let now = Date()
        if engine.paused { engine.resume(now: now) } else { engine.pause(now: now) }
        persist()
    }

    func skip() {
        let now = Date()
        engine.tick(now: now)
        engine.skip(now: now)
        persist()
    }

    func resetRound() {
        engine.resetRound(now: Date())
        persist()
    }

    func temporaryStart() {
        engine.temporaryStart(now: Date())
        persist()
    }

    func stop() {
        engine.stop(now: Date())
        persist()
    }

    // MARK: - 设置

    private func settingsDidChange(from old: AppSettings) {
        store.saveSettings(settings)
        engine.apply(settings: settings)
        if old.launchAtLogin != settings.launchAtLogin {
            LaunchAtLogin.set(settings.launchAtLogin)
        }
        refresh()
    }

    // MARK: - 内部

    private func persist(now: Date = Date()) {
        let snapshot = engine.snapshot(now: now)
        // 仅当对挂件有意义的状态真正变化时才编码写入并刷新时间线，
        // 避免每秒 `JSONEncoder.encode` + `UserDefaults.set`（cfprefsd）churn。
        let signature = [
            snapshot.phase.rawValue,
            String(snapshot.phaseEnd.timeIntervalSince1970),
            String(snapshot.windowEnd?.timeIntervalSince1970 ?? 0),
            String(snapshot.nextWindowStart?.timeIntervalSince1970 ?? -1),
            String(snapshot.paused),
            String(snapshot.freeRun),
        ].joined(separator: "|")
        guard signature != lastReloadSignature else { return }
        lastReloadSignature = signature
        store.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func handle(_ event: TimerEvent) {
        notifications.post(event, settings: settings)
    }
}

// MARK: - 内存诊断

/// 轻量诊断工具：记录进程 `phys_footprint`，用于内存增长排查的前后对照。
private enum MemoryDiagnostics {

    static func logFootprint() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let megabytes = Double(info.phys_footprint) / 1_048_576.0
        print(String(format: "[Rhythm] phys_footprint = %.1f MB", megabytes))
    }
}
