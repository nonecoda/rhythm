//
//  ClockObserver.swift
//  Rhythm
//
//  监听系统唤醒、时钟变更、时区变更，触发重新计算，避免剩余时间为负或跳变。
//

import Foundation
import AppKit

final class ClockObserver {

    var onEvent: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent?()
            }
        )

        let defaultCenter = NotificationCenter.default
        observers.append(
            defaultCenter.addObserver(
                forName: NSNotification.Name.NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent?()
            }
        )
        observers.append(
            defaultCenter.addObserver(
                forName: NSNotification.Name.NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent?()
            }
        )
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            defaultCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        stop()
    }
}
