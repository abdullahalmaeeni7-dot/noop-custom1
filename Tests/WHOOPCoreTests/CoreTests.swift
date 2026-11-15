import XCTest
@testable import WHOOPCore
import ZIPFoundation

final class WhoopZIPImportTests: XCTestCase {
    private let cycles = "Cycle start time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Day Strain,Energy burned (cal),Sleep performance %,Asleep duration (min),Sleep need (min),Respiratory rate (rpm)\r\n2026-03-10 00:30:00,UTC+04:00,76,55,83.4,12.6,2345,88,416,473,15.2\r\n"
    private let sleep = "Cycle start time,Cycle timezone,Nap,Sleep performance %,Asleep duration (min),Sleep need (min),Respiratory rate (rpm)\n2026-03-10 00:30:00,UTC+04:00,false,88,416,473,15.2\n2026-03-10 00:30:00,UTC+04:00,true,,22,,\n"
    private let workout = "Cycle start time,Workout start time,Workout end time,Cycle timezone,Activity name,Activity Strain\n2026-03-10 00:30:00,2026-03-10 17:00:00,2026-03-10 17:45:00,UTC+04:00,\"Strength, circuit\",8.7\n"
    private func zip(_ files: [(String, String)], compression: CompressionMethod = .deflate) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        for (name, text) in files {
            let data = Data(text.utf8)
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: compression) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return try XCTUnwrap(archive.data)
    }
    func testOfficialZIPImportsCyclesSleepAndWorkoutsWithoutInventedHeartRates() throws {
        let result = try MeasurementExport.readImport(zip([("export/physiological_cycles.csv", cycles), ("export/sleeps.csv", sleep), ("export/workouts.csv", workout)]), filename: "WHOOP-export.zip")
        let day = try XCTUnwrap(result.days.first)
        XCTAssertEqual(result.days.count, 1)
        XCTAssertEqual(day.date, ISO8601DateFormatter().date(from: "2026-03-09T00:00:00Z"))
        XCTAssertEqual(day.recovery, 76); XCTAssertEqual(day.strain, 12.6)
        XCTAssertEqual(day.hrv, 83.4); XCTAssertEqual(day.restingHeartRate, 55)
        XCTAssertEqual(day.energyKcal, 2345); XCTAssertEqual(day.respiratoryRate, 15.2)
        XCTAssertEqual(day.sleepMinutes, 416); XCTAssertEqual(day.sleepNeededMinutes, 473)
        XCTAssertEqual(day.sleepPerformance, 88); XCTAssertTrue(day.heartRates.isEmpty)
        XCTAssertEqual(day.source, .imported)
        let activity = try XCTUnwrap(result.activities.first)
        XCTAssertEqual(activity.name, "Strength, circuit"); XCTAssertEqual(activity.strain, 8.7)
        XCTAssertEqual(activity.durationMinutes, 45); XCTAssertEqual(activity.strainIsEstimate, false)
        XCTAssertEqual(activity.start, ISO8601DateFormatter().date(from: "2026-03-10T13:00:00Z"))
    }
    func testStoredZIPAndDirectOfficialCSVMatch() throws {
        let direct = try MeasurementExport.readImport(Data(cycles.utf8), filename: "cycles.csv")
        let archive = try MeasurementExport.readImport(zip([("physiological_cycles.csv", cycles)], compression: .none), filename: "export.ZIP")
        XCTAssertEqual(direct.days, archive.days)
        XCTAssertEqual(try ImportReader.read(Data(cycles.utf8), filename: "cycles.csv"), direct.days)
    }
    func testRepeatedWorkoutImportHasStableIdentityEvenWhenScoreChanges() throws {
        let first = try MeasurementExport.readImport(zip([("workouts.csv", workout)]), filename: "export.zip")
        let next = try MeasurementExport.readImport(zip([("workouts.csv", workout.replacingOccurrences(of: ",8.7", with: ",9.1"))]), filename: "export.zip")
        XCTAssertTrue(first.days.isEmpty)
        XCTAssertEqual(first.activities.first?.id, next.activities.first?.id)
        XCTAssertEqual(next.activities.first?.strain, 9.1)
    }
    func testSleepOnlyArchiveDoesNotAddNapToPrimarySleepOrInventRecovery() throws {
        let result = try MeasurementExport.readImport(zip([("sleeps.csv", sleep)]), filename: "export.zip")
        XCTAssertEqual(result.days.first?.sleepMinutes, 416)
        XCTAssertNil(result.days.first?.recovery); XCTAssertNil(result.days.first?.strain)
    }
    func testJournalIsReportedAndDoesNotOverwritePersonalNotes() throws {
        let result = try MeasurementExport.readImport(zip([("physiological_cycles.csv", cycles), ("journal_entries.csv", "Question text,Answered yes/no\nCaffeine,true\n")]), filename: "export.zip")
        XCTAssertEqual(result.notices, ["Journal answers are not part of this measurement import."])
    }
    func testMissingNumbersStayMissingAndPercentSuffixIsAccepted() throws {
        let csv = "Cycle start time,Cycle timezone,Recovery score %,Day Strain\n2026-03-10 10:00:00,UTC,76%,\n"
        let result = try MeasurementExport.readImport(Data(csv.utf8), filename: "cycles.csv")
        XCTAssertEqual(result.days.first?.recovery, 76); XCTAssertNil(result.days.first?.strain)
        XCTAssertNil(result.days.first?.hrv); XCTAssertTrue(result.days.first?.heartRates.isEmpty == true)
    }
    func testExplicitISOTimeAndIANATimezoneAreSupported() throws {
        let iso = cycles.replacingOccurrences(of: "2026-03-10 00:30:00", with: "2026-03-09T20:30:00Z")
        XCTAssertEqual(try ImportReader.read(Data(iso.utf8), filename: "cycles.csv"), try ImportReader.read(Data(cycles.utf8), filename: "cycles.csv"))
        let ny = cycles.replacingOccurrences(of: "UTC+04:00", with: "America/New_York")
        XCTAssertEqual(try ImportReader.read(Data(ny.utf8), filename: "cycles.csv").first?.date, ISO8601DateFormatter().date(from: "2026-03-10T00:00:00Z"))
    }
    func testInvalidMetricTimezoneAndTruncatedCSVAreRejected() throws {
        for csv in [cycles.replacingOccurrences(of: ",76,", with: ",101,"), cycles.replacingOccurrences(of: "83.4", with: "NaN"), cycles.replacingOccurrences(of: "UTC+04:00", with: "UTC+99:00"), cycles + "2026-03-11\n"] {
            XCTAssertThrowsError(try MeasurementExport.readImport(Data(csv.utf8), filename: "cycles.csv"))
        }
    }
    func testDuplicateKnownFilesAndUnsafePathsAreRejected() throws {
        for files in [[("a/physiological_cycles.csv", cycles), ("b/physiological_cycles.csv", cycles)], [("../physiological_cycles.csv", cycles)]] {
            XCTAssertThrowsError(try MeasurementExport.readImport(zip(files), filename: "export.zip"))
        }
    }
    func testCorruptedCSVChecksumIsRejectedBeforeParsing() throws {
        var data = try zip([("physiological_cycles.csv", cycles)], compression: .none)
        let region = try XCTUnwrap(data.range(of: Data(cycles.utf8)))
        data[region.lowerBound + 2] ^= 1
        XCTAssertThrowsError(try MeasurementExport.readImport(data, filename: "export.zip"))
    }
    func testUnknownAndBrokenArchivesGiveAnImportError() throws {
        for data in [Data("not a zip".utf8), try zip([("readme.txt", "not WHOOP measurements")])] {
            XCTAssertThrowsError(try MeasurementExport.readImport(data, filename: "export.zip")) { XCTAssertTrue($0 is WHOOPCore.ImportError) }
        }
    }
    func testUnpackedSizeLimitStopsHighlyCompressedInput() throws {
        let data = try zip([("physiological_cycles.csv", String(repeating: "x", count: ImportReader.maximumBytes + 1))])
        XCTAssertLessThan(data.count, ImportReader.maximumBytes)
        XCTAssertThrowsError(try MeasurementExport.readImport(data, filename: "export.zip"))
    }
    func testConflictingCyclesAndInvalidWorkoutDurationAreRejected() throws {
        let extra = "2026-03-10 01:30:00,UTC+04:00,75,55,83.4,12.6,2345,88,416,473,15.2\n"
        XCTAssertThrowsError(try MeasurementExport.readImport(Data((cycles + extra).utf8), filename: "cycles.csv"))
        let bad = workout.replacingOccurrences(of: "2026-03-10 17:45:00", with: "2026-03-10 16:00:00")
        XCTAssertThrowsError(try MeasurementExport.readImport(Data(bad.utf8), filename: "workouts.csv"))
    }
}

final class LaunchDayDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_398_400)

    func testFirstLaunchStartsOnTodayWithoutScoresOrExampleDays() {
        let initial = LaunchDayData(now: now)
        XCTAssertTrue(initial.days.isEmpty)
        XCTAssertEqual(initial.selectedDate, DayCalendar.start(of: now))
    }

    func testExistingExampleInstallOpensTodayWithoutAdoptingItsScores() {
        let examples = ExampleData.days()
        XCTAssertFalse(examples.isEmpty)
        let initial = LaunchDayData(savedDays: examples, selectedDate: examples[0].date, now: now)
        XCTAssertTrue(initial.days.isEmpty)
        XCTAssertEqual(initial.selectedDate, DayCalendar.start(of: now))
    }

    func testMigrationPreservesEveryRealMeasurementAndSelectedDay() {
        var recorded = DailySnapshot.empty(on: now)
        recorded.recovery = 74
        recorded.strain = 9.4
        recorded.heartRates = [HeartRateSample(timestamp: now, bpm: 71)]
        var earlier = DailySnapshot.empty(on: now.addingTimeInterval(-86_400))
        earlier.sleepMinutes = 431
        let initial = LaunchDayData(savedDays: ExampleData.days() + [recorded, earlier], selectedDate: earlier.date, now: now)
        XCTAssertEqual(initial.days, [earlier, recorded])
        XCTAssertEqual(initial.selectedDate, earlier.date)
    }
}

final class BluetoothTests: XCTestCase {
    func testEightBitAndOtherFlags() {
        XCTAssertEqual(HeartRateMeasurement.decode(Data([0, 72])), 72)
        XCTAssertEqual(HeartRateMeasurement.decode(Data([0x16, 91, 0x34, 0x12])), 91)
    }
    func testSixteenBitIsLittleEndian() {
        XCTAssertEqual(HeartRateMeasurement.decode(Data([1, 0x2c, 1])), 300)
        XCTAssertEqual(HeartRateMeasurement.decode(Data([1, 1, 0])), 1)
    }
    func testTruncatedAndUnsupportedRates() {
        for bytes: [UInt8] in [[], [0], [1, 72], [0, 0], [1, 0x2d, 1], [1, 0, 2]] {
            XCTAssertNil(HeartRateMeasurement.decode(Data(bytes)))
        }
    }
}

final class ImportTests: XCTestCase {
    func read(_ text: String, _ filename: String = "data.csv") throws -> [DailySnapshot] {
        try ImportReader.read(Data(text.utf8), filename: filename)
    }
    func testCSVUTCGroupingAndNoInventedScores() throws {
        let days = try read("timestamp,heart_rate\n2026-11-08T00:30:00+04:00,80\n2026-11-08T00:00:00Z,72\n")
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.map { $0.heartRates.count }, [1, 1])
        XCTAssertTrue(days.allSatisfy { $0.recovery == nil && $0.sleepPerformance == nil && $0.strain == nil })
        XCTAssertTrue(days.allSatisfy { $0.source == .imported })
        XCTAssertEqual(days[1].date.timeIntervalSince(days[0].date), 86400)
    }
    func testCSVQuotedFieldsBOMAndCRLF() throws {
        let days = try read("\u{feff}timestamp,heart_rate,note\r\n\"2026-11-08T08:00:00.125Z\",\"75\",\"Morning, \"\"easy\"\"\"\r\n")
        XCTAssertEqual(days[0].heartRates[0].bpm, 75)
        XCTAssertEqual(days[0].heartRates[0].timestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.125, accuracy: 0.00001)
    }
    func testDuplicateIdenticalSamplesAreCoalescedAndSorted() throws {
        let days = try read("timestamp,heart_rate\n2026-11-08T09:00:00Z,90\n2026-11-08T08:00:00Z,70\n2026-11-08T08:00:00Z,70\n")
        XCTAssertEqual(days[0].heartRates.map(\.bpm), [70, 90])
    }
    func testConflictingDuplicateRejectsWholeImport() {
        XCTAssertThrowsError(try read("timestamp,heart_rate\n2026-11-08T08:00:00Z,70\n2026-11-08T08:00:00Z,80"))
    }
    func testInvalidRateAndMissingTimezone() {
        for value in ["NaN", "inf", "0", "-2", "301", "hello"] {
            XCTAssertThrowsError(try read("timestamp,heart_rate\n2026-11-08T08:00:00Z,\(value)"))
        }
        XCTAssertThrowsError(try read("timestamp,heart_rate\n2026-11-08T08:00:00,70"))
        XCTAssertThrowsError(try read("timestamp,heart_rate\n2026-11-08,70"))
    }
    func testCSVStructuralErrors() {
        for text in [
            "timestamp,heart_rate\n\"2026-11-08T08:00:00Z,70",
            "timestamp,heart_rate\n\"2026-11-08T08:00:00Z\"bad,70",
            "timestamp,heart_rate\n2026-11-08T08:00:00Z,70,extra",
            "timestamp,timestamp,heart_rate\n2026-11-08T08:00:00Z,ignored,70",
            "date,bpm\n2026-11-08T08:00:00Z,70"
        ] { XCTAssertThrowsError(try read(text)) }
    }
    func testEmptyAndUnsupportedFiles() {
        XCTAssertThrowsError(try read("timestamp,heart_rate\n"))
        XCTAssertThrowsError(try read(""))
        XCTAssertThrowsError(try read("hello", "data.txt"))
        XCTAssertThrowsError(try ImportReader.read(Data([0xff]), filename: "data.csv"))
    }
    func testByteLimitBeforeParsing() {
        XCTAssertThrowsError(try ImportReader.read(Data(repeating: 0, count: ImportReader.maximumBytes + 1), filename: "data.json")) { error in
            XCTAssertEqual(error as? ImportError, .tooLarge)
        }
    }
    func testJSONArchiveMinimalPreservesExplicitExampleProvenance() throws {
        let days = try read("{\"days\":[{\"date\":\"2026-11-08\",\"recovery\":78,\"source\":\"example\"}]}", "day.json")
        XCTAssertEqual(days[0].recovery, 78)
        XCTAssertEqual(days[0].source, .example)
        XCTAssertNil(days[0].sleepPerformance)
        XCTAssertEqual(days[0].heartRates, [])
    }
    func testJSONArchiveMissingSourceIsImported() throws {
        let days = try read("{\"days\":[{\"date\":\"2026-11-08\",\"recovery\":78}]}", "day.json")
        XCTAssertEqual(days[0].source, .imported)
    }
    func testJSONRejectsInvalidMetricAndWrongSampleDay() {
        XCTAssertThrowsError(try read("[{\"date\":\"2026-11-08\",\"recovery\":101}]", "day.json"))
        XCTAssertThrowsError(try read("[{\"date\":\"2026-11-08\",\"strain\":22}]", "day.json"))
        XCTAssertThrowsError(try read("[{\"date\":\"2026-11-08\",\"heartRates\":[{\"timestamp\":\"2026-11-09T00:00:00Z\",\"bpm\":70}]}]", "day.json"))
        XCTAssertThrowsError(try read("[{\"date\":\"2026-11-08\"},{\"date\":\"2026-11-08\"}]", "day.json"))
    }
    func testJSONDateAndModelRoundTrip() throws {
        let fixed = Date(timeIntervalSince1970: 1_793_491_200)
        let input = ExampleData.days(endingOn: fixed)
        let data = try ImportReader.jsonEncoder().encode(DayArchive(days: input))
        let decoded = try ImportReader.read(data, filename: "export.JSON")
        XCTAssertEqual(decoded.count, 7)
        XCTAssertEqual(decoded[6].heartRates, input[6].heartRates)
        XCTAssertEqual(decoded[6].strain, input[6].strain)
        XCTAssertTrue(decoded.allSatisfy { $0.source == .example })
    }
    func testJSONExportPreservesDistinctMillisecondSamples() throws {
        let input = try read("timestamp,heart_rate\n2026-11-08T08:00:00.125Z,70\n2026-11-08T08:00:00.875Z,80")
        let data = try ImportReader.jsonEncoder().encode(DayArchive(days: input))
        let output = try ImportReader.read(data, filename: "export.json")
        XCTAssertEqual(output, input)
    }
    func testPairedDateCodecsPreserveAppState() throws {
        struct SavedState: Codable, Equatable {
            let journal: JournalEntry
            let activity: ActivityRecord
        }
        let time = Date(timeIntervalSince1970: 1_793_491_200.125)
        let state = SavedState(journal: .init(date: time, caffeine: true, note: "Morning coffee"),
                               activity: .init(start: time, durationMinutes: 30, name: "Walk"))
        let data = try ImportReader.jsonEncoder().encode(state)
        XCTAssertEqual(try ImportReader.jsonDecoder().decode(SavedState.self, from: data), state)
    }
    func testExampleWeekIsDeterministicAndLabelled() {
        let date = Date(timeIntervalSince1970: 1_793_491_200)
        let values = ExampleData.days(endingOn: date)
        XCTAssertEqual(values, ExampleData.days(endingOn: date))
        XCTAssertEqual(values.count, 7)
        XCTAssertEqual(values.map(\.date), values.map(\.date).sorted())
        XCTAssertTrue(values.allSatisfy { $0.source == .example })
    }
}

final class StrainTests: XCTestCase {
    func sample(_ seconds: Double, _ bpm: Double) -> HeartRateSample {
        .init(timestamp: Date(timeIntervalSince1970: seconds), bpm: bpm)
    }
    func testRecoveredTableAndExactThresholdBoundaries() throws {
        let rows = try StrainCalculator.lookupEntries()
        XCTAssertEqual(rows.count, 211)
        XCTAssertEqual(rows.last?.lowerThreshold, 0.70195765)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 0), 0)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 0.0000007099), 0)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 0.00000071), 0.1)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 0.00364918), 10)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 0.02997906), 20)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 0.70195765), 21)
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: 500), 21)
        for (index, row) in rows.enumerated() {
            XCTAssertEqual(row.score, Double(index) / 10, accuracy: 1e-12)
            XCTAssertEqual(try StrainCalculator.scaledScore(raw: row.lowerThreshold), row.score)
            if index > 0 { XCTAssertGreaterThan(row.lowerThreshold, rows[index - 1].lowerThreshold) }
        }
    }
    func testLiteralNegativeLookupFallbackIsNotSilentlyCorrected() throws {
        XCTAssertEqual(try StrainCalculator.scaledScore(raw: -1), 21)
        XCTAssertThrowsError(try StrainCalculator.scaledScore(raw: .nan))
        XCTAssertThrowsError(try StrainCalculator.scaledScore(raw: .infinity))
    }
    func testReserveCutoffAndUpperClipping() throws {
        XCTAssertEqual(try StrainCalculator.reserve(heartRate: 95, restingHeartRate: 50, maximumHeartRate: 197), 0)
        XCTAssertGreaterThan(try StrainCalculator.reserve(heartRate: 95.01, restingHeartRate: 50, maximumHeartRate: 197), 0)
        XCTAssertEqual(try StrainCalculator.reserve(heartRate: 20, restingHeartRate: 50, maximumHeartRate: 197), 0)
        XCTAssertEqual(try StrainCalculator.reserve(heartRate: 220, restingHeartRate: 50, maximumHeartRate: 197), 1)
        XCTAssertThrowsError(try StrainCalculator.reserve(heartRate: 50, restingHeartRate: 80, maximumHeartRate: 77))
    }
    func testLogisticKnownMidpointAndZeroReserve() throws {
        XCTAssertEqual(try StrainCalculator.weightedContribution(reserve: 1, durationSeconds: 3), 24, accuracy: 1e-12)
        XCTAssertEqual(try StrainCalculator.weightedContribution(reserve: 0, durationSeconds: 3), 0)
    }
    func testDurationCapAndTerminalDifference() throws {
        let input = [sample(100, 160), sample(101, 160), sample(111, 160)]
        XCTAssertEqual(try StrainCalculator.durationScales(for: input), [1, 3, 3])
        XCTAssertEqual(try StrainCalculator.durationScales(for: input, terminalTimestampMilliseconds: 112000), [1, 3, 1])
    }
    func testLiteralSingletonDurationQuirk() throws {
        let input = [sample(100, 160)]
        XCTAssertEqual(try StrainCalculator.durationScales(for: input, terminalTimestampMilliseconds: -1), [1])
        XCTAssertEqual(try StrainCalculator.durationScales(for: input), [-100])
        XCTAssertEqual(try StrainCalculator.rawContribution(smoothedSamples: input, restingHeartRate: 50, maximumHeartRate: 200), 0)
    }
    func testRawContributionIsZeroAtRestAndPositiveForWork() throws {
        let rest = [sample(100, 55), sample(101, 55)]
        let work = [sample(100, 180), sample(101, 180)]
        XCTAssertEqual(try StrainCalculator.rawContribution(smoothedSamples: rest, restingHeartRate: 50, maximumHeartRate: 200), 0)
        let raw = try StrainCalculator.rawContribution(smoothedSamples: work, restingHeartRate: 50, maximumHeartRate: 200)
        XCTAssertGreaterThan(raw, 0)
        XCTAssertLessThanOrEqual(raw, 1)
        XCTAssertEqual(try StrainCalculator.rawContribution(smoothedSamples: [], restingHeartRate: 50, maximumHeartRate: 200), 0)
    }
    func testUnorderedDuplicateAndNonfiniteInputReject() {
        XCTAssertThrowsError(try StrainCalculator.durationScales(for: [sample(2, 100), sample(1, 100)]))
        XCTAssertThrowsError(try StrainCalculator.durationScales(for: [sample(1, 100), sample(1, 100)]))
        XCTAssertThrowsError(try StrainCalculator.durationScales(for: [sample(1, .nan)]))
    }
    func testQuantileInterpolatesAndHandlesEmpty() throws {
        XCTAssertEqual(try StrainCalculator.quantile([4, 1, 3, 2]), 1.75)
        XCTAssertEqual(try StrainCalculator.quantile([]), 0)
        XCTAssertEqual(try StrainCalculator.quantile([4]), 4)
        XCTAssertEqual(try StrainCalculator.quantile([4, 2], fraction: 1), 4)
    }
}

final class CameraOverlayDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_182_400)
    private func day() -> DailySnapshot {
        var value = DailySnapshot.empty(on: now)
        value.strain = 15.8; value.recovery = 38; value.sleepMinutes = 224
        value.sleepPerformance = 33; value.energyKcal = 2_886
        return value
    }
    func testOverviewUsesDayStrainRecoveryAndActualSleepDuration() {
        let result = CameraOverlayData.metrics(mode: .overview, day: day(), liveHeartRate: nil, sampleDate: nil, now: now)
        XCTAssertEqual(result.map(\.value), ["15.8", "38%", "3:44"])
        XCTAssertEqual(result.map(\.label), ["DAY STRAIN", "RECOVERY", "HOURS\nOF SLEEP"])
        XCTAssertEqual(result[0].fraction ?? 0, 15.8 / 21, accuracy: 0.00001)
        XCTAssertEqual(result[1].tone, .yellow)
        XCTAssertNil(result[2].fraction)
    }
    func testDetailModesUseTheSameMetricAsOverview() {
        let overview = CameraOverlayData.metrics(mode: .overview, day: day(), liveHeartRate: nil, sampleDate: nil, now: now)
        for (index, mode) in [CameraOverlayMode.strain, .recovery, .sleep].enumerated() {
            XCTAssertEqual(CameraOverlayData.metrics(mode: mode, day: day(), liveHeartRate: nil, sampleDate: nil, now: now), [overview[index]])
        }
    }
    func testLiveHRRequiresFreshReceivedTimestampIncludingTenSecondBoundary() {
        for age in [-1.0, 10.001, 60] {
            let value = CameraOverlayData.metrics(mode: .live, day: day(), liveHeartRate: 98, sampleDate: now.addingTimeInterval(-age), now: now)
            XCTAssertEqual(value[0].value, "Connect"); XCTAssertFalse(value[0].available)
        }
        for age in [0.0, 9, 10] {
            let value = CameraOverlayData.metrics(mode: .live, day: day(), liveHeartRate: 98, sampleDate: now.addingTimeInterval(-age), now: now)
            XCTAssertEqual(value[0].value, "98"); XCTAssertTrue(value[0].available)
        }
    }
    func testMissingOrInvalidHRIsNotReplacedByHistoricalOrExampleSamples() {
        var example = day(); example.source = .example
        example.heartRates = [.init(timestamp: now, bpm: 150)]
        for rate: Double? in [nil, 0, 301, .nan, .infinity] {
            let value = CameraOverlayData.metrics(mode: .live, day: example, liveHeartRate: rate, sampleDate: now, now: now)
            XCTAssertEqual(value[0].value, "Connect")
        }
        XCTAssertEqual(CameraOverlayData.metrics(mode: .live, day: example, liveHeartRate: 98, sampleDate: nil, now: now)[0].value, "Connect")
    }
    func testRecoveryThresholdsAndZeroScores() {
        for (score, tone) in [(0, CameraOverlayTone.red), (33, .red), (34, .yellow), (66, .yellow), (67, .green), (100, .green)] {
            var value = day(); value.recovery = score
            let metric = CameraOverlayData.metrics(mode: .recovery, day: value, liveHeartRate: nil, sampleDate: nil)[0]
            XCTAssertEqual(metric.tone, tone); XCTAssertEqual(metric.value, "\(score)%"); XCTAssertTrue(metric.available)
        }
    }
    func testUnavailableAndOutOfRangeScoresStayUnavailable() {
        var value = DailySnapshot.empty(on: now)
        let empty = CameraOverlayData.metrics(mode: .overview, day: value, liveHeartRate: nil, sampleDate: nil)
        XCTAssertEqual(empty.map(\.value), ["Sync", "Sync", "Sync"])
        XCTAssertTrue(empty.allSatisfy { !$0.available && $0.fraction == nil })
        value.strain = .nan; value.recovery = 101; value.sleepMinutes = 1_441
        XCTAssertEqual(CameraOverlayData.metrics(mode: .overview, day: value, liveHeartRate: nil, sampleDate: nil).map(\.value), ["Sync", "Sync", "Sync"])
    }
    func testLiveEnergyIsLabeledDayCaloriesAndTimerIsBounded() {
        let value = CameraOverlayData.metrics(mode: .live, day: day(), liveHeartRate: nil, sampleDate: nil, elapsedSeconds: 125)
        XCTAssertEqual(value[2].value, "2886"); XCTAssertEqual(value[2].label, "DAY CALORIES")
        XCTAssertEqual(value[3].value, "2:05")
        XCTAssertEqual(CameraOverlayData.metrics(mode: .live, day: day(), liveHeartRate: nil, sampleDate: nil, elapsedSeconds: -1)[3].value, "0:00")
        XCTAssertEqual(CameraOverlayData.metrics(mode: .live, day: day(), liveHeartRate: nil, sampleDate: nil, elapsedSeconds: Int.max)[3].value, "360:00")
    }
}
