//
//  TimerEngineTests.swift
//  RhythmTests
//

import XCTest
import Combine

final class TimerEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 星期一。
    private func monday(_ hour: Int, _ minute: Int) -> Date {
        date(2026, 1, 5, hour, minute)
    }

    private func wideSettings(
        work: Int = 40,
        rest: Int = 5,
        notifyPhase: Bool = true,
        notifyWindow: Bool = false
    ) -> AppSettings {
        AppSettings(
            workMinutes: work,
            restMinutes: rest,
            ranges: [TimeRange(startHour: 9, startMinute: 0, endHour: 18, endMinute: 0)],
            activeWeekdays: AppSettings.weekdaysMondayToFriday,
            notifyOnPhaseEnd: notifyPhase,
            notifyOnWindowEnd: notifyWindow
        )
    }

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    // MARK: - 循环

    func testColdStartInWindowStartsWorkFromNow() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseEnd, monday(9, 0).addingTimeInterval(minutes(40)))
        XCTAssertEqual(engine.windowEnd, monday(18, 0))
    }

    func testWorkToRestToWork() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))

        engine.tick(now: monday(9, 40))
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertEqual(engine.phaseEnd, monday(9, 45))

        engine.tick(now: monday(9, 45))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseEnd, monday(10, 25))
    }

    func testCoalescesLongSleepToSingleNotification() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }
        engine.tick(now: monday(9, 0))
        events.removeAll()

        // 直接跳到 11:00，跨过多个相位。
        engine.tick(now: monday(11, 0))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseEnd, monday(11, 10))
        XCTAssertEqual(events.filter { if case .phaseChanged = $0 { return true } else { return false } }.count, 1)
    }

    func testBothDirectionsEmitNotification() {
        let engine = TimerEngine(
            settings: wideSettings(work: 1, rest: 1),
            calendar: calendar,
            now: monday(9, 0)
        )
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }

        engine.tick(now: monday(9, 0))
        engine.tick(now: monday(9, 1))
        engine.tick(now: monday(9, 2))

        XCTAssertTrue(events.contains(.phaseChanged(from: .work, to: .rest)))
        XCTAssertTrue(events.contains(.phaseChanged(from: .rest, to: .work)))
    }

    // MARK: - 时段末裁剪

    func testWindowEndTruncatesPhase() {
        let settings = AppSettings(
            workMinutes: 40,
            restMinutes: 5,
            ranges: [TimeRange(startHour: 9, startMinute: 0, endHour: 9, endMinute: 30)],
            activeWeekdays: [2],
            notifyOnWindowEnd: true
        )
        let engine = TimerEngine(settings: settings, calendar: calendar, now: monday(9, 0))
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }

        engine.tick(now: monday(9, 0))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseEnd, monday(9, 30))

        engine.tick(now: monday(9, 30))
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertTrue(events.contains(.windowEnded))
    }

    func testWindowEndNotificationGatedBySetting() {
        let settings = AppSettings(
            workMinutes: 40,
            restMinutes: 5,
            ranges: [TimeRange(startHour: 9, startMinute: 0, endHour: 9, endMinute: 30)],
            activeWeekdays: [2],
            notifyOnWindowEnd: false
        )
        let engine = TimerEngine(settings: settings, calendar: calendar, now: monday(9, 0))
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }
        engine.tick(now: monday(9, 0))
        engine.tick(now: monday(9, 30))
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertFalse(events.contains(.windowEnded))
    }

    // MARK: - 暂停 / 继续

    func testPauseAndResume() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        engine.pause(now: monday(9, 10))
        XCTAssertTrue(engine.paused)
        XCTAssertEqual(engine.remaining(at: monday(9, 10)), minutes(30))

        // 暂停期间推进，剩余不变。
        engine.tick(now: monday(9, 20))
        XCTAssertEqual(engine.remaining(at: monday(9, 20)), minutes(30))

        engine.resume(now: monday(9, 20))
        XCTAssertFalse(engine.paused)
        XCTAssertEqual(engine.phaseEnd, monday(9, 50))
    }

    // MARK: - 自动暂停 / 恢复

    func testAutomaticPauseAndResumeIfAutomatic() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))

        engine.pause(now: monday(9, 10), reason: .automatic)
        XCTAssertTrue(engine.paused)
        XCTAssertEqual(engine.pauseReason, .automatic)
        XCTAssertEqual(engine.remaining(at: monday(9, 10)), minutes(30))

        // 暂停期间推进，剩余冻结。
        engine.tick(now: monday(9, 30))
        XCTAssertEqual(engine.remaining(at: monday(9, 30)), minutes(30))

        engine.resumeIfAutomatic(now: monday(9, 30))
        XCTAssertFalse(engine.paused)
        XCTAssertNil(engine.pauseReason)
        XCTAssertEqual(engine.phaseEnd, monday(10, 0))
    }

    func testManualPauseNotResumedByAutomatic() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))

        engine.pause(now: monday(9, 10))
        XCTAssertEqual(engine.pauseReason, .user)

        engine.resumeIfAutomatic(now: monday(9, 20))
        XCTAssertTrue(engine.paused)
        XCTAssertEqual(engine.pauseReason, .user)
        XCTAssertEqual(engine.remaining(at: monday(9, 20)), minutes(30))
    }

    func testAutomaticPauseOnIdleIsNoOp() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(8, 0))
        engine.tick(now: monday(8, 0))
        XCTAssertEqual(engine.phase, .idle)

        engine.pause(now: monday(8, 0), reason: .automatic)
        XCTAssertFalse(engine.paused)
        XCTAssertNil(engine.pauseReason)
    }

    func testAutomaticPauseAcrossWindowEndGoesIdleOnResume() {
        let settings = AppSettings(
            workMinutes: 40,
            restMinutes: 5,
            ranges: [TimeRange(startHour: 9, startMinute: 0, endHour: 9, endMinute: 30)],
            activeWeekdays: [2]
        )
        let engine = TimerEngine(settings: settings, calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        XCTAssertEqual(engine.phaseEnd, monday(9, 30))

        engine.pause(now: monday(9, 5), reason: .automatic)
        XCTAssertEqual(engine.remaining(at: monday(9, 5)), minutes(25))

        // 恢复时刻已越过 windowEnd：tick 内部结束循环回到 idle。
        engine.resumeIfAutomatic(now: monday(9, 40))
        XCTAssertFalse(engine.paused)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.pauseReason)
    }

    // MARK: - 跳过 / 重置

    func testSkipWorkGoesToRest() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        engine.skip(now: monday(9, 10))
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertEqual(engine.phaseEnd, monday(9, 15))

        engine.skip(now: monday(9, 15))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseEnd, monday(9, 55))
    }

    func testResetRoundRestartsFullWork() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        engine.tick(now: monday(9, 10))
        engine.resetRound(now: monday(9, 10))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseStart, monday(9, 10))
        XCTAssertEqual(engine.phaseEnd, monday(9, 50))
    }

    // MARK: - 时段外临时启动

    func testTemporaryStartOutsideWindow() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(8, 0))
        engine.tick(now: monday(8, 0))
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.nextWindowStart, monday(9, 0))

        engine.temporaryStart(now: monday(8, 0))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertTrue(engine.freeRun)
        XCTAssertEqual(engine.phaseEnd, monday(8, 40))

        // 循环继续。
        engine.tick(now: monday(8, 40))
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertEqual(engine.phaseEnd, monday(8, 45))
    }

    func testFreeRunAdoptsWindowWhenItStarts() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(8, 50))
        engine.temporaryStart(now: monday(8, 50))
        XCTAssertTrue(engine.freeRun)

        engine.tick(now: monday(9, 0))
        XCTAssertFalse(engine.freeRun)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseEnd, monday(9, 40))
        XCTAssertEqual(engine.windowEnd, monday(18, 0))
    }

    func testStopFreeRun() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(8, 0))
        engine.temporaryStart(now: monday(8, 0))
        engine.stop(now: monday(8, 5))
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertFalse(engine.freeRun)
    }

    // MARK: - 跨时段

    func testJumpToNextWindowRestartsFromNow() {
        let settings = AppSettings(
            workMinutes: 40,
            restMinutes: 5,
            ranges: AppSettings.defaultRanges,
            activeWeekdays: [2]
        )
        let engine = TimerEngine(settings: settings, calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))

        // 跳到下午时段内。
        engine.tick(now: monday(14, 0))
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.phaseStart, monday(14, 0))
        XCTAssertEqual(engine.phaseEnd, monday(14, 40))
        XCTAssertEqual(engine.windowEnd, monday(18, 0))
    }

    func testLeavingWindowGoesIdle() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        // 跳过 18:00 之后。
        engine.tick(now: monday(19, 0))
        XCTAssertEqual(engine.phase, .idle)
        // 第二天（星期二）09:00。
        XCTAssertEqual(engine.nextWindowStart, date(2026, 1, 6, 9, 0))
    }

    // MARK: - 快照

    func testSnapshotReflectsState() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))
        let snapshot = engine.snapshot(now: monday(9, 0))
        XCTAssertEqual(snapshot.phase, .work)
        XCTAssertEqual(snapshot.phaseEnd, monday(9, 40))
        XCTAssertEqual(snapshot.windowEnd, monday(18, 0))
        XCTAssertFalse(snapshot.paused)
    }

    // MARK: - 发布行为（内存 churn 回归）

    private func changeCount(_ engine: TimerEngine, while body: () -> Void) -> Int {
        var changes = 0
        let cancellable = engine.objectWillChange.sink { _ in changes += 1 }
        body()
        cancellable.cancel()
        return changes
    }

    func testTickInIdleWithUnchangedStateDoesNotPublish() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(8, 0))
        engine.tick(now: monday(8, 0))

        // 空闲态每秒都会重算 nextWindowStart；值不变时不得发出 objectWillChange。
        let changes = changeCount(engine) {
            engine.tick(now: monday(8, 0).addingTimeInterval(1))
            engine.tick(now: monday(8, 0).addingTimeInterval(2))
        }
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(engine.nextWindowStart, monday(9, 0))
    }

    func testTickDuringActiveWorkWithoutTransitionDoesNotPublish() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))

        let changes = changeCount(engine) {
            engine.tick(now: monday(9, 10))
        }
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(engine.phase, .work)
    }

    func testTickStillPublishesOnPhaseTransition() {
        let engine = TimerEngine(settings: wideSettings(), calendar: calendar, now: monday(9, 0))
        engine.tick(now: monday(9, 0))

        let changes = changeCount(engine) {
            engine.tick(now: monday(9, 40))
        }
        XCTAssertEqual(engine.phase, .rest)
        XCTAssertGreaterThan(changes, 0)
    }
}
