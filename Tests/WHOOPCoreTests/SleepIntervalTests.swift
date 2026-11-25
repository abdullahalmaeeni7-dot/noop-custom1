import Foundation
import XCTest
@testable import WHOOPCore

final class SleepIntervalTests: XCTestCase {
    private func interval(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    func testOverlappingStagesAndDuplicateSourcesCountOnce() {
        let episodes = [interval(120, 420), interval(0, 240), interval(0, 240), interval(180, 300)]
        XCTAssertEqual(SleepIntervals.seconds(episodes, within: interval(0, 600)), 420)
    }

    func testDisjointEpisodesPreserveAwakeGap() {
        XCTAssertEqual(SleepIntervals.minutes([interval(0, 120), interval(180, 300)], within: interval(0, 600)), 4)
    }

    func testCrossMidnightSleepClipsToEachUTCDay() {
        let date = DayCalendar.start(of: Date(timeIntervalSince1970: 1_793_491_200))
        let next = date.addingTimeInterval(86_400)
        let sleep = DateInterval(start: next.addingTimeInterval(-3_600), end: next.addingTimeInterval(7_200))
        XCTAssertEqual(SleepIntervals.minutes([sleep], within: DateInterval(start: date, end: next)), 60)
        XCTAssertEqual(SleepIntervals.minutes([sleep], within: DateInterval(start: next, duration: 86_400)), 120)
    }

    func testTouchingBoundariesEmptyRangesAndOutsideIntervals() {
        XCTAssertEqual(SleepIntervals.seconds([interval(0, 60), interval(60, 120)], within: interval(0, 120)), 120)
        XCTAssertEqual(SleepIntervals.seconds([interval(0, 60), interval(120, 180)], within: interval(60, 120)), 0)
        XCTAssertEqual(SleepIntervals.seconds([interval(0, 120)], within: interval(60, 60)), 0)
        XCTAssertEqual(SleepIntervals.seconds([], within: interval(0, 120)), 0)
    }

    func testRoundingOccursAfterUnionAndRangeIsMaximum() {
        XCTAssertEqual(SleepIntervals.minutes([interval(0, 35), interval(40, 75)], within: interval(0, 100)), 1)
        XCTAssertEqual(SleepIntervals.seconds([interval(-1_000, 1_000)], within: interval(0, 100)), 100)
    }
    func testNightBelongsToDubaiWakeDateAndAwakeGapsAreExcluded() throws {
        let format = ISO8601DateFormatter()
        let wakeDay = try XCTUnwrap(format.date(from: "2026-11-24T00:00:00Z"))
        let first = DateInterval(start: wakeDay.addingTimeInterval(-5 * 3600), duration: 3 * 3600)
        let second = DateInterval(start: wakeDay.addingTimeInterval(-1.5 * 3600), duration: 3 * 3600)
        let overlap = DateInterval(start: second.start.addingTimeInterval(300), duration: 1800)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Dubai"))
        let totals = SleepIntervals.minutesByWakeDay([overlap, second, first, first], now: second.end, timeZone: zone)
        XCTAssertEqual(totals, [wakeDay: 360])
    }

    func testMidnightAndDaylightSavingKeepActualElapsedSleep() throws {
        let format = ISO8601DateFormatter()
        let start = try XCTUnwrap(format.date(from: "2026-11-01T04:00:00Z"))
        // The New York autumn clock change adds an hour of actual elapsed time.
        let end = start.addingTimeInterval(8 * 3600)
        let sleep = DateInterval(start: start, end: end)
        let nextNight = DateInterval(start: end.addingTimeInterval(24 * 3600), duration: 3600)
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let wakeDay = DayCalendar.start(of: start)
        XCTAssertEqual(SleepIntervals.minutesByWakeDay([sleep, nextNight], now: end, timeZone: zone), [wakeDay: 480])
    }

    func testSleepEndingAfterLocalMidnightCanWakeOnDayAfterUTCRecord() throws {
        let wake = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-23T22:00:00Z"))
        let interval = DateInterval(start: wake.addingTimeInterval(-4 * 3600), end: wake)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Dubai"))
        let nextUTCDay = DayCalendar.start(of: wake).addingTimeInterval(86_400)
        XCTAssertEqual(SleepIntervals.minutesByWakeDay([interval], now: wake, timeZone: zone), [nextUTCDay: 240])
    }

    func testAppleHealthSleepFillsMissingDurationAndAcceptsCorrectionsUntilProviderArrives() {
        let date = DayCalendar.start(of: Date())
        var saved = DailySnapshot.empty(on: date)
        var health = DailySnapshot.empty(on: date)
        health.sleepFromAppleHealth = true
        health.sleepMinutes = 400
        saved.mergeReportedSleep(from: health)
        XCTAssertEqual(saved.sleepMinutes, 400)
        health.sleepMinutes = 380
        saved.mergeReportedSleep(from: health)
        XCTAssertEqual(saved.sleepMinutes, 380)
        var provider = DailySnapshot.empty(on: date)
        provider.sleepMinutes = 395
        saved.mergeReportedSleep(from: provider)
        saved.mergeReportedSleep(from: health)
        XCTAssertEqual(saved.sleepMinutes, 395)
        XCTAssertNil(saved.sleepFromAppleHealth)
    }

}
