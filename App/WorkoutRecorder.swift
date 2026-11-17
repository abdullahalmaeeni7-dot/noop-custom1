import Foundation
import Combine
import WHOOPCore

/// A foreground recorder. Device timestamps use receipt time; strap epoch is not inferred.
@MainActor
final class WorkoutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var samples = 0
    @Published private(set) var localStrain: Double?
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var heartRateIsFresh = false
    private var lastSampleDate: Date?
    var latestSampleDate: Date? { lastSampleDate }
    @Published private(set) var status = "Connect a heart-rate source, then start recording."
    private var rates: [HeartRateSample] = []
    private var engine: LiveStrainEngine?
    private var baseRaw = 0.0
    private var processedCount = 0
    private var started: Date?
    private var pauseStarted: Date?
    private var pausedSeconds = 0.0
    private var resting = 55.0, maximum = 190.0
    private var subscription: AnyCancellable?
    private var clock: AnyCancellable?
    private(set) var name = "Workout"

    func bind(_ device: DeviceModel) {
        guard subscription == nil else { return }
        subscription = device.heartRateSamples.sink { [weak self] sample in
            Task { @MainActor in self?.receive(sample.bpm, at: sample.timestamp) }
        }
        clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func start(name: String, resting: Double, maximum: Double) throws {
        guard !isRecording else { return }
        engine = try LiveStrainEngine(restingHeartRate: resting, maximumHeartRate: maximum)
        self.name = String(name.prefix(80)); self.resting = resting; self.maximum = maximum
        rates = []; samples = 0; baseRaw = 0; processedCount = 0; localStrain = nil
        latestHeartRate = nil; heartRateIsFresh = false; lastSampleDate = nil; elapsedSeconds = 0; pausedSeconds = 0; pauseStarted = nil
        started = Date(); isRecording = true; isPaused = false
        status = "Recording. Waiting for live heart rate…"
    }
    func togglePause() {
        guard isRecording else { return }
        if isPaused {
            if let pauseStarted { pausedSeconds += Date().timeIntervalSince(pauseStarted) }
            pauseStarted = nil
            engine = try? LiveStrainEngine(restingHeartRate: resting, maximumHeartRate: maximum)
            isPaused = false; status = "Recording resumed. Waiting for fresh heart rate…"
        } else {
            if let engine { baseRaw += engine.rawStrain; processedCount += engine.processedSampleCount }
            engine = nil; pauseStarted = Date(); isPaused = true; heartRateIsFresh = false
            status = "Paused. No heart-rate samples are being recorded."
        }
        tick()
    }
    private func receive(_ bpm: Double, at date: Date) {
        guard isRecording, !isPaused else { return }
        tick()
        guard rates.count < 21_600, elapsedSeconds < 21_600 else {
            status = "Recording limit reached. Save this session before starting another."; return
        }
        let sample = HeartRateSample(timestamp: date, bpm: bpm)
        guard rates.last.map({ date.timeIntervalSince($0.timestamp) >= 0.001 }) ?? true else { return }
        do {
            do { try engine?.append(sample) }
            catch LiveStrainError.gapTooLarge {
                if let engine { baseRaw += engine.rawStrain; processedCount += engine.processedSampleCount }
                engine = try LiveStrainEngine(restingHeartRate: resting, maximumHeartRate: maximum)
                try engine?.append(sample)
            }
            rates.append(sample); samples = rates.count; latestHeartRate = bpm
            lastSampleDate = date; heartRateIsFresh = true
            let processed = processedCount + (engine?.processedSampleCount ?? 0)
            localStrain = processed > 0 ? try StrainCalculator.scaledScore(raw: baseRaw + (engine?.rawStrain ?? 0)) : nil
            status = processed > 0 ? "Recording live heart rate. Local strain is an estimate." : "Collecting heart rate. The local estimate needs at least 32 fresh samples."
        } catch { status = "A reading was skipped: \(error.localizedDescription)" }
    }
    func save(to store: AppStore) throws {
        guard isRecording, let started else { return }
        tick()
        try store.saveRecordedWorkout(name: name, start: started, durationSeconds: max(1, elapsedSeconds), heartRates: rates, localStrain: localStrain)
        isRecording = false; isPaused = false; engine = nil; pauseStarted = nil
        rates = []; status = "Workout saved on this iPhone."
    }
    func discard() {
        isRecording = false; isPaused = false; rates = []; engine = nil; started = nil
        pauseStarted = nil; samples = 0; localStrain = nil; elapsedSeconds = 0
        status = "Recording discarded."
    }
    private func tick() {
        guard isRecording, let started else { return }
        let now = pauseStarted ?? Date()
        elapsedSeconds = min(21_600, max(0, Int(now.timeIntervalSince(started) - pausedSeconds)))
        heartRateIsFresh = !isPaused && (lastSampleDate.map { (0...10).contains(Date().timeIntervalSince($0)) } ?? false)
        if elapsedSeconds >= 21_600 { status = "Recording limit reached. Save this session before starting another." }
        else if !isPaused, !heartRateIsFresh, lastSampleDate != nil { status = "Waiting for fresh heart rate. Missing readings are not filled in." }
    }
}


/// Automatic tracking is separate from manually named workouts. Only delivered BLE
/// readings count; there is no strap-history backfill or synthesized overnight score.
@MainActor
final class DailyTrackerRecorder: ObservableObject {
    nonisolated static let restingKey = "whoop.tracking.resting.v1"
    nonisolated static let maximumKey = "whoop.tracking.maximum.v1"
    @Published private(set) var error: String?
    private var accumulator = DailyTrackerAccumulator()
    private var subscription: AnyCancellable?
    private var clock: AnyCancellable?
    private weak var store: AppStore?
    private var generation: UUID?
    private var lastSavedAt = Date.distantPast

    func bind(_ device: DeviceModel, to store: AppStore) {
        guard subscription == nil else { return }
        self.store = store; generation = store.trackerDataGeneration
        subscription = device.heartRateSamples.sink { [weak self] sample in
            Task { @MainActor in self?.receive(sample) }
        }
        clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }
    private func synchronizeGeneration() {
        if generation != store?.trackerDataGeneration {
            accumulator.reset(); error = nil; generation = store?.trackerDataGeneration
        }
    }
    private func receive(_ sample: HeartRateSample) {
        synchronizeGeneration()
        guard let store, !store.isLoadingSavedData, error == nil else { return }
        let savedResting = UserDefaults.standard.double(forKey: Self.restingKey)
        let savedMaximum = UserDefaults.standard.double(forKey: Self.maximumKey)
        let resting = (30...110).contains(savedResting) ? savedResting : 55
        let maximum = (120...230).contains(savedMaximum) ? savedMaximum : 190
        do {
            try accumulator.append(sample, resting: resting, maximum: maximum)
            // Also flush from incoming events when a foreground timer is suspended.
            if sample.timestamp.timeIntervalSince(lastSavedAt) >= 15 { flush() }
        } catch { /* Invalid or out-of-order readings never contribute to the estimate. */ }
    }
    func flush() {
        synchronizeGeneration()
        guard let store, !store.isLoadingSavedData, !accumulator.pending.isEmpty else { return }
        do {
            try store.saveTrackerReadings(accumulator.pending)
            accumulator.acknowledgeSaved(); lastSavedAt = Date(); error = nil
        } catch { self.error = error.localizedDescription }
    }
}
