//
//  LaunchAtLogin.swift
//  Rhythm
//

import Foundation
import ServiceManagement

/// 使用 `SMAppService` 管理开机自启（macOS 13+）。
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Rhythm: 设置开机自启失败 - \(error.localizedDescription)")
        }
    }
}
