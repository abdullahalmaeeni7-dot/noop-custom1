import Foundation

/// A local observation of sustained elevated heart rate. HR alone cannot identify
/// the sport, distinguish quiet wakefulness from sleep, or assign WHOOP scores.
public struct TrackerActivityDetector {
    public static let minimumDuration: TimeInterval = 5 * 60
    public static let maximumSampleGap: TimeInterval = 15
    public private(set) var activity: ActivityRecord?

    private var firstElevated: Date?
    private var lastReading: Date?
    private var limits: ClosedRange<Double>?

    public init() {}

    public mutating func interrupt() { self = Self() }

    public mutating func expire(at now: Date) {
        if let lastReading, now.timeIntervalSince(lastReading) > Self.maximumSampleGap { interrupt() }
    }

    public mutating func receive(_ sample: HeartRateSample, resting: Double, maximum: Double) {
        guard resting.isFinite, maximum.isFinite, resting < maximum,
              sample.timestamp.timeIntervalSince1970.isFinite,
              sample.bpm.isFinite, (1...300).contains(sample.bpm) else {
            interrupt()
            return
        }
        if let lastReading, sample.timestamp <= lastReading { return }
        expire(at: sample.timestamp)
        let currentLimits = resting...maximum
        if limits != currentLimits { interrupt() }
        limits = currentLimits
        lastReading = sample.timestamp

        let reserve = (sample.bpm - resting) / (maximum - resting)
        // After onset use a lower exit threshold so small fluctuations do not split a bout.
        guard reserve >= (activity == nil ? 0.50 : 0.40) else {
            firstElevated = nil
            activity = nil
            return
        }
        let start = firstElevated ?? sample.timestamp
        firstElevated = start
        let elapsed = sample.timestamp.timeIntervalSince(start)
        guard elapsed >= Self.minimumDuration else { return }
        let minutes = Int(elapsed / 60)
        if minutes > 1440 { interrupt(); return }
        if activity == nil {
            activity = ActivityRecord(start: start, durationMinutes: minutes,
                                      name: "Elevated heart rate", automaticallyDetected: true)
        } else {
            activity?.durationMinutes = minutes
        }
    }
}

/// Automatic checkpoints, unlike manually named or imported workouts, yield to
/// an overlapping explicit record. Updates to a deleted checkpoint never reinsert it.
public struct TrackerActivityCheckpoint {
    public let record: ActivityRecord
    public let mayInsert: Bool

    public init(record: ActivityRecord, mayInsert: Bool) {
        self.record = record
        self.mayInsert = mayInsert
    }
}

public extension Array where Element == ActivityRecord {
    mutating func mergeTrackerActivity(_ update: TrackerActivityCheckpoint) {
        let next = update.record
        guard next.automaticallyDetected == true else { return }
        if contains(where: { $0.automaticallyDetected != true && $0.overlaps(next) }) {
            removeAll { $0.id == next.id && $0.automaticallyDetected == true }
            return
        }
        if let index = firstIndex(where: { $0.id == next.id }) {
            if self[index].automaticallyDetected == true { self[index] = next }
        } else if update.mayInsert {
            append(next)
        }
    }

    mutating func mergeSavedActivity(_ record: ActivityRecord) {
        if record.automaticallyDetected == true {
            mergeTrackerActivity(.init(record: record, mayInsert: true))
            return
        }
        removeAll { $0.automaticallyDetected == true && $0.overlaps(record) }
        if let index = firstIndex(where: { $0.id == record.id }) { self[index] = record }
        else { append(record) }
    }
}

private extension ActivityRecord {
    func overlaps(_ other: ActivityRecord) -> Bool {
        start < other.start.addingTimeInterval(Double(other.durationMinutes) * 60) &&
            other.start < start.addingTimeInterval(Double(durationMinutes) * 60)
    }
}
