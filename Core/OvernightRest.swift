import Foundation

/// Locates a resting interval for the wearer to review. Its boundaries are actual
/// contact-qualified observations, never an inferred sleep onset or wake time.
public enum OvernightRest {
    private struct Minute {
        var first: Date
        var last: Date
        var eligible: Bool
    }

    public static func candidate(
        wakeDay: Date,
        days: [DailySnapshot],
        activities: [ActivityRecord],
        now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent,
        allowTrackerHistory: Bool = false
    ) -> DateInterval? {
        let archive = DayCalendar.utc
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let wakeKey = archive.startOfDay(for: wakeDay)
        let civilDate = archive.dateComponents([.year, .month, .day], from: wakeKey)
        guard let midnight = local.date(from: civilDate),
              let previous = local.date(byAdding: .day, value: -1, to: midnight),
              let evening = local.date(bySettingHour: 20, minute: 0, second: 0, of: previous),
              let morning = local.date(bySettingHour: 6, minute: 0, second: 0, of: midnight),
              let noon = local.date(bySettingHour: 12, minute: 0, second: 0, of: midnight),
              now >= midnight,
              let weekAgo = archive.date(byAdding: .day, value: -7, to: wakeKey) else { return nil }

        let end = min(noon, now)
        let personal = days.filter { $0.source != .example }
        let baseline = personal.filter {
            $0.date >= weekAgo && $0.date <= wakeKey &&
                $0.restingHeartRate.map { (35...90).contains($0) } == true
        }.max { $0.date < $1.date }?.restingHeartRate
        // First-time wearers have no measured baseline. Require a longer run
        // of lower readings and substantial night coverage before offering review.
        let restingRange = baseline.map { max(35, $0 - 15)...min(95, $0 + 10) } ?? (40...75)
        let requiredSeconds: TimeInterval = baseline == nil ? 4 * 3600 : 2 * 3600
        let earlyNight = DateInterval(start: midnight, end: morning)
        let window = DateInterval(start: evening, end: end)
        let blocked = activities.compactMap { record -> DateInterval? in
            guard (1...1440).contains(record.durationMinutes) else { return nil }
            let interval = DateInterval(start: record.start, duration: Double(record.durationMinutes) * 60)
            return interval.intersection(with: window)
        }.sorted { $0.start < $1.start }

        var minutes: [Int: Minute] = [:]
        let firstKey = archive.startOfDay(for: evening)
        let lastKey = archive.startOfDay(for: end)
        for day in personal where (firstKey...lastKey).contains(day.date) {
            for sample in day.heartRates where sample.timestamp >= evening && sample.timestamp <= end {
                // An unknown-source import is never positive evidence. An overt
                // contact loss or out-of-range tagged reading splits the run.
                guard let onBody = sample.trackerContactReading ?? (allowTrackerHistory && sample.trackerRecorded == true ? true : nil) else { continue }
                let key = Int(floor(sample.timestamp.timeIntervalSince1970 / 60))
                let eligible = onBody && restingRange.contains(sample.bpm)
                if var value = minutes[key] {
                    value.first = min(value.first, sample.timestamp)
                    value.last = max(value.last, sample.timestamp)
                    value.eligible = value.eligible && eligible
                    minutes[key] = value
                } else {
                    minutes[key] = Minute(first: sample.timestamp, last: sample.timestamp, eligible: eligible)
                }
            }
        }

        var longest: DateInterval?
        var runStart: Date?
        var previousKey: Int?
        var previousTime: Date?
        var workoutIndex = 0
        for key in minutes.keys.sorted() {
            guard let minute = minutes[key] else { continue }
            let contiguous = previousKey == key - 1 &&
                previousTime.map { minute.first.timeIntervalSince($0) <= 90 } == true
            let segmentStart = contiguous ? previousTime ?? minute.first : minute.first
            while workoutIndex < blocked.count, blocked[workoutIndex].end < segmentStart {
                workoutIndex += 1
            }
            let workout = workoutIndex < blocked.count && blocked[workoutIndex].start <= minute.last
            if !contiguous || !minute.eligible || workout { runStart = nil }
            if minute.eligible && !workout {
                let start = runStart ?? minute.first
                runStart = start
                let interval = DateInterval(start: start, end: minute.last)
                if minute.last >= midnight, interval.duration >= requiredSeconds,
                   baseline != nil || (interval.intersection(with: earlyNight)?.duration ?? 0) >= 2 * 3600,
                   interval.duration >= (longest?.duration ?? 0) {
                    longest = interval
                }
            }
            previousKey = key
            previousTime = minute.last
        }
        return longest
    }
}
