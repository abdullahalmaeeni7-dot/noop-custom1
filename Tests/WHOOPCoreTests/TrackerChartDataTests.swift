import XCTest
@testable import WHOOPCore

final class TrackerChartDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func sample(_ offset: Double, _ bpm: Double = 80, tracked: Bool = true) -> HeartRateSample {
        HeartRateSample(timestamp: now.addingTimeInterval(offset), bpm: bpm, trackerRecorded: tracked)
    }
    private func day(_ samples: [HeartRateSample], source: DataSource = .imported) -> DailySnapshot {
        var day = DailySnapshot.empty(on: now, source: source)
        day.heartRates = samples
        return day
    }
    func testOnlyRealRecentValidTrackerReadingsAppear() {
        let saved = day([sample(-120), sample(-30, tracked: false), sample(1), sample(-90_000), sample(-5, .nan), sample(-8, 240)])
        let result = TrackerChartData.points(days: [saved, day([sample(-2, 90)], source: .example)], live: nil, now: now)
        XCTAssertEqual(result.map(\.bpm), [80])
    }
    func testLatestReadingPerMinuteWinsWithoutInventingPoints() {
        let result = TrackerChartData.points(days: [day([sample(-25, 75), sample(-50, 60), sample(-80, 70)])], live: sample(-1, 99), now: now)
        XCTAssertEqual(result.map(\.bpm), [70, 99])
        XCTAssertEqual(result.last?.timestamp, now.addingTimeInterval(-1))
    }
    func testMissingIntervalsBecomeSeparateChartLines() {
        let result = TrackerChartData.points(days: [day([sample(-100, 90), sample(-600), sample(-540, 85)])], live: sample(-1, 95), now: now)
        XCTAssertEqual(result.map(\.segment), [0, 0, 1, 1])
        XCTAssertEqual(result.map(\.bpm), [80, 85, 90, 95])
    }
    func testEmptyAndExpiredSeriesStayEmpty() {
        XCTAssertTrue(TrackerChartData.points(days: [], live: nil, now: now).isEmpty)
        XCTAssertTrue(TrackerChartData.points(days: [day([sample(-86_401)])], live: nil, now: now).isEmpty)
    }
}
