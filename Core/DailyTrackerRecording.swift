import Foundation

/// Locally observed coverage and estimated load. Provider scores stay in DailySnapshot.strain.
public struct DailyTrackerRecording: Codable, Equatable, Sendable {
    public var firstSampleAt: Date
    public var lastSampleAt: Date
    public var sampleCount: Int
    public var processedSampleCount: Int
    public var observedSeconds: Double
    public var rawStrain: Double

    public var strainEstimate: Double? {
        processedSampleCount > 0 ? try? StrainCalculator.scaledScore(raw: rawStrain) : nil
    }

    public func validated(on day: Date) throws {
        guard firstSampleAt.timeIntervalSince1970.isFinite, lastSampleAt.timeIntervalSince1970.isFinite,
              firstSampleAt.timeIntervalSince1970 >= 0, firstSampleAt <= lastSampleAt,
              DayCalendar.start(of: firstSampleAt) == day, DayCalendar.start(of: lastSampleAt) == day,
              (1...10_000_000).contains(sampleCount), (0...sampleCount).contains(processedSampleCount),
              observedSeconds.isFinite, (0...86_400).contains(observedSeconds),
              rawStrain.isFinite, (0...1).contains(rawStrain),
              processedSampleCount > 0 || (observedSeconds == 0 && rawStrain == 0) else {
            throw ImportError.invalid("The local tracker recording has invalid counts, coverage, load or dates.")
        }
    }

    public func merging(_ update: Self, on day: Date) throws -> Self {
        try validated(on: day); try update.validated(on: day)
        let merged = Self(firstSampleAt: min(firstSampleAt, update.firstSampleAt),
                          lastSampleAt: max(lastSampleAt, update.lastSampleAt),
                          sampleCount: sampleCount + update.sampleCount,
                          processedSampleCount: processedSampleCount + update.processedSampleCount,
                          observedSeconds: observedSeconds + update.observedSeconds,
                          rawStrain: min(1, rawStrain + update.rawStrain))
        try merged.validated(on: day)
        return merged
    }
}

public struct DailyTrackerBatch: Sendable {
    public let date: Date
    public let recording: DailyTrackerRecording
    /// One genuine reading per UTC minute for a bounded saved chart. No invented averages.
    public let chartSamples: [HeartRateSample]
}

/// Keeps the live engine between disk batches, resets on gaps/profile/day changes,
/// and never fills periods while the phone is not receiving readings.
public struct DailyTrackerAccumulator {
    private var engine: LiveStrainEngine?
    private var currentDay: Date?
    private var lastTimestamp: Date?
    private var records: [Date: DailyTrackerRecording] = [:]
    private var chart: [Date: [Int64: HeartRateSample]] = [:]
    public init() {}

    public var pending: [DailyTrackerBatch] {
        records.keys.sorted().compactMap { day in
            guard let recording = records[day] else { return nil }
            return DailyTrackerBatch(date: day, recording: recording,
                              chartSamples: (chart[day] ?? [:]).values.sorted { $0.timestamp < $1.timestamp })
        }
    }
    public mutating func acknowledgeSaved() { records = [:]; chart = [:] }
    public mutating func reset() { self = Self() }
    /// Stop integrating immediately on explicit loss of skin contact or a link.
    /// Preserve uncommitted batches and the timestamp guard across reconnection.
    public mutating func interruptStream() { engine = nil; currentDay = nil }


    public mutating func append(_ sample: HeartRateSample, resting: Double, maximum: Double) throws {
        _ = try LiveStrainPoint(sample)
        if let lastTimestamp, sample.timestamp <= lastTimestamp { throw LiveStrainError.unorderedTimestamp }
        let day = DayCalendar.start(of: sample.timestamp)
        var next = engine
        if currentDay != day || next?.restingHeartRate != resting || next?.maximumHeartRate != maximum {
            next = try LiveStrainEngine(restingHeartRate: resting, maximumHeartRate: maximum)
        }
        var previousRaw = next?.rawStrain ?? 0
        var previousProcessed = next?.processedSampleCount ?? 0
        var previousSeconds = next?.observedSeconds ?? 0
        do { try next?.append(sample) }
        catch LiveStrainError.gapTooLarge {
            next = try LiveStrainEngine(restingHeartRate: resting, maximumHeartRate: maximum)
            previousRaw = 0; previousProcessed = 0; previousSeconds = 0
            try next?.append(sample)
        }
        var record = records[day] ?? DailyTrackerRecording(firstSampleAt: sample.timestamp, lastSampleAt: sample.timestamp,
                                                          sampleCount: 0, processedSampleCount: 0, observedSeconds: 0, rawStrain: 0)
        record.lastSampleAt = sample.timestamp; record.sampleCount += 1
        record.processedSampleCount += (next?.processedSampleCount ?? 0) - previousProcessed
        record.observedSeconds += (next?.observedSeconds ?? 0) - previousSeconds
        record.rawStrain = min(1, record.rawStrain + (next?.rawStrain ?? 0) - previousRaw)
        try record.validated(on: day)
        let minute = Int64(sample.timestamp.timeIntervalSince1970 / 60)
        records[day] = record; chart[day, default: [:]][minute] = sample
        engine = next; currentDay = day; lastTimestamp = sample.timestamp
    }
}

extension DailySnapshot {
    /// Atomic value-level merge shared by persistence and regression tests.
    public func applyingTrackerBatch(_ batch: DailyTrackerBatch) throws -> Self {
        guard date == batch.date else { throw ImportError.invalid("Tracker data must belong to its UTC day.") }
        try batch.recording.validated(on: date)
        var updated = self
        var rates = heartRates.reduce(into: [Date: HeartRateSample]()) { $0[$1.timestamp] = $1 }
        if let previous = trackerRecording?.lastSampleAt,
           batch.chartSamples.contains(where: { Int64($0.timestamp.timeIntervalSince1970 / 60) == Int64(previous.timeIntervalSince1970 / 60) }) {
            rates.removeValue(forKey: previous)
        }
        for sample in batch.chartSamples {
            guard sample.timestamp.timeIntervalSince1970.isFinite, sample.bpm.isFinite, sample.bpm > 0, sample.bpm <= 300, DayCalendar.start(of: sample.timestamp) == date else {
                throw ImportError.invalid("Invalid automatic tracker chart sample.")
            }
            rates[sample.timestamp] = sample
        }
        updated.heartRates = rates.values.sorted { $0.timestamp < $1.timestamp }
        updated.trackerRecording = try trackerRecording.map { try $0.merging(batch.recording, on: date) } ?? batch.recording
        return updated
    }
}
