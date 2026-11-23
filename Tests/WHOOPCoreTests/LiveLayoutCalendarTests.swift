import XCTest
@testable import WHOOPCore

final class LiveLayoutCalendarTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testNovemberImportKeepsMeasurementDatesButLaunchesOnToday() {
        let old = date("2026-11-09T00:00:00Z"), now = date("2026-11-23T16:00:00Z")
        var day = DailySnapshot.empty(on: old); day.recovery = 38
        day.heartRates = [.init(timestamp: old.addingTimeInterval(1234), bpm: 98)]
        let launched = LaunchDayData(savedDays: [day], selectedDate: old, now: now)
        XCTAssertEqual(launched.selectedDate, date("2026-11-23T00:00:00Z"))
        XCTAssertEqual(launched.days, [day])
        XCTAssertEqual(DashboardDatePolicy.afterImport(now: now), launched.selectedDate)
    }
    func testMidnightFollowsTodayWithoutHijackingHistoricalBrowsing() {
        let prior = date("2026-11-30T00:00:00Z"), now = date("2026-12-01T00:01:00Z")
        XCTAssertEqual(DashboardDatePolicy.onRollover(selected: prior, previousToday: prior, now: now), date("2026-12-01T00:00:00Z"))
        let historical = date("2026-11-09T00:00:00Z")
        XCTAssertEqual(DashboardDatePolicy.onRollover(selected: historical, previousToday: prior, now: now), historical)
    }
    func testCalendarLeapYearAlignmentAndYearBoundary() {
        let leap = RecoveryCalendarMonth(containing: date("2024-02-15T14:00:00Z"))
        XCTAssertEqual(leap.cells.compactMap { $0 }.count, 29)
        XCTAssertEqual(leap.cells.prefix(3).compactMap { $0 }.count, 0)
        XCTAssertEqual(leap.cells[3], date("2024-02-01T00:00:00Z"))
        XCTAssertEqual(leap.shifted(by: -2).start, date("2023-12-01T00:00:00Z"))
        let sunday = RecoveryCalendarMonth(containing: leap.start, firstWeekday: 1)
        XCTAssertEqual(sunday.shifted(by: 1).firstWeekday, 1)
        XCTAssertEqual(leap.cells.count % 7, 0)
    }
    func testRecoveryThresholdsDoNotColorMissingRecordsGreen() {
        for (score, expected) in [(0, RecoveryBand.red), (33, .red), (34, .yellow), (66, .yellow), (67, .green), (100, .green)] {
            XCTAssertEqual(RecoveryBand(score: score), expected)
        }
        for score in [nil, -1, 101] { XCTAssertEqual(RecoveryBand(score: score), .unavailable) }
    }
    func testRecoverySizeAndPositionAreConsistentAcrossPreviewAndExport() {
        var layout = LiveOverlayLayout()
        layout.setPlacement(.init(scale: 0.6, offsetX: 0.25, offsetY: -0.15), widget: .recovery, mode: .recovery, width: 360, height: 640)
        let preview = layout.frame(.recovery, mode: .recovery, width: 360, height: 640)
        let exported = layout.frame(.recovery, mode: .recovery, width: 1080, height: 1920)
        XCTAssertEqual(exported.x, preview.x * 3, accuracy: 0.001)
        XCTAssertEqual(exported.y, preview.y * 3, accuracy: 0.001)
        XCTAssertEqual(exported.width, preview.width * 3, accuracy: 0.001)
        XCTAssertEqual(exported.height, preview.height * 3, accuracy: 0.001)
        XCTAssertEqual(preview.width, 360 * 0.75 * 0.6, accuracy: 0.001)
    }
    func testOversizedDraggedWidgetStaysOnCanvasInBothAspectRatios() {
        for aspect in LiveCanvasAspect.allCases {
            for mode in CameraOverlayMode.allCases {
                for widget in LiveOverlayLayout.widgets(for: mode) {
                    var layout = LiveOverlayLayout(); layout.aspect = aspect
                    let width = 360.0, height = width / aspect.ratio
                    layout.setPlacement(.init(scale: 1000, offsetX: -1000, offsetY: 1000), widget: widget, mode: mode, width: width, height: height)
                    let rect = layout.frame(widget, mode: mode, width: width, height: height)
                    XCTAssertGreaterThanOrEqual(rect.x, -0.0001); XCTAssertGreaterThanOrEqual(rect.y, -0.0001)
                    XCTAssertLessThanOrEqual(rect.x + rect.width, width + 0.0001)
                    XCTAssertLessThanOrEqual(rect.y + rect.height, height + 0.0001)
                }
            }
        }
    }
    func testHideResetPersistenceAndModesRemainIndependent() throws {
        var layout = LiveOverlayLayout(); layout.aspect = .condensed
        layout.setVisible(false, widget: .recovery, mode: .overview)
        layout.setVisible(true, widget: .heartRateGraph, mode: .live)
        layout.setPlacement(.init(scale: 0.5), widget: .recovery, mode: .recovery, width: 360, height: 480)
        let restored = try JSONDecoder().decode(LiveOverlayLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored, layout)
        XCTAssertFalse(restored.isVisible(.recovery, mode: .overview))
        XCTAssertTrue(restored.isVisible(.recovery, mode: .recovery))
        XCTAssertTrue(restored.isVisible(.heartRateGraph, mode: .live))
        layout.reset(mode: .recovery)
        XCTAssertEqual(layout.placement(.recovery, mode: .recovery).scale, 1)
        XCTAssertFalse(layout.isVisible(.recovery, mode: .overview))
        layout.reset(mode: .live)
        XCTAssertFalse(layout.isVisible(.heartRateGraph, mode: .live))
        XCTAssertEqual(layout.aspect, .condensed)
    }
    func testNonfiniteAndZeroCanvasCannotProduceInvalidDrawingBounds() {
        var layout = LiveOverlayLayout()
        layout.placements[layout.key(.recovery, mode: .recovery)] = .init(scale: .nan, offsetX: .infinity, offsetY: -.infinity)
        let rect = layout.frame(.recovery, mode: .recovery, width: 360, height: 640)
        XCTAssertTrue([rect.x, rect.y, rect.width, rect.height].allSatisfy { $0.isFinite })
        XCTAssertEqual(layout.frame(.recovery, mode: .recovery, width: 0, height: 0).width, 0)
    }
    func testActivityStrainAndHistoricalHRHaveAccurateProvenance() {
        let now = date("2026-11-23T16:00:00Z")
        var day = DailySnapshot.empty(on: now); day.strain = 15.8
        let official = ActivityRecord(start: now, durationMinutes: 30, name: "Soccer", strain: 8.8, strainIsEstimate: false)
        let result = CameraOverlayData.metrics(mode: .strain, day: day, liveHeartRate: nil, sampleDate: nil, activity: official)
        XCTAssertEqual(result[0].value, "8.8"); XCTAssertEqual(result[0].label, "ACTIVITY STRAIN")
        let local = ActivityRecord(start: now, durationMinutes: 30, name: "Running", strain: 4.2, strainIsEstimate: true)
        XCTAssertEqual(CameraOverlayData.metrics(mode: .strain, day: day, liveHeartRate: nil, sampleDate: nil, activity: local)[0].value, "15.8")
        let photo = CameraOverlayData.metrics(mode: .live, day: day, liveHeartRate: 98, sampleDate: nil, historical: true)
        XCTAssertEqual(photo[0].label, "DAY AVG BPM"); XCTAssertEqual(photo[0].value, "98")
        XCTAssertEqual(CameraOverlayData.metrics(mode: .live, day: day, liveHeartRate: 98, sampleDate: nil)[0].value, "Connect")
    }
    func testSleepAndAdditionalHealthFieldsSurviveJSONAndFullBackup() throws {
        var day = DailySnapshot.empty(on: date("2026-11-09T00:00:00Z"))
        day.oxygenSaturation = 98; day.skinTemperatureCelsius = 33.7
        day.sleepBreakdown = .init(awakeMinutes: 30, lightMinutes: 200, deepMinutes: 80, remMinutes: 90, inBedMinutes: 400,
                                   efficiencyPercent: 92.5, consistencyPercent: 80, debtMinutes: 60)
        let data = try ImportReader.jsonEncoder().encode(DayArchive(days: [day]))
        XCTAssertEqual(try ImportReader.read(data, filename: "day.json"), [day])
        let backup = LocalBackup(selectedDate: day.date, days: [day], journal: [], activities: [])
        XCTAssertEqual(try LocalBackupCodec.decode(LocalBackupCodec.encode(backup)).days, [day])
        day.sleepBreakdown?.deepMinutes = 500
        XCTAssertThrowsError(try ImportReader.read(ImportReader.jsonEncoder().encode(DayArchive(days: [day])), filename: "bad.json"))
    }
}
