import Foundation

public struct TrackerChartPoint: Identifiable, Equatable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let bpm: Double
    public let segment: Int
}

public enum TrackerChartData {
    /// At most one actual reading per minute over the last 24 hours. Never bridge
    /// a missing interval longer than 150 seconds or include screenshot fixtures.
    public static func points(days: [DailySnapshot], live: HeartRateSample?, now: Date) -> [TrackerChartPoint] {
        var minutes: [Int: HeartRateSample] = [:]
        func include(_ sample: HeartRateSample) {
            let age = now.timeIntervalSince(sample.timestamp)
            guard sample.trackerRecorded == true, sample.bpm.isFinite, (25...230).contains(sample.bpm),
                  age.isFinite, (0...86_400).contains(age) else { return }
            let minute = Int(floor(sample.timestamp.timeIntervalSince1970 / 60))
            if let previous = minutes[minute], previous.timestamp > sample.timestamp { return }
            minutes[minute] = sample
        }
        for day in days where day.source != .example {
            for sample in day.heartRates { include(sample) }
        }
        if let live { include(live) }
        let samples = minutes.values.sorted { $0.timestamp < $1.timestamp }
        var segment = 0
        return samples.enumerated().map { index, sample in
            if index > 0, sample.timestamp.timeIntervalSince(samples[index - 1].timestamp) > 150 { segment += 1 }
            return TrackerChartPoint(timestamp: sample.timestamp, bpm: sample.bpm, segment: segment)
        }
    }
}
