import XCTest
@testable import WHOOPCore

final class TrackerConnectionEvidenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_392_000)
    private func evidence(connected: Bool = true, connecting: Bool = false, bpm: Double? = 98, age: Double? = 0) -> TrackerConnectionEvidence {
        TrackerConnectionEvidence(connected: connected, connecting: connecting, heartRate: bpm,
                                  receivedAt: age.map { now.addingTimeInterval(-$0) }, now: now)
    }
    func testLinkAloneDoesNotVerifyStream() {
        XCTAssertEqual(evidence(bpm: nil, age: nil).state, .waiting)
        XCTAssertNil(evidence(bpm: nil).liveHeartRate)
        XCTAssertEqual(evidence(connected: false, connecting: true).state, .connecting)
        XCTAssertEqual(evidence(connected: false).state, .disconnected)
        XCTAssertNil(evidence(connected: false).liveHeartRate)
    }
    func testFreshnessExpiresWithoutANewBluetoothEvent() {
        XCTAssertEqual(evidence(age: 10).liveHeartRate, 98)
        XCTAssertEqual(evidence(age: 10.001).state, .stale)
        XCTAssertNil(evidence(age: 10.001).liveHeartRate)
        XCTAssertEqual(evidence(age: -1).state, .stale)
        XCTAssertEqual(evidence(age: 0).state, .receiving)
    }
    func testInvalidReadingsNeverVerifyConnection() {
        for bpm in [Double.nan, .infinity, -1, 0, 24, 231] {
            XCTAssertEqual(evidence(bpm: bpm).state, .waiting)
            XCTAssertNil(evidence(bpm: bpm).liveHeartRate)
        }
        XCTAssertNil(evidence(age: nil).liveHeartRate)
    }
}
