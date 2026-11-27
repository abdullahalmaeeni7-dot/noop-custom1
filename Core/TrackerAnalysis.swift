import Foundation

/// Reproducible local estimates from saved sensor readings. Provider scores remain authoritative.
public struct TrackerDayAnalysis: Equatable, Sendable {
    public var strain: Double?
    public var sleepMinutes: Int?
}

public enum TrackerAnalysis {
    public static func calculate(days: [DailySnapshot], activities: [ActivityRecord], now: Date = Date(),
                                 timeZone: TimeZone = .autoupdatingCurrent,
                                 resting: Double = 55, maximum: Double = 190) -> [Date: TrackerDayAnalysis] {
        let personal = days.filter { $0.source != .example }
        let readings = personal.flatMap(\.heartRates).filter {
            ($0.trackerRecorded == true || $0.trackerContactReading != nil) &&
            $0.timestamp <= now &&
            $0.bpm.isFinite && (25...230).contains($0.bpm)
        }
        let localDays = Dictionary(grouping: readings) { DashboardDatePolicy.today(now: $0.timestamp, timeZone: timeZone) }
        var results: [Date: TrackerDayAnalysis] = [:]
        for (date, samples) in localDays {
            var unique: [Date: HeartRateSample] = [:]
            for sample in samples { unique[sample.timestamp] = sample }
            let sorted = unique.values.sorted { $0.timestamp < $1.timestamp }
            var raw = 0.0
            var coverage = 0.0
            for (before, after) in zip(sorted, sorted.dropFirst()) {
                let elapsed = after.timestamp.timeIntervalSince(before.timestamp)
                guard before.trackerContactReading != false, after.trackerContactReading != false,
                      elapsed > 0, elapsed <= 90,
                      let reserve = try? StrainCalculator.reserve(heartRate: (before.bpm + after.bpm) / 2,
                                                                  restingHeartRate: resting, maximumHeartRate: maximum),
                      let load = try? StrainCalculator.weightedContribution(reserve: reserve, durationSeconds: elapsed) else { continue }
                coverage += elapsed
                raw += load
            }
            let score = coverage >= 60 ? try? StrainCalculator.scaledScore(raw: min(1, raw / 691_200)) : nil
            results[date] = TrackerDayAnalysis(strain: score)
        }
        // Re-evaluate recent nights after an incoming batch, including a wake day
        // that has no provider snapshot yet. Work is bounded to seven nights.
        let today = DashboardDatePolicy.today(now: now, timeZone: timeZone)
        for offset in 0..<7 {
            let wakeDay = today.addingTimeInterval(-Double(offset) * 86_400)
            guard let interval = OvernightRest.candidate(wakeDay: wakeDay, days: personal,
                  activities: activities, now: now, timeZone: timeZone, allowTrackerHistory: true),
                  now.timeIntervalSince(interval.end) >= 30 * 60 else { continue }
            // Require subsequent samples to show the band continued recording.
            // A lost Bluetooth connection alone is not evidence of waking up.
            guard readings.contains(where: { $0.trackerContactReading != false && $0.timestamp > interval.end && $0.timestamp <= interval.end.addingTimeInterval(30 * 60) }) else { continue }
            var day = results[wakeDay] ?? TrackerDayAnalysis()
            day.sleepMinutes = Int(interval.duration / 60)
            results[wakeDay] = day
        }
        return results
    }
}
