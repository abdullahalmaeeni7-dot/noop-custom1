import Foundation
import XCTest
@testable import WHOOPCore

final class TrackerActivityDetectionTests: XCTestCase {
    let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func feed(_ detector: inout TrackerActivityDetector, from first: Int, through last: Int, bpm: Double) {
        for second in stride(from: first, through: last, by: 5) {
            detector.receive(HeartRateSample(timestamp: epoch.addingTimeInterval(Double(second)), bpm: bpm),
                             resting: 60, maximum: 180)
        }
    }

    func testOnsetRequiresFiveMinutesAndEndsOnLowerThreshold() throws {
        var detector = TrackerActivityDetector()
        feed(&detector, from: 0, through: 295, bpm: 125)
        XCTAssertNil(detector.activity)
        feed(&detector, from: 300, through: 300, bpm: 125)
        let first = try XCTUnwrap(detector.activity)
        XCTAssertEqual(first.start, epoch)
        XCTAssertEqual(first.durationMinutes, 5)
        XCTAssertEqual(first.automaticallyDetected, true)
        XCTAssertNil(first.strain)
        feed(&detector, from: 305, through: 360, bpm: 110)
        XCTAssertEqual(first.id, detector.activity?.id)
        XCTAssertEqual(detector.activity?.durationMinutes, 6)
        feed(&detector, from: 365, through: 365, bpm: 90)
        XCTAssertNil(detector.activity)
    }

    func testInterruptsAndSparseSamplesCannotQualify() {
        var detector = TrackerActivityDetector()
        feed(&detector, from: 0, through: 245, bpm: 125)
        detector.interrupt()
        feed(&detector, from: 250, through: 300, bpm: 125)
        XCTAssertNil(detector.activity)
        feed(&detector, from: 900, through: 1150, bpm: 125)
        XCTAssertNil(detector.activity)
        feed(&detector, from: 1155, through: 1200, bpm: 125)
        XCTAssertNotNil(detector.activity)
        detector.expire(at: epoch.addingTimeInterval(1216))
        XCTAssertNil(detector.activity)
        // A long quiet night cannot imply an activity or a sleep record.
        feed(&detector, from: 1220, through: 30_000, bpm: 54)
        XCTAssertNil(detector.activity)
    }

    func testDeletedEditedAndAuthoritativeActivitiesWinOnRetry() throws {
        var detector = TrackerActivityDetector()
        feed(&detector, from: 0, through: 360, bpm: 130)
        let auto = try XCTUnwrap(detector.activity)
        let insert = TrackerActivityCheckpoint(record: auto, mayInsert: true)
        let update = TrackerActivityCheckpoint(record: auto, mayInsert: false)
        var records = [ActivityRecord]()
        records.mergeTrackerActivity(insert)
        records.mergeTrackerActivity(insert)
        XCTAssertEqual(records, [auto])
        records.removeAll()
        records.mergeTrackerActivity(update)
        XCTAssertTrue(records.isEmpty)

        var edited = auto
        edited.automaticallyDetected = nil
        edited.name = "Walk"
        records = [edited]
        records.mergeTrackerActivity(update)
        XCTAssertEqual(records, [edited])

        let imported = ActivityRecord(start: epoch.addingTimeInterval(90), durationMinutes: 40, name: "Running", strain: 10)
        records = [auto]
        records.mergeSavedActivity(imported)
        records.mergeTrackerActivity(insert)
        XCTAssertEqual(records, [imported])
    }

    func testWearInterruptionKeepsUnsavedSamplesButStopsIntegration() throws {
        var accumulator = DailyTrackerAccumulator()
        for second in 0..<50 {
            try accumulator.append(.init(timestamp: epoch.addingTimeInterval(Double(second)), bpm: 130), resting: 55, maximum: 190)
        }
        let before = try XCTUnwrap(accumulator.pending.first?.recording)
        XCTAssertGreaterThan(before.processedSampleCount, 0)
        accumulator.interruptStream()
        try accumulator.append(.init(timestamp: epoch.addingTimeInterval(50), bpm: 125), resting: 55, maximum: 190)
        let after = try XCTUnwrap(accumulator.pending.first?.recording)
        XCTAssertEqual(after.sampleCount, before.sampleCount + 1)
        XCTAssertEqual(after.processedSampleCount, before.processedSampleCount)
        XCTAssertEqual(after.observedSeconds, before.observedSeconds)
    }
}
