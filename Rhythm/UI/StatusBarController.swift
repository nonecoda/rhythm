//
//  StatusBarController.swift
//  Rhythm
//
//  原生 NSStatusItem 菜单栏项：固定长度 + 表格数字字体，彻底避免 SwiftUI
//  MenuBarExtra 标签光栅化/重新布局导致的左右抖动。
//

import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    private let controller: AppController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private var lastSymbolName: String?

    /// 固定宽度需容纳「图标 + 最长 h:mm:ss」。
    private let fixedLength: CGFloat = 78

    init(controller: AppController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: fixedLength)
        super.init()

        configureButton()
        menu.delegate = self
        statusItem.menu = menu
        updateButton()

        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
    }

    // MARK: - 按钮

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        button.imageScaling = .scaleProportionallyDown
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }

        let phase = controller.engine.phase
        if phase.symbolName != lastSymbolName {
            lastSymbolName = phase.symbolName
            let image = NSImage(systemSymbolName: phase.symbolName, accessibilityDescription: phase.displayName)
            image?.isTemplate = true
            button.image = image
        }

        let text = controller.menuBarText
        if button.title != text {
            button.title = text
        }
        button.toolTip = controller.statusText
    }

    // MARK: - 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: controller.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if controller.engine.phase != .idle {
            menu.addItem(makeItem(controller.engine.paused ? "继续" : "暂停", #selector(togglePause)))
            menu.addItem(makeItem("跳过当前阶段", #selector(skipPhase)))
            menu.addItem(makeItem("重置本轮", #selector(resetRound)))
            if controller.engine.freeRun {
                menu.addItem(makeItem("停止临时循环", #selector(stopTemporary)))
            }
        } else {
            menu.addItem(makeItem("临时启动", #selector(temporaryStart)))
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("设置…", #selector(openSettings)))
        menu.addItem(makeItem("退出", #selector(quit)))
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 动作

    @objc private func togglePause() { controller.pauseOrResume() }
    @objc private func skipPhase() { controller.skip() }
    @objc private func resetRound() { controller.resetRound() }
    @objc private func temporaryStart() { controller.temporaryStart() }
    @objc private func stopTemporary() { controller.stop() }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(controller: controller)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
