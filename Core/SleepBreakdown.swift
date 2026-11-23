import Foundation

/// Provider-reported stages and scores. Missing fields stay absent.
public struct SleepBreakdown: Codable, Equatable, Sendable {
    public var awakeMinutes: Double?
    public var lightMinutes: Double?
    public var deepMinutes: Double?
    public var remMinutes: Double?
    public var inBedMinutes: Double?
    public var efficiencyPercent: Double?
    public var consistencyPercent: Double?
    public var debtMinutes: Double?
    public init(awakeMinutes: Double? = nil, lightMinutes: Double? = nil, deepMinutes: Double? = nil,
                remMinutes: Double? = nil, inBedMinutes: Double? = nil, efficiencyPercent: Double? = nil,
                consistencyPercent: Double? = nil, debtMinutes: Double? = nil) {
        self.awakeMinutes = awakeMinutes; self.lightMinutes = lightMinutes; self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes; self.inBedMinutes = inBedMinutes; self.efficiencyPercent = efficiencyPercent
        self.consistencyPercent = consistencyPercent; self.debtMinutes = debtMinutes
    }
    public func validated() throws {
        for value in [awakeMinutes, lightMinutes, deepMinutes, remMinutes, inBedMinutes, debtMinutes].compactMap({ $0 }) {
            guard value.isFinite, (0...1440).contains(value) else { throw ImportError.invalid("A sleep duration is outside 0–1440 minutes.") }
        }
        for value in [efficiencyPercent, consistencyPercent].compactMap({ $0 }) {
            guard value.isFinite, (0...100).contains(value) else { throw ImportError.invalid("A sleep percentage is outside 0–100.") }
        }
        let sum = [awakeMinutes, lightMinutes, deepMinutes, remMinutes].compactMap { $0 }.reduce(0, +)
        guard sum <= 1440 else { throw ImportError.invalid("Sleep stages exceed 24 hours.") }
        if let inBedMinutes {
            guard sum <= inBedMinutes + 1.0 / 60 else { throw ImportError.invalid("Sleep stages exceed recorded time in bed.") }
        }
    }
}
