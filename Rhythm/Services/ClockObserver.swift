//
//  ClockObserver.swift
//  Rhythm
//
//  监听系统唤醒 / 熄屏 / 睡眠 / 锁屏、时钟变更、时区变更，触发重新计算或自动暂停，
//  避免剩余时间为负或跳变。
//

import Foundation
import AppKit
import CoreGraphics

final class ClockObserver {

    /// 通用重算事件（时钟 / 时区变更，以及系统唤醒）。
    var onEvent: (() -> Void)?
    /// 熄屏或系统睡眠（离开）。
    var onAway: (() -> Void)?
    /// 屏幕点亮或系统唤醒。
    var onWake: (() -> Void)?
    /// 屏幕解锁。
    var onUnlock: (() -> Void)?

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var screenLocked = false

    private static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenIsUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    func start() {
        guard observers.isEmpty else { return }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.onWake?()
            self?.onEvent?()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.onAway?()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.onAway?()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.onWake?()
        }

        let defaultCenter = NotificationCenter.default
        observe(defaultCenter, .NSSystemClockDidChange) { [weak self] in
            self?.onEvent?()
        }
        observe(defaultCenter, .NSSystemTimeZoneDidChange) { [weak self] in
            self?.onEvent?()
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Self.screenIsLocked) { [weak self] in
            self?.screenLocked = true
        }
        observe(distributed, Self.screenIsUnlocked) { [weak self] in
            self?.screenLocked = false
            self?.onUnlock?()
        }
    }

    /// 当前是否处于锁屏状态（读取会话信息，避免依赖通知到达时序）。
    func isScreenLockedNow() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return screenLocked
        }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            handler()
        }
        observers.append((center, token))
    }

    deinit {
        stop()
    }
}
