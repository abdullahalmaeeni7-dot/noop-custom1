import Foundation

public enum TrackerWearState: Equatable, Sendable {
    case unknown, onBody, offBody
}

/// Standard Bluetooth SIG Heart Rate Measurement (0x2A37).
public struct HeartRateMeasurement: Equatable, Sendable {
    public let bpm: Double?
    public let wearState: TrackerWearState

    public static func parse(_ data: Data) -> Self? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        let wide = flags & 0x01 != 0
        let heartRateEnd = wide ? 3 : 2
        let hasEnergy = flags & 0x08 != 0
        let hasRR = flags & 0x10 != 0
        let rrStart = heartRateEnd + (hasEnergy ? 2 : 0)
        guard flags & 0xE0 == 0, bytes.count >= rrStart else { return nil }
        let rrBytes = bytes.count - rrStart
        guard hasRR ? (rrBytes >= 2 && rrBytes.isMultiple(of: 2)) : rrBytes == 0 else { return nil }

        let value = Int(bytes[1]) | (wide ? Int(bytes[2]) << 8 : 0)
        // Bit 2 advertises support. Bit 1 alone has no contact meaning.
        let wear: TrackerWearState
        if flags & 0x04 == 0 { wear = .unknown }
        else { wear = flags & 0x02 == 0 ? .offBody : .onBody }
        return Self(bpm: wear != .offBody && (1...300).contains(value) ? Double(value) : nil,
                    wearState: wear)
    }

    public static func decode(_ data: Data) -> Double? { parse(data)?.bpm }
}
