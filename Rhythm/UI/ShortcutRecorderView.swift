//
//  ShortcutRecorderView.swift
//  Rhythm
//

import SwiftUI
import KeyboardShortcuts

/// 录制“跳过休息”全局快捷键。
struct ShortcutRecorderView: View {
    var body: some View {
        KeyboardShortcuts.Recorder("跳过休息：", name: .skipRest)
    }
}
