import Foundation

/// Duration of the union of asleep intervals, clipped to a half-open day/range.
/// Callers must exclude awake and in-bed records before passing intervals here.
public enum SleepIntervals {
    public static func seconds(_ intervals: [DateInterval], within range: DateInterval) -> TimeInterval {
        guard range.start < range.end else { return 0 }
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, range.start)
            let end = min(interval.end, range.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }
        guard var current = clipped.first else { return 0 }
        var total: TimeInterval = 0
        for interval in clipped.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration
                current = interval
            }
        }
        return total + current.duration
    }

    /// Round down once after unioning intervals; never round each stage separately.
    public static func minutes(_ intervals: [DateInterval], within range: DateInterval) -> Int {
        Int((seconds(intervals, within: range) / 60).rounded(.down))
    }
}

/// Total reported sleep by local wake date. Overlapping samples from different devices
/// describe the same asleep time; a quiet period or an awake gap never adds sleep.
public extension SleepIntervals {
    static func minutesByWakeDay(_ intervals: [DateInterval], now: Date,
                                 timeZone: TimeZone = .autoupdatingCurrent) -> [Date: Int] {
        let valid = intervals.filter { $0.duration > 0 && $0.duration <= 86_400 && $0.end <= now }
            .sorted { $0.start < $1.start }
        guard var night = valid.first else { return [:] }
        var asleep = night.duration
        var totals: [Date: TimeInterval] = [:]
        for sample in valid.dropFirst() {
            if sample.start.timeIntervalSince(night.end) <= 90 * 60,
               sample.end.timeIntervalSince(night.start) <= 86_400 {
                asleep += max(0, sample.end.timeIntervalSince(max(sample.start, night.end)))
                night = DateInterval(start: night.start, end: max(night.end, sample.end))
            } else {
                totals[DashboardDatePolicy.today(now: night.end, timeZone: timeZone), default: 0] += asleep
                night = sample
                asleep = sample.duration
            }
        }
        totals[DashboardDatePolicy.today(now: night.end, timeZone: timeZone), default: 0] += asleep
        return totals.compactMapValues {
            let minutes = Int($0 / 60)
            return (1...1440).contains(minutes) ? minutes : nil
        }
    }
}

public extension DailySnapshot {
    /// Official/imported durations take precedence over Apple Health, while a
    /// later HealthKit correction may update the app's own previous Health import.
    mutating func mergeReportedSleep(from incoming: DailySnapshot) {
        guard incoming.sleepMinutes > 0 else { return }
        guard incoming.sleepFromAppleHealth != true || sleepMinutes == 0 || sleepFromAppleHealth == true else { return }
        sleepMinutes = incoming.sleepMinutes
        sleepFromAppleHealth = incoming.sleepFromAppleHealth
    }
}
