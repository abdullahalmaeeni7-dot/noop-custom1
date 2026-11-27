import XCTest
@testable import WHOOPCore

final class TrackerAnalysisTests: XCTestCase {
    let utc = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_795_651_200)

    func testSavedHistoryProducesStrainAndReplayDoesNotDoubleCount() throws {
        var day = DailySnapshot.empty(on: start)
        day.heartRates = (0...60).map { HeartRateSample(timestamp: start.addingTimeInterval(Double($0) * 60), bpm: 150, trackerRecorded: true) }
        let now = start.addingTimeInterval(7200)
        let single = TrackerAnalysis.calculate(days: [day], activities: [], now: now, timeZone: utc)
        let replay = TrackerAnalysis.calculate(days: [day, day], activities: [], now: now, timeZone: utc)
        XCTAssertEqual(single, replay)
        XCTAssertGreaterThan(try XCTUnwrap(single.values.first?.strain), 0)
    }

    func testLongGapsAndUnattributedImportsDoNotGenerateLoad() {
        var day = DailySnapshot.empty(on: start)
        day.heartRates = [HeartRateSample(timestamp: start, bpm: 170, trackerRecorded: true),
                         HeartRateSample(timestamp: start.addingTimeInterval(3600), bpm: 170, trackerRecorded: true)]
        let sparse = TrackerAnalysis.calculate(days: [day], activities: [], now: start.addingTimeInterval(7200), timeZone: utc)
        XCTAssertNil(sparse.values.first?.strain)
        day.heartRates = (0...60).map { HeartRateSample(timestamp: start.addingTimeInterval(Double($0) * 60), bpm: 150) }
        XCTAssertTrue(TrackerAnalysis.calculate(days: [day], activities: [], now: start.addingTimeInterval(7200), timeZone: utc).isEmpty)
    }

    func testAutomaticSleepRequiresReadingsAfterRestAndPreservesProviderValues() throws {
        let midnight = DayCalendar.start(of: start)
        var day = DailySnapshot.empty(on: midnight)
        day.heartRates = (0...300).map { HeartRateSample(timestamp: midnight.addingTimeInterval(Double($0) * 60), bpm: 55, trackerRecorded: true) }
        let now = midnight.addingTimeInterval(8 * 3600)
        XCTAssertNil(TrackerAnalysis.calculate(days: [day], activities: [], now: now, timeZone: utc)[midnight]?.sleepMinutes)
        day.heartRates += (301...330).map { HeartRateSample(timestamp: midnight.addingTimeInterval(Double($0) * 60), bpm: 100, trackerRecorded: true) }
        let analysis = TrackerAnalysis.calculate(days: [day], activities: [], now: now, timeZone: utc)
        XCTAssertEqual(analysis[midnight]?.sleepMinutes, 300)
        day.sleepMinutes = 420
        day.estimatedSleepMinutes = analysis[midnight]?.sleepMinutes
        day.strain = 12
        day.estimatedTrackerStrain = 5
        XCTAssertEqual(day.displayedSleepMinutes, 420)
        XCTAssertEqual(day.displayedStrain, 12)
    }

    func testLocalDayAndExampleExclusion() {
        let dubai = TimeZone(identifier: "Asia/Dubai")!
        let sampleTime = DayCalendar.start(of: start).addingTimeInterval(22 * 3600)
        var day = DailySnapshot.empty(on: sampleTime)
        day.heartRates = (0...3).map { HeartRateSample(timestamp: sampleTime.addingTimeInterval(Double($0) * 60), bpm: 140, trackerRecorded: true) }
        let result = TrackerAnalysis.calculate(days: [day], activities: [], now: sampleTime.addingTimeInterval(600), timeZone: dubai)
        XCTAssertNotNil(result[DashboardDatePolicy.today(now: sampleTime, timeZone: dubai)]?.strain)
        day.source = .example
        XCTAssertTrue(TrackerAnalysis.calculate(days: [day], activities: [], now: sampleTime.addingTimeInterval(600), timeZone: dubai).isEmpty)
    }
}
