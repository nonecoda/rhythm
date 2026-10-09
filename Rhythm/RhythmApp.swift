//
//  RhythmApp.swift
//  Rhythm
//

import SwiftUI

@main
struct RhythmApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏与设置窗口均由 AppKit 管理（见 AppDelegate / StatusBarController）。
        // 这里保留一个 Settings 场景以满足 App 需要至少一个 Scene 的要求。
        Settings {
            SettingsView(controller: AppController.shared)
        }
    }
}
