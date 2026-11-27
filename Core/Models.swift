import Foundation

public enum DataSource: String, Codable, Sendable {
    case example, imported
    public var title: String { self == .example ? "Example data" : "Imported data" }
}

/// All archive dates and day grouping use UTC, independent of device timezone.
public enum DayCalendar {
    public static var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    public static func start(of date: Date) -> Date { utc.startOfDay(for: date) }
}

/// A personal session starts empty and never adopts screenshot/example scores.
public struct LaunchDayData: Equatable, Sendable {
    public let days: [DailySnapshot]
    public let selectedDate: Date
    public init(savedDays: [DailySnapshot] = [], selectedDate: Date? = nil, now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        days = savedDays.filter { $0.source != .example }.sorted { $0.date < $1.date }
        self.selectedDate = DashboardDatePolicy.today(now: now, timeZone: timeZone)
    }
}

public struct HeartRateSample: Codable, Identifiable, Equatable, Sendable {
    public var timestamp: Date
    public var bpm: Double
    /// Only live tracker samples delivered with positive wrist-contact evidence set this flag.
    public var trackerContactReading: Bool?
    public var trackerRecorded: Bool?
    public var id: Date { timestamp }
    public init(timestamp: Date, bpm: Double, trackerContactReading: Bool? = nil, trackerRecorded: Bool? = nil) {
        self.timestamp = timestamp; self.bpm = bpm; self.trackerContactReading = trackerContactReading; self.trackerRecorded = trackerRecorded
    }
}

public struct DailySnapshot: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var recovery: Int?
    public var strain: Double?
    public var sleepPerformance: Int?
    public var sleepMinutes: Int
    public var sleepFromAppleHealth: Bool?
    public var confirmedSleep: ConfirmedSleep?
    public var estimatedSleepMinutes: Int? = nil
    public var estimatedTrackerStrain: Double? = nil
    public var usesConfirmedSleep: Bool { sleepMinutes == 0 && confirmedSleep != nil }
    public var displayedSleepMinutes: Int { sleepMinutes > 0 ? sleepMinutes : confirmedSleep?.minutes ?? estimatedSleepMinutes ?? 0 }
    public var sleepNeededMinutes: Int
    public var restingHeartRate: Double?
    public var hrv: Double?
    public var respiratoryRate: Double?
    public var steps: Int
    public var energyKcal: Double
    public var heartRates: [HeartRateSample]
    public var source: DataSource
    public var trackerRecording: DailyTrackerRecording?
    public var oxygenSaturation: Double?
    public var skinTemperatureCelsius: Double?
    public var sleepBreakdown: SleepBreakdown?
    public var displayedStrain: Double? { strain ?? estimatedTrackerStrain ?? trackerRecording?.strainEstimate }
    public var strainIsLocalEstimate: Bool { strain == nil && (estimatedTrackerStrain != nil || trackerRecording?.strainEstimate != nil) }
    public var cycleRecords: [WhoopCycleRecord]?
    public var id: Date { date }

    public init(date: Date, recovery: Int?, strain: Double?, sleepPerformance: Int?,
                sleepMinutes: Int, sleepNeededMinutes: Int, restingHeartRate: Double?,
                hrv: Double?, respiratoryRate: Double?, steps: Int, energyKcal: Double,
                heartRates: [HeartRateSample], source: DataSource, cycleRecords: [WhoopCycleRecord]? = nil, trackerRecording: DailyTrackerRecording? = nil,
                oxygenSaturation: Double? = nil, skinTemperatureCelsius: Double? = nil, sleepBreakdown: SleepBreakdown? = nil) {
        self.date = date; self.recovery = recovery; self.strain = strain
        self.sleepPerformance = sleepPerformance; self.sleepMinutes = sleepMinutes
        self.sleepNeededMinutes = sleepNeededMinutes; self.restingHeartRate = restingHeartRate
        self.hrv = hrv; self.respiratoryRate = respiratoryRate; self.steps = steps
        self.energyKcal = energyKcal; self.heartRates = heartRates; self.source = source; self.cycleRecords = cycleRecords; self.trackerRecording = trackerRecording
        self.oxygenSaturation = oxygenSaturation; self.skinTemperatureCelsius = skinTemperatureCelsius; self.sleepBreakdown = sleepBreakdown
    }

    public static func empty(on date: Date, source: DataSource = .imported) -> Self {
        .init(date: DayCalendar.start(of: date), recovery: nil, strain: nil, sleepPerformance: nil,
              sleepMinutes: 0, sleepNeededMinutes: 0, restingHeartRate: nil, hrv: nil,
              respiratoryRate: nil, steps: 0, energyKcal: 0, heartRates: [], source: source)
    }

    private enum CodingKeys: String, CodingKey {
        case date, recovery, strain, sleepPerformance, sleepMinutes, sleepNeededMinutes, sleepFromAppleHealth, confirmedSleep
        case restingHeartRate, hrv, respiratoryRate, steps, energyKcal, heartRates, source, cycleRecords, trackerRecording, oxygenSaturation, skinTemperatureCelsius, sleepBreakdown
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(Date.self, forKey: .date)
        confirmedSleep = try values.decodeIfPresent(ConfirmedSleep.self, forKey: .confirmedSleep)
        try confirmedSleep?.validate(on: date)
        recovery = try values.decodeIfPresent(Int.self, forKey: .recovery)
        strain = try values.decodeIfPresent(Double.self, forKey: .strain)
        sleepPerformance = try values.decodeIfPresent(Int.self, forKey: .sleepPerformance)
        sleepFromAppleHealth = try values.decodeIfPresent(Bool.self, forKey: .sleepFromAppleHealth)
        sleepMinutes = try values.decodeIfPresent(Int.self, forKey: .sleepMinutes) ?? 0
        sleepNeededMinutes = try values.decodeIfPresent(Int.self, forKey: .sleepNeededMinutes) ?? 0
        restingHeartRate = try values.decodeIfPresent(Double.self, forKey: .restingHeartRate)
        hrv = try values.decodeIfPresent(Double.self, forKey: .hrv)
        respiratoryRate = try values.decodeIfPresent(Double.self, forKey: .respiratoryRate)
        steps = try values.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        energyKcal = try values.decodeIfPresent(Double.self, forKey: .energyKcal) ?? 0
        heartRates = try values.decodeIfPresent([HeartRateSample].self, forKey: .heartRates) ?? []
        source = try values.decodeIfPresent(DataSource.self, forKey: .source) ?? .imported
        cycleRecords = try values.decodeIfPresent([WhoopCycleRecord].self, forKey: .cycleRecords)
        trackerRecording = try values.decodeIfPresent(DailyTrackerRecording.self, forKey: .trackerRecording)
        oxygenSaturation = try values.decodeIfPresent(Double.self, forKey: .oxygenSaturation)
        skinTemperatureCelsius = try values.decodeIfPresent(Double.self, forKey: .skinTemperatureCelsius)
        sleepBreakdown = try values.decodeIfPresent(SleepBreakdown.self, forKey: .sleepBreakdown)
    }
}

/// Original cycle scores retained when more than one provider cycle shares a dashboard date.
/// The dashboard shows the latest cycle; scores are never added or averaged.
public struct WhoopCycleRecord: Codable, Equatable, Sendable {
    public let id: String
    public let start: Date
    public let measurements: DailySnapshot
    public init(id: String, start: Date, measurements: DailySnapshot) {
        self.id = id; self.start = start; self.measurements = measurements
    }
    public static func dailySummaries(_ records: [WhoopCycleRecord]) -> [DailySnapshot] {
        Dictionary(grouping: records, by: { DayCalendar.start(of: $0.start) }).map { _, group in
            let ordered = group.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
            var day = ordered[ordered.count - 1].measurements
            day.cycleRecords = ordered.count > 1 ? ordered : nil
            return day
        }.sorted { $0.date < $1.date }
    }
}

public struct JournalEntry: Codable, Equatable, Sendable {
    public var date: Date
    public var caffeine: Bool
    public var alcohol: Bool
    public var lateMeal: Bool
    public var note: String
    public init(date: Date, caffeine: Bool = false, alcohol: Bool = false,
                lateMeal: Bool = false, note: String = "") {
        self.date = date; self.caffeine = caffeine; self.alcohol = alcohol
        self.lateMeal = lateMeal; self.note = note
    }
}

public struct ActivityRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var durationMinutes: Int
    public var name: String
    public var strain: Double?
    /// True only for a local reference estimate, never an imported official score.
    public var strainIsEstimate: Bool?
    /// True for a local, HR-only possible activity. Unset in older backups.
    public var automaticallyDetected: Bool?
    public init(id: UUID = UUID(), start: Date, durationMinutes: Int, name: String, strain: Double? = nil, strainIsEstimate: Bool? = nil, automaticallyDetected: Bool? = nil) {
        self.id = id; self.start = start; self.durationMinutes = durationMinutes
        self.name = name; self.strain = strain; self.strainIsEstimate = strainIsEstimate
        self.automaticallyDetected = automaticallyDetected
    }
}

public struct DayArchive: Codable, Equatable, Sendable {
    public var days: [DailySnapshot]
    public init(days: [DailySnapshot]) { self.days = days }
}

/// Local display preferences. Ages are decimal strings so no arbitrary numeric age
/// ceiling or floating-point rounding is imposed on personalized display values.
public enum ProfileGender: String, Codable, CaseIterable, Sendable { case man, woman }
public enum WearWrist: String, Codable, CaseIterable, Sendable { case left, right }

public struct ProfilePersonalization: Codable, Equatable, Sendable {
    public var birthDate: Date?
    public var gender: ProfileGender?
    public var wearWrist: WearWrist?
    public var hasRequiredDetails: Bool { birthDate != nil && gender != nil && wearWrist != nil }

    public func validatedForSetup() throws -> Self {
        guard hasRequiredDetails else {
            throw ProfilePersonalizationError.invalid("Choose your birth date, man or woman, and wearing wrist to continue.")
        }
        return try validated()
    }

    public var displayName: String
    public var username: String
    public var age: String
    public var whoopAge: String
    public var dayStreakOverride: Int?
    public init(displayName: String = "", username: String = "", age: String = "", whoopAge: String = "", dayStreakOverride: Int? = nil) {
        self.displayName = displayName; self.username = username; self.age = age
        self.whoopAge = whoopAge; self.dayStreakOverride = dayStreakOverride
    }
    public var isPersonalized: Bool {
        !displayName.isEmpty || !username.isEmpty || !age.isEmpty || !whoopAge.isEmpty || dayStreakOverride != nil
    }
    public func validated() throws -> Self {
        var result = self
        result.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.username.hasPrefix("@") { result.username.removeFirst() }
        guard result.displayName.count <= 100, result.username.count <= 80,
              !result.displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !result.username.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProfilePersonalizationError.invalid("Use a name up to 100 characters and a username up to 80 characters, without control characters.")
        }
        if let birthDate {
            guard birthDate.timeIntervalSince1970.isFinite,
                  birthDate >= DayCalendar.utc.date(from: DateComponents(year: 1, month: 1, day: 1))!,
                  DayCalendar.start(of: birthDate) <= DashboardDatePolicy.today() else {
                throw ProfilePersonalizationError.invalid("Choose a valid birth date that is today or earlier.")
            }
            result.birthDate = DayCalendar.start(of: birthDate)
            result.age = String(DayCalendar.utc.dateComponents([.year], from: result.birthDate!, to: DashboardDatePolicy.today()).year ?? 0)
        } else { result.age = try Self.ageText(age) }
        result.whoopAge = try Self.ageText(whoopAge)
        if let dayStreakOverride, dayStreakOverride < 0 {
            throw ProfilePersonalizationError.invalid("Your chosen day streak must be zero or greater.")
        }
        return result
    }
    public func initials(fallback: String = "AA") -> String {
        let words = displayName.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return fallback }
        return (words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined() : String(words[0].prefix(2))).uppercased()
    }
    private static func ageText(_ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return "" }
        guard text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || $0.value == 46 }),
              text.filter({ $0 == "." }).count <= 1, text.contains(where: { $0 != "." }) else {
            throw ProfilePersonalizationError.invalid("Enter an age of zero or greater, with an optional decimal point. There is no upper age limit.")
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0].drop(while: { $0 == "0" }))
        let fraction = parts.count == 2 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
        return (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
    }
}
public enum ProfilePersonalizationError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public struct ProfileRecord: Codable, Equatable, Sendable {
    public let value: Double
    public let date: Date
}
public struct ProfileHighlights: Codable, Equatable, Sendable {
    public var bestSleepPerformance: ProfileRecord?
    public var peakRecovery: ProfileRecord?
    public var peakStrain: ProfileRecord?
    public var lowestRecovery: ProfileRecord?
    public var lowestRestingHeartRate: ProfileRecord?
    public var highestRestingHeartRate: ProfileRecord?
    public var lowestHRV: ProfileRecord?
    public var highestHRV: ProfileRecord?
    public var maxHeartRate: ProfileRecord?
    public var longestSleepMinutes: ProfileRecord?
    public var savedDays = 0
    public var currentLoggedDayStreak = 0
    public var longestLoggedDayStreak = 0
    public var longestSleep70Streak = 0
    public var longestGreenRecoveryStreak = 0
    public var longestStrain10Streak = 0
    public init() { }
}
