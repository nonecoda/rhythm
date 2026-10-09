//
//  NotificationService.swift
//  Rhythm
//

import Foundation
import UserNotifications

/// 系统通知服务：请求授权、发送相位/时段通知、前台也显示 banner。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 根据事件发送通知；声音由 `settings.soundEnabled` 控制。
    func post(_ event: TimerEvent, settings: AppSettings) {
        let content = UNMutableNotificationContent()
        if settings.soundEnabled {
            content.sound = .default
        }
        switch event {
        case let .phaseChanged(_, to):
            switch to {
            case .rest:
                content.title = "该休息了"
                content.body = "工作阶段结束，休息 \(settings.restMinutes) 分钟。"
            case .work:
                content.title = "继续工作"
                content.body = "休息结束，开始 \(settings.workMinutes) 分钟工作。"
            case .idle:
                return
            }
        case .windowEnded:
            content.title = "时段已结束"
            content.body = "当前生效时段结束，计时已停止。"
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
