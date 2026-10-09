//
//  Provider.swift
//  RhythmWidget
//

import WidgetKit
import SwiftUI

struct RhythmEntry: TimelineEntry {
    let date: Date
    let phase: Phase
    let phaseStart: Date
    let phaseEnd: Date
    let nextWindowStart: Date?
    let paused: Bool
}

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> RhythmEntry {
        let now = Date()
        return RhythmEntry(
            date: now,
            phase: .work,
            phaseStart: now,
            phaseEnd: now.addingTimeInterval(40 * 60),
            nextWindowStart: nil,
            paused: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RhythmEntry) -> Void) {
        completion(makeEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RhythmEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now: now)
        completion(Timeline(entries: [entry], policy: .after(nextReloadDate(from: entry, now: now))))
    }

    // MARK: - 私有

    private func makeEntry(now: Date) -> RhythmEntry {
        guard let snapshot = SharedStore().loadSnapshot() else {
            return RhythmEntry(
                date: now,
                phase: .idle,
                phaseStart: now,
                phaseEnd: now,
                nextWindowStart: nil,
                paused: false
            )
        }
        return RhythmEntry(
            date: now,
            phase: snapshot.phase,
            phaseStart: snapshot.phaseStart,
            phaseEnd: snapshot.phaseEnd,
            nextWindowStart: snapshot.nextWindowStart,
            paused: snapshot.paused
        )
    }

    private func nextReloadDate(from entry: RhythmEntry, now: Date) -> Date {
        if entry.phase != .idle, entry.phaseEnd > now {
            return min(entry.phaseEnd, now.addingTimeInterval(30 * 60))
        }
        if let next = entry.nextWindowStart, next > now {
            return next
        }
        return now.addingTimeInterval(15 * 60)
    }
}
