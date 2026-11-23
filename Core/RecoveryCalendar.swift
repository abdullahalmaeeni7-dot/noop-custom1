import Foundation

public enum RecoveryBand: String, Codable, Sendable {
    case unavailable, red, yellow, green
    public init(score: Int?) {
        guard let score, (0...100).contains(score) else { self = .unavailable; return }
        self = score <= 33 ? .red : score <= 66 ? .yellow : .green
    }
}

/// UTC archive dates stay immutable. Browsing and opening the app are separate
/// from the date a historical measurement was taken.
public enum DashboardDatePolicy {
    public static func today(now: Date = Date()) -> Date { DayCalendar.start(of: now) }
    public static func afterImport(now: Date = Date()) -> Date { today(now: now) }
    public static func onRollover(selected: Date, previousToday: Date, now: Date) -> Date {
        DayCalendar.start(of: selected) == DayCalendar.start(of: previousToday) ? today(now: now) : DayCalendar.start(of: selected)
    }
}

public struct RecoveryCalendarMonth: Equatable, Sendable {
    public let start: Date
    public let cells: [Date?]
    public let firstWeekday: Int
    public init(containing date: Date, firstWeekday: Int = 2) {
        let calendar = DayCalendar.utc
        let start = calendar.dateInterval(of: .month, for: date)!.start
        self.start = start
        let weekday = min(7, max(1, firstWeekday)); self.firstWeekday = weekday
        let offset = (calendar.component(.weekday, from: start) - weekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        let length = ((offset + count + 6) / 7) * 7
        cells = (0..<length).map { index in
            guard index >= offset, index < offset + count else { return nil }
            return calendar.date(byAdding: .day, value: index - offset, to: start)
        }
    }
    public func shifted(by months: Int) -> Self {
        Self(containing: DayCalendar.utc.date(byAdding: .month, value: months, to: start)!, firstWeekday: firstWeekday)
    }
}
