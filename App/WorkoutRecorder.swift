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
    @Published private(set) var detectedActivity: ActivityRecord?
    private var accumulator = DailyTrackerAccumulator()
    private var detector = TrackerActivityDetector()
    private var checkpoints: [UUID: TrackerActivityCheckpoint] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private weak var store: AppStore?
    private weak var manual: WorkoutRecorder?
    private var generation: UUID?
    private var firstPendingAt: Date?
    private var lastSaveAttempt = Date.distantPast
    private static let bufferWindow: TimeInterval = 7 * 24 * 60 * 60

    func bind(_ device: DeviceModel, to store: AppStore, manualRecorder: WorkoutRecorder) {
        guard subscriptions.isEmpty else { return }
        self.store = store
        manual = manualRecorder
        generation = store.trackerDataGeneration

        // These publishers and the CoreBluetooth delegate run on the main queue.
        // Process them in delivery order, including contact changes between samples.
        device.heartRateSamples.sink { [weak self] in self?.receive($0) }.store(in: &subscriptions)
        device.$wearState.removeDuplicates().sink { [weak self] state in
            if state == .offBody { self?.interrupt() }
        }.store(in: &subscriptions)
        device.$connectedName.dropFirst().sink { [weak self] name in
            if name == nil { self?.interrupt() }
        }.store(in: &subscriptions)
        manualRecorder.$isRecording.sink { [weak self] recording in
            if recording { self?.interruptDetection() }
        }.store(in: &subscriptions)
        Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] now in
            self?.detector.expire(at: now)
            if self?.detector.activity == nil, self?.detectedActivity != nil { self?.detectedActivity = nil }
            self?.flush()
        }.store(in: &subscriptions)
    }

    private func interruptDetection() {
        detector.interrupt()
        if detectedActivity != nil { detectedActivity = nil }
    }

    private func interrupt() {
        interruptDetection()
        accumulator.interruptStream()
        flush()
    }

    private func synchronizeGeneration() {
        if generation != store?.trackerDataGeneration {
            accumulator.reset()
            interruptDetection()
            checkpoints.removeAll()
            error = nil
            firstPendingAt = nil
            generation = store?.trackerDataGeneration
        }
    }

    private func receive(_ sample: HeartRateSample) {
        synchronizeGeneration()
        guard store != nil else { return }
        let now = Date()
        if let firstPendingAt, sample.timestamp.timeIntervalSince(firstPendingAt) >= Self.bufferWindow {
            if now.timeIntervalSince(lastSaveAttempt) >= 15 { flush() }
            // Preserve the oldest unsaved batch. Continue retrying from BLE events
            // when iOS suspends the timer after a write failure.
            if self.firstPendingAt != nil {
                interruptDetection()
                accumulator.interruptStream()
                error = "Tracker storage is full or unavailable. New readings are paused until the buffered data can be saved."
                return
            }
        }
        let savedResting = UserDefaults.standard.double(forKey: Self.restingKey)
        let savedMaximum = UserDefaults.standard.double(forKey: Self.maximumKey)
        let resting = (30...110).contains(savedResting) ? savedResting : 55
        let maximum = (120...230).contains(savedMaximum) ? savedMaximum : 190
        do {
            try accumulator.append(sample, resting: resting, maximum: maximum)
            if firstPendingAt == nil { firstPendingAt = sample.timestamp }
            if manual?.isRecording != true {
                let previous = detector.activity
                detector.receive(sample, resting: resting, maximum: maximum)
                if let current = detector.activity, current != previous {
                    let mayInsert = checkpoints[current.id]?.mayInsert ?? (previous?.id != current.id)
                    checkpoints[current.id] = TrackerActivityCheckpoint(record: current, mayInsert: mayInsert)
                }
                if detectedActivity != detector.activity { detectedActivity = detector.activity }
            }
            if now.timeIntervalSince(lastSaveAttempt) >= 15 { flush() }
        } catch {
            // A duplicate or nonfinite reading must never extend a detected activity.
        }
    }

    func flush() {
        synchronizeGeneration()
        guard let store, !store.isLoadingSavedData, firstPendingAt != nil else { return }
        lastSaveAttempt = Date()
        do {
            try store.saveTrackerReadings(accumulator.pending, activities: Array(checkpoints.values))
            accumulator.acknowledgeSaved()
            checkpoints.removeAll()
            firstPendingAt = nil
            if error != nil { error = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
