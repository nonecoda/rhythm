//
//  ScheduleEngineTests.swift
//  RhythmTests
//

import XCTest

final class ScheduleEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 2026-01-05 是星期一。
    private func mondayEngine(_ ranges: [TimeRange] = AppSettings.defaultRanges) -> ScheduleEngine {
        ScheduleEngine(
            ranges: ranges,
            activeWeekdays: AppSettings.weekdaysMondayToFriday,
            calendar: calendar
        )
    }

    func testCurrentWindowHit() {
        let engine = mondayEngine()
        let window = engine.currentWindow(at: date(2026, 1, 5, 10, 0))
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.start, date(2026, 1, 5, 9, 0))
        XCTAssertEqual(window?.end, date(2026, 1, 5, 12, 0))
    }

    func testCurrentWindowMissBeforeStart() {
        let engine = mondayEngine()
        XCTAssertNil(engine.currentWindow(at: date(2026, 1, 5, 8, 59)))
    }

    func testCurrentWindowBoundaryIsHalfOpen() {
        let engine = mondayEngine()
        // 起点计入，终点不计入。
        XCTAssertNotNil(engine.currentWindow(at: date(2026, 1, 5, 9, 0)))
        XCTAssertNil(engine.currentWindow(at: date(2026, 1, 5, 12, 0)))
    }

    func testCurrentWindowSecondRange() {
        let engine = mondayEngine()
        let window = engine.currentWindow(at: date(2026, 1, 5, 14, 0))
        XCTAssertEqual(window?.start, date(2026, 1, 5, 13, 30))
        XCTAssertEqual(window?.end, date(2026, 1, 5, 18, 0))
    }

    func testInactiveWeekdayReturnsNil() {
        let engine = mondayEngine()
        // 2026-01-10 是星期六。
        XCTAssertNil(engine.currentWindow(at: date(2026, 1, 10, 10, 0)))
    }

    func testNextWindowStartSameDay() {
        let engine = mondayEngine()
        XCTAssertEqual(engine.nextWindowStart(after: date(2026, 1, 5, 12, 30)), date(2026, 1, 5, 13, 30))
    }

    func testNextWindowStartSkipsCurrentWindow() {
        let engine = mondayEngine()
        // 处于第一段内，下一个起点应是当天第二段。
        XCTAssertEqual(engine.nextWindowStart(after: date(2026, 1, 5, 10, 0)), date(2026, 1, 5, 13, 30))
    }

    func testNextWindowStartRollsToNextActiveDay() {
        let engine = mondayEngine()
        // 2026-01-09 星期五 18:30 → 下周一 09:00（2026-01-12）。
        XCTAssertEqual(engine.nextWindowStart(after: date(2026, 1, 9, 18, 30)), date(2026, 1, 12, 9, 0))
    }

    func testAdjacentWindows() {
        let engine = mondayEngine([
            TimeRange(startHour: 9, startMinute: 0, endHour: 12, endMinute: 0),
            TimeRange(startHour: 12, startMinute: 0, endHour: 13, endMinute: 0),
        ])
        XCTAssertEqual(engine.currentWindow(at: date(2026, 1, 5, 11, 0))?.start, date(2026, 1, 5, 9, 0))
        XCTAssertEqual(engine.currentWindow(at: date(2026, 1, 5, 12, 30))?.start, date(2026, 1, 5, 12, 0))
    }

    func testEmptyRangesNeverActive() {
        let engine = mondayEngine([])
        XCTAssertNil(engine.currentWindow(at: date(2026, 1, 5, 10, 0)))
        XCTAssertNil(engine.nextWindowStart(after: date(2026, 1, 5, 10, 0)))
    }
}
