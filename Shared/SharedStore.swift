//
//  SharedStore.swift
//  Rhythm
//
//  App Group 持久化：设置 + 实时快照。App 与挂件共用同一份实现。
//

import Foundation

/// 通过 App Group `UserDefaults` 共享设置与快照。
///
/// 数据以 JSON `Data` 存储，避免 `UserDefaults` 对嵌套类型的局限。
/// 若 App Group 不可用（例如个人团队签名降级），退化为标准 `UserDefaults`，
/// 此时挂件无法读取实时快照，App 本体功能不受影响。
public final class SharedStore {
    public static let shared = SharedStore()

    private enum Key {
        static let settings = "rhythm.settings.v1"
        static let snapshot = "rhythm.snapshot.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// `suiteName` 为 App Group 标识符；不可用时回退。
    public init(suiteName: String = AppGroup.identifier) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Settings

    public func loadSettings() -> AppSettings {
        guard
            let data = defaults.data(forKey: Key.settings),
            let settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    public func saveSettings(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }

    // MARK: - Snapshot

    public func loadSnapshot() -> TimerSnapshot? {
        guard
            let data = defaults.data(forKey: Key.snapshot),
            let snapshot = try? decoder.decode(TimerSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    public func saveSnapshot(_ snapshot: TimerSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    public func clearSnapshot() {
        defaults.removeObject(forKey: Key.snapshot)
    }
}
