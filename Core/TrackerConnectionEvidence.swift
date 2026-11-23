import Foundation

/// A Bluetooth link is not proof of a working physiological stream.
/// Evaluate against the current clock so a disconnected or stalled stream never
/// keeps displaying an old reading as live.
public struct TrackerConnectionEvidence: Equatable, Sendable {
    public enum State: Equatable, Sendable { case disconnected, connecting, waiting, receiving, stale }
    public let state: State
    public let liveHeartRate: Double?

    public init(connected: Bool, connecting: Bool, heartRate: Double?, receivedAt: Date?, now: Date) {
        guard connected else {
            state = connecting ? .connecting : .disconnected
            liveHeartRate = nil
            return
        }
        guard let heartRate, heartRate.isFinite, (25...230).contains(heartRate), let receivedAt else {
            state = .waiting; liveHeartRate = nil; return
        }
        let age = now.timeIntervalSince(receivedAt)
        guard age.isFinite, (0...10).contains(age) else {
            state = .stale; liveHeartRate = nil; return
        }
        state = .receiving; liveHeartRate = heartRate
    }
}
