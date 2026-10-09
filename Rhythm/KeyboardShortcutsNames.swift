//
//  KeyboardShortcutsNames.swift
//  Rhythm
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 全局快捷键：跳过休息。
    static let skipRest = Self(
        "skipRest",
        default: .init(.r, modifiers: [.command, .shift])
    )
}
