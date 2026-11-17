import XCTest
@testable import WHOOPCore

final class DailyTrackerRecordingTests: XCTestCase {
    private let day = DayCalendar.start(of: Date(timeIntervalSince1970: 1_800_000_000))
    private func sample(_ seconds: Double, bpm: Double = 175) -> HeartRateSample {
        HeartRateSample(timestamp: day.addingTimeInterval(seconds), bpm: bpm)
    }
    private func add(_ range: Range<Int>, to value: inout DailyTrackerAccumulator) throws {
        for i in range { try value.append(sample(Double(i)), resting: 55, maximum: 190) }
    }
    func testAutomaticBatchesPreserveEngineAndOnlyOneChartPointPerMinute() throws {
        var stream = DailyTrackerAccumulator(), single = DailyTrackerAccumulator()
        var stored = DailySnapshot.empty(on: day)
        for i in 0..<180 {
            try stream.append(sample(Double(i)), resting: 55, maximum: 190)
            try single.append(sample(Double(i)), resting: 55, maximum: 190)
            if i % 15 == 14 {
                stored = try stored.applyingTrackerBatch(XCTUnwrap(stream.pending.first))
                stream.acknowledgeSaved()
            }
        }
        let record = try XCTUnwrap(stored.trackerRecording)
        XCTAssertEqual(record.sampleCount, 180)
        XCTAssertEqual(record.processedSampleCount, 149)
        XCTAssertEqual(record.observedSeconds, 149, accuracy: 0.001)
        XCTAssertEqual(record.rawStrain, try XCTUnwrap(single.pending.first).recording.rawStrain, accuracy: 1e-12)
        XCTAssertEqual(stored.heartRates.map(\.timestamp), [59,119,179].map { day.addingTimeInterval(Double($0)) })
        XCTAssertNil(stored.strain)
        XCTAssertNil(stored.recovery)
        XCTAssertTrue(stored.strainIsLocalEstimate)
        XCTAssertGreaterThan(try XCTUnwrap(stored.displayedStrain), 0)
    }
    func testWarmupAndDisconnectDoNotInventCoverageOrRecovery() throws {
        var stream = DailyTrackerAccumulator()
        try add(0..<31, to: &stream)
        XCTAssertNil(stream.pending.first?.recording.strainEstimate)
        try add(31..<60, to: &stream)
        try add(3600..<3660, to: &stream)
        let record = try XCTUnwrap(stream.pending.first).recording
        XCTAssertEqual(record.sampleCount, 120)
        XCTAssertEqual(record.processedSampleCount, 58)
        XCTAssertEqual(record.observedSeconds, 58)
        XCTAssertLessThan(record.observedSeconds, record.lastSampleAt.timeIntervalSince(record.firstSampleAt))
    }
    func testUTCMidnightSplitsRecordingAndDoesNotCarryEngineAcrossDays() throws {
        var stream = DailyTrackerAccumulator()
        try add(86_360..<86_440, to: &stream)
        XCTAssertEqual(stream.pending.count, 2)
        for batch in stream.pending {
            try batch.recording.validated(on: batch.date)
            XCTAssertEqual(batch.recording.sampleCount, 40)
            XCTAssertEqual(batch.recording.observedSeconds, 9)
            XCTAssertTrue(batch.chartSamples.allSatisfy { DayCalendar.start(of: $0.timestamp) == batch.date })
        }
    }
    func testRestartAddsOnlyNewObservedIntervalsAndKeepsProviderScores() throws {
        var first = DailyTrackerAccumulator()
        try add(0..<60, to: &first)
        var stored = DailySnapshot.empty(on: day)
        stored.strain = 12.4; stored.recovery = 83; stored.hrv = 91
        stored.heartRates = [sample(0.5, bpm: 100)]
        stored = try stored.applyingTrackerBatch(XCTUnwrap(first.pending.first))
        var restarted = DailyTrackerAccumulator()
        try add(500..<560, to: &restarted)
        stored = try stored.applyingTrackerBatch(XCTUnwrap(restarted.pending.first))
        XCTAssertEqual(stored.trackerRecording?.sampleCount, 120)
        XCTAssertEqual(stored.trackerRecording?.observedSeconds, 58)
        XCTAssertEqual(stored.displayedStrain, 12.4)
        XCTAssertFalse(stored.strainIsLocalEstimate)
        XCTAssertEqual(stored.recovery, 83)
        XCTAssertEqual(stored.hrv, 91)
        XCTAssertTrue(stored.heartRates.contains(sample(0.5, bpm: 100)))
    }
    func testBackupAndJSONRoundtripPreserveSeparateLocalRecording() throws {
        var stream = DailyTrackerAccumulator(); try add(0..<70, to: &stream)
        let saved = try DailySnapshot.empty(on: day).applyingTrackerBatch(XCTUnwrap(stream.pending.first))
        let backup = LocalBackup(selectedDate: day, days: [saved], journal: [], activities: [])
        let restored = try LocalBackupCodec.decode(LocalBackupCodec.encode(backup))
        XCTAssertEqual(restored.days, [saved])
        let data = try ImportReader.jsonEncoder().encode(DayArchive(days: [saved]))
        let imported = try ImportReader.read(data, filename: "day.json")
        XCTAssertEqual(imported.first?.trackerRecording, saved.trackerRecording)
        let old = try ImportReader.jsonEncoder().encode(DailySnapshot.empty(on: day))
        XCTAssertNil(try ImportReader.jsonDecoder().decode(DailySnapshot.self, from: old).trackerRecording)
    }
    func testInvalidSamplesAndRecordingMetadataAreRejectedWithoutChangingAccumulator() throws {
        var stream = DailyTrackerAccumulator(); try add(0..<60, to: &stream)
        let before = try XCTUnwrap(stream.pending.first).recording
        for invalid in [sample(60, bpm: .nan), sample(59), sample(58), sample(60, bpm: 0)] {
            XCTAssertThrowsError(try stream.append(invalid, resting: 55, maximum: 190))
            XCTAssertEqual(stream.pending.first?.recording, before)
        }
        var corrupt = before; corrupt.observedSeconds = 86_401
        XCTAssertThrowsError(try corrupt.validated(on: day))
        corrupt = before; corrupt.processedSampleCount = corrupt.sampleCount + 1
        XCTAssertThrowsError(try corrupt.validated(on: day))
        corrupt = before; corrupt.firstSampleAt = day.addingTimeInterval(-1)
        XCTAssertThrowsError(try corrupt.validated(on: day))
        stream.reset(); XCTAssertTrue(stream.pending.isEmpty)
    }
    func testProfileChangesResetSmoothingAndLiveUsesExplicitLocalLabel() throws {
        var stream = DailyTrackerAccumulator(); try add(0..<60, to: &stream)
        for i in 60..<120 { try stream.append(sample(Double(i)), resting: 65, maximum: 200) }
        var saved = try DailySnapshot.empty(on: day).applyingTrackerBatch(XCTUnwrap(stream.pending.first))
        XCTAssertEqual(saved.trackerRecording?.observedSeconds, 58)
        let local = CameraOverlayData.metrics(mode: .strain, day: saved, liveHeartRate: nil, sampleDate: nil)
        XCTAssertEqual(local.first?.label, "LOCAL STRAIN EST.")
        XCTAssertEqual(local.first?.available, true)
        saved.strain = 9.8
        let official = CameraOverlayData.metrics(mode: .strain, day: saved, liveHeartRate: nil, sampleDate: nil)
        XCTAssertEqual(official.first?.label, "DAY STRAIN")
        XCTAssertEqual(official.first?.value, "9.8")
    }

}
