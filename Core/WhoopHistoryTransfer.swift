import Foundation

/// The only projected physiological fields: independently documented, known layouts.
/// Unknown revisions remain in the complete raw batch and never borrow these offsets.
public struct WhoopHistoricalMeasurement: Equatable, Sendable {
    public let timestamp: Date
    public let heartRate: Double?
    public let rrIntervalsMilliseconds: [UInt16]

    public init?(record: WhoopHistoryRecord) {
        guard record.generation == .gen4 || (record.rawFrame.count > 1 && record.rawFrame[record.rawFrame.startIndex + 1] == 1) else { return nil }
        let bytes = [UInt8](record.rawPayload)
        let hrOffset: Int, rrOffset: Int
        switch (record.generation, record.rawRevision) {
        case (.gen4, 12), (.gen4, 24):
            guard bytes.count >= 89 else { return nil }
            hrOffset = 17; rrOffset = 18
        case (.maverick, 18), (.goose, 18):
            guard bytes.count >= 112 else { return nil }
            hrOffset = 14; rrOffset = 15
        default: return nil
        }
        guard let time = record.deviceTime else { return nil }
        timestamp = time.date
        let rawHR = bytes[hrOffset]
        heartRate = (25...230).contains(rawHR) ? Double(rawHR) : nil
        let count = Int(bytes[rrOffset])
        if count <= 4 {
            rrIntervalsMilliseconds = (0..<count).compactMap { index in
                let offset = rrOffset + 1 + index * 2
                guard offset + 1 < bytes.count else { return nil }
                let value = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                return (200...2500).contains(value) ? value : nil
            }
        } else { rrIntervalsMilliseconds = [] }
    }
}

public enum WhoopHistoryTransferError: Error, LocalizedError, Equatable {
    case unsupported, notReady, invalidMarker, countMismatch, tooLarge, unexpectedData, rejected, expired, wrongCommit
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "This device frame revision is not supported for history transfer."
        case .notReady: return "Wait for the device handshake before downloading history."
        case .invalidMarker: return "The device sent an incomplete history marker. No batch was acknowledged."
        case .countMismatch: return "The history batch count did not match. No batch was acknowledged; reconnect and try again."
        case .tooLarge: return "The history batch exceeded the supported buffer. No batch was acknowledged."
        case .unexpectedData: return "History arrived out of order. No unsaved batch was acknowledged."
        case .rejected: return "The tracker declined the history request."
        case .expired: return "The history transfer stopped responding. Unsaved data was not acknowledged."
        case .wrongCommit: return "The saved batch does not match the pending device batch."
        }
    }
}

public struct WhoopHistoryBatch: Codable, Equatable, Sendable {
    public let generation: WhoopGeneration
    public let token: Data
    public let packets: [Data]
    public let endMarker: Data
    public var measurements: [WhoopHistoricalMeasurement] {
        packets.compactMap { bytes in
            var decoder = WhoopFrameDecoder(generation: generation)
            guard let frame = decoder.append(bytes).first, let record = WhoopHistoryRecord(frame: frame) else { return nil }
            return WhoopHistoricalMeasurement(record: record)
        }
    }
}

/// Read-transfer flow control only. No clock writes, flash erase, force-trim,
/// bonding changes or firmware commands exist in this interface.
public struct WhoopHistoryTransfer {
    public enum State: Equatable { case idle, receiving, awaitingStorage, completed, failed }
    public private(set) var state: State = .idle
    public private(set) var receivedCount = 0
    public let generation: WhoopGeneration
    private var packets: [Data] = []
    private var bytes = 0
    private var pendingToken: Data?
    private var pendingEndMarker: Data?
    private var nextSequence: UInt8 = 128
    private var lastRequestSequence: UInt8?
    private var lastRequestOpcode: UInt8?
    public static let maximumBatchBytes = 8 * 1024 * 1024
    public static let maximumBatchPackets = 20_000
    public init(generation: WhoopGeneration) { self.generation = generation }

    public mutating func begin() throws -> Data {
        guard state == .idle || state == .failed || state == .completed else { throw WhoopHistoryTransferError.notReady }
        packets = []; bytes = 0; receivedCount = 0; pendingToken = nil; pendingEndMarker = nil
        let sequence = allocate(); lastRequestSequence = sequence; lastRequestOpcode = 0x16
        let command = try WhoopCommands.frame(.downloadHistory, generation: generation, sequence: sequence)
        state = .receiving
        return command
    }
    /// Returns a batch for durable storage. This method never returns an ACK.
    public mutating func receive(_ frame: WhoopFrame) throws -> WhoopHistoryBatch? {
        guard state == .receiving || state == .awaitingStorage else { return nil }
        guard frame.generation == generation else { state = .failed; throw WhoopHistoryTransferError.unsupported }
        if generation != .gen4, frame.bytes.count > 1, frame.bytes[frame.bytes.startIndex + 1] != 1 {
            state = .failed; throw WhoopHistoryTransferError.unsupported
        }
        if let response = WhoopCommandResponse(frame: frame), response.sequence == lastRequestSequence,
           response.opcode == lastRequestOpcode, response.result == .failure || response.result == .unsupported {
            state = .failed; throw WhoopHistoryTransferError.rejected
        }
        if Self.isHistoryPacket(frame.packetTypeCode) {
            guard state == .receiving else { state = .failed; throw WhoopHistoryTransferError.unexpectedData }
            guard packets.count < Self.maximumBatchPackets,
                  frame.bytes.count <= Self.maximumBatchBytes - bytes else { state = .failed; throw WhoopHistoryTransferError.tooLarge }
            packets.append(frame.bytes); bytes += frame.bytes.count; receivedCount += 1
            return nil
        }
        guard frame.packetType == .metadata else { return nil }
        let payload = [UInt8](frame.payload)
        guard payload.count >= 3 else { state = .failed; throw WhoopHistoryTransferError.invalidMarker }
        switch payload[2] {
        case 1:
            guard state == .receiving, packets.isEmpty else { state = .failed; throw WhoopHistoryTransferError.unexpectedData }
        case 2:
            guard state == .receiving, payload.count >= 21 else { state = .failed; throw WhoopHistoryTransferError.invalidMarker }
            let expected = UInt32(payload[9]) | UInt32(payload[10]) << 8 | UInt32(payload[11]) << 16 | UInt32(payload[12]) << 24
            guard expected == packets.count else { state = .failed; throw WhoopHistoryTransferError.countMismatch }
            let token = Data(payload[13..<21]); pendingToken = token; pendingEndMarker = frame.bytes; state = .awaitingStorage
            return WhoopHistoryBatch(generation: generation, token: token, packets: packets, endMarker: frame.bytes)
        case 3:
            guard state == .receiving, packets.isEmpty else { state = .failed; throw WhoopHistoryTransferError.unexpectedData }
            state = .completed
        default: break
        }
        return nil
    }
    /// Only a receipt issued by synchronized raw-archive storage can confirm this batch.
    public mutating func confirmDurablySaved(_ receipt: WhoopHistorySavedReceipt) throws -> Data {
        let batch = receipt.batch
        guard state == .awaitingStorage, batch.token == pendingToken, batch.generation == generation,
              batch.packets == packets, batch.endMarker == pendingEndMarker else { throw WhoopHistoryTransferError.wrongCommit }
        let sequence = allocate()
        let command = try WhoopCommands.frame(.acknowledgeHistory(batch.token), generation: generation, sequence: sequence)
        lastRequestSequence = sequence; lastRequestOpcode = 0x17
        packets = []; bytes = 0; pendingToken = nil; pendingEndMarker = nil; state = .receiving
        return command
    }
    public mutating func fail() { state = .failed }
    public static func isHistoryPacket(_ code: UInt8) -> Bool { [0x2f, 0x34, 0x35, 0x36, 0x37].contains(code) }
    private mutating func allocate() -> UInt8 { let value = nextSequence; nextSequence = nextSequence == 255 ? 128 : nextSequence + 1; return value }
}
