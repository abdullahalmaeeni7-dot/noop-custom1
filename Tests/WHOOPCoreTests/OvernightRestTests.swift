import Foundation
import XCTest
@testable import WHOOPCore

final class OvernightRestTests: XCTestCase {
    private let formatter = ISO8601DateFormatter()
    private let dubai = TimeZone(identifier: "Asia/Dubai")!

    private func series(from start: Date, minutes: Int) -> [HeartRateSample] {
        (0...minutes).map { offset in
            var reading = HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(offset * 60)), bpm: 58)
            reading.trackerContactReading = true
            return reading
        }
    }

    private func archive(_ samples: [HeartRateSample], resting: Double? = 60) -> [DailySnapshot] {
        Dictionary(grouping: samples, by: { DayCalendar.start(of: $0.timestamp) }).map { date, rates in
            var day = DailySnapshot.empty(on: date)
            day.heartRates = rates
            day.restingHeartRate = resting
            return day
        }
    }

    func testLocalNightUsesObservedEndpointsAcrossArchiveDays() {
        let start = formatter.date(from: "2026-11-23T19:10:23Z")! // 23:10 Dubai
        let key = formatter.date(from: "2026-11-24T00:00:00Z")!
        let samples = series(from: start, minutes: 360)
        let result = OvernightRest.candidate(wakeDay: key, days: archive(samples), activities: [],
                                             now: key.addingTimeInterval(7200), timeZone: dubai)
        XCTAssertEqual(result, DateInterval(start: start, duration: 360 * 60))
    }

    func testSparseUnknownAndInterruptedInputCannotCreateAnInterval() {
        let start = formatter.date(from: "2026-11-23T20:04:00Z")!
        let key = formatter.date(from: "2026-11-24T00:00:00Z")!
        let samples = series(from: start, minutes: 180)
        var noContact = samples
        noContact[90].trackerContactReading = false
        var high = samples
        high[90].bpm = 135
        let old = samples.map { HeartRateSample(timestamp: $0.timestamp, bpm: $0.bpm) }
        let gap = Array(samples.prefix(85)) + Array(samples.suffix(85))
        let minuteSparse = samples.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        for source in [old, gap, high, noContact, minuteSparse] {
            XCTAssertNil(OvernightRest.candidate(wakeDay: key, days: archive(source), activities: [], now: key, timeZone: dubai))
        }
        XCTAssertNil(OvernightRest.candidate(wakeDay: key, days: archive(samples, resting: nil), activities: [], now: key, timeZone: dubai))
        let activity = ActivityRecord(start: samples[90].timestamp.addingTimeInterval(20), durationMinutes: 1, name: "Workout")
        XCTAssertNil(OvernightRest.candidate(wakeDay: key, days: archive(samples), activities: [activity], now: key, timeZone: dubai))
    }

    func testClockChangeMeasuresElapsedTimeAndRejectsFutureWakeDay() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let key = formatter.date(from: "2026-11-01T00:00:00Z")!
        let start = formatter.date(from: "2026-11-01T04:30:00Z")! // 00:30 EDT
        let end = start.addingTimeInterval(3 * 3600) // 02:30 EST
        let days = archive(series(from: start, minutes: 180))
        XCTAssertEqual(OvernightRest.candidate(wakeDay: key, days: days, activities: [], now: end, timeZone: newYork),
                       DateInterval(start: start, end: end))
        XCTAssertNil(OvernightRest.candidate(wakeDay: key, days: days, activities: [], now: key, timeZone: newYork))
    }

    func testFirstNightWithoutBaselineOffersOnlyAnObservedReviewInterval() {
        let key = formatter.date(from: "2026-11-24T00:00:00Z")!
        let start = formatter.date(from: "2026-11-23T19:15:05Z")! // 23:15 Dubai
        let samples = series(from: start, minutes: 240)
        let days = archive(samples, resting: nil)
        let interval = OvernightRest.candidate(wakeDay: key, days: days, activities: [],
                                               now: key, timeZone: dubai)
        XCTAssertEqual(interval, DateInterval(start: start, duration: 4 * 3600))
        XCTAssertTrue(days.allSatisfy { $0.displayedSleepMinutes == 0 && $0.confirmedSleep == nil })
    }

    func testFirstNightReviewRejectsDaytimeGapsUnknownContactAndExertion() {
        let key = formatter.date(from: "2026-11-24T00:00:00Z")!
        let morning = key.addingTimeInterval(8 * 3600) // noon Dubai
        let samples = series(from: key.addingTimeInterval(-4 * 3600), minutes: 300)
        let daytime = series(from: key.addingTimeInterval(2 * 3600), minutes: 300)
        var unknown = samples
        unknown[150].trackerContactReading = nil
        var elevated = samples
        elevated[150].bpm = 110
        var offBody = samples
        offBody[150].trackerContactReading = false
        let gap = Array(samples[..<145]) + Array(samples[150...])
        for source in [daytime, gap, unknown, elevated, offBody] {
            XCTAssertNil(OvernightRest.candidate(wakeDay: key, days: archive(source, resting: nil),
                                                 activities: [], now: morning, timeZone: dubai))
        }
        let workout = ActivityRecord(start: samples[150].timestamp, durationMinutes: 10, name: "Workout")
        XCTAssertNil(OvernightRest.candidate(wakeDay: key, days: archive(samples, resting: nil),
                                             activities: [workout], now: morning, timeZone: dubai))
    }
}
