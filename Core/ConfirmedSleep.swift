import Foundation

/// A member-confirmed sleep log. Provider sleep duration and all scores remain independent.
public struct ConfirmedSleep: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Preserve the wake-day assignment when the device later changes time zones.
    public let timeZoneID: String

    public init(start: Date, end: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        self.start = start
        self.end = end
        self.timeZoneID = timeZone.identifier
    }

    public var minutes: Int {
        let elapsed = end.timeIntervalSince(start)
        return elapsed.isFinite && (60...86_400).contains(elapsed) ? Int(elapsed / 60) : 0
    }

    public func validate(on wakeDay: Date, now: Date? = nil) throws {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              minutes > 0, let zone = TimeZone(identifier: timeZoneID),
              DashboardDatePolicy.today(now: end, timeZone: zone) == DayCalendar.start(of: wakeDay),
              now.map({ end <= $0 }) ?? true else {
            throw ImportError.invalid("Choose a sleep interval of 1 minute to 24 hours that ends on the selected day and has already finished.")
        }
    }
}
