//
//  AppDelegate.swift
//  Rhythm
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 无 Dock 图标，后台常驻。
        NSApp.setActivationPolicy(.accessory)

        let controller = AppController.shared
        statusBar = StatusBarController(controller: controller)
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
