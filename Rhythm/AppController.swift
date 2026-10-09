//
//  AppController.swift
//  Rhythm
//
//  应用层协调器：驱动 1 秒心跳、持久化快照、刷新挂件、分发通知与全局快捷键。
//

import Foundation
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

    /// 每秒更新一次，供菜单栏文本刷新（低频，避免状态栏项抖动）。
    @Published private(set) var now: Date = Date()

    let engine: TimerEngine

    private let store: SharedStore
    private let notifications: NotificationService
    private let clockObserver = ClockObserver()
    private var timer: Timer?
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
    var menuBarText: String {
        switch engine.phase {
        case .idle:
            return "--:--"
        case .work, .rest:
            if let frozen = engine.pausedRemainingSeconds {
                return Self.format(frozen)
            }
            return Self.format(engine.remaining(at: now))
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
            return "\(engine.phase.displayName) · 剩余 \(Self.format(engine.remaining(at: now)))"
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
    }

    /// 每秒 / 唤醒 / 时钟变更时重算并持久化。
    func refresh() {
        let now = Date()
        self.now = now
        engine.tick(now: now)
        persist(now: now)
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
        store.saveSnapshot(snapshot)
        let signature = "\(snapshot.phase.rawValue)|\(snapshot.phaseEnd.timeIntervalSince1970)|\(snapshot.windowEnd?.timeIntervalSince1970 ?? 0)|\(snapshot.paused)|\(snapshot.freeRun)"
        if signature != lastReloadSignature {
            lastReloadSignature = signature
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func handle(_ event: TimerEvent) {
        notifications.post(event, settings: settings)
    }
}
