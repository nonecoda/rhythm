//
//  SettingsWindowController.swift
//  Rhythm
//
//  用原生 NSWindow 承载 SwiftUI 设置界面，避免菜单栏 App 打开设置场景的不确定性。
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(controller: AppController) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(controller: controller))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Rhythm 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
