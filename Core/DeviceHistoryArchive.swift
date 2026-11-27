import Foundation
import ZIPFoundation

public struct DeviceHistoryArchiveSummary: Codable, Equatable, Sendable {
    public var batches = 0
    public var packets = 0
    public var heartRateRecords = 0
    public var rrIntervals = 0
    public var latestMeasurement: Date?
    public init() {}
}
public struct WhoopHistorySavedReceipt: Sendable {
    let batch: WhoopHistoryBatch
    init(_ batch: WhoopHistoryBatch) { self.batch = batch }
}
public struct DeviceHistorySave: Sendable {
    public let receipt: WhoopHistorySavedReceipt
    public let days: [DailySnapshot]
    public let summary: DeviceHistoryArchiveSummary
}
public enum DeviceHistoryArchiveError: Error, LocalizedError {
    case conflictingBatch, invalidBatch
    public var errorDescription: String? {
        switch self {
        case .conflictingBatch: return "The tracker reused a batch token with different data. The saved archive was protected and no acknowledgement was sent."
        case .invalidBatch: return "The device batch failed integrity validation. No acknowledgement was sent."
        }
    }
}

/// Lossless device batches are stored independently of the bounded dashboard JSON.
/// No acknowledgement is permitted until this actor returns from a synchronized save.
public actor DeviceHistoryArchiveStore {
    private let directory: URL
    private struct Envelope: Codable, Equatable {
        let format: String
        let version: Int
        let deviceIdentifier: UUID
        let batch: WhoopHistoryBatch
    }
    public init(directory: URL) { self.directory = directory }

    public func save(_ batch: WhoopHistoryBatch, deviceIdentifier: UUID, now: Date = Date()) throws -> DeviceHistorySave {
        guard batch.token.count == 8, batch.packets.count <= WhoopHistoryTransfer.maximumBatchPackets,
              batch.packets.reduce(0, { $0 + $1.count }) <= WhoopHistoryTransfer.maximumBatchBytes else { throw DeviceHistoryArchiveError.invalidBatch }
        var transfer = WhoopHistoryTransfer(generation: batch.generation)
        _ = try transfer.begin()
        for bytes in batch.packets {
            let frame = try Self.checkedFrame(bytes, generation: batch.generation)
            guard WhoopHistoryTransfer.isHistoryPacket(frame.packetTypeCode) else { throw DeviceHistoryArchiveError.invalidBatch }
            _ = try transfer.receive(frame)
        }
        let marker = try Self.checkedFrame(batch.endMarker, generation: batch.generation)
        guard try transfer.receive(marker) == batch else { throw DeviceHistoryArchiveError.invalidBatch }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = deviceIdentifier.uuidString.lowercased() + "_" + batch.generation.rawValue + "_" + batch.token.map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent(stem + ".history.json")
        let manifest = directory.appendingPathComponent(stem + ".meta.json")
        let envelope = Envelope(format: "WHOOP_DEVICE_HISTORY", version: 1, deviceIdentifier: deviceIdentifier, batch: batch)
        let encoder = ImportReader.jsonEncoder()
        let encoded = try encoder.encode(envelope)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try ImportReader.jsonDecoder().decode(Envelope.self, from: Data(contentsOf: url)) == envelope else { throw DeviceHistoryArchiveError.conflictingBatch }
        } else {
            try Self.durableWrite(encoded, to: url)
        }
        try Self.synchronize(url)
        // A replay may follow a crash between the raw save and its small manifest.
        // Recreating the manifest is idempotent; an existing raw batch is never overwritten.
        let measurements = batch.measurements.filter {
            $0.timestamp >= Date(timeIntervalSince1970: 946_684_800) && $0.timestamp <= now.addingTimeInterval(300)
        }
        let meta = Self.summarize(batch, measurements: measurements)
        try Self.durableWrite(encoder.encode(meta), to: manifest)
        return DeviceHistorySave(receipt: WhoopHistorySavedReceipt(batch), days: Self.snapshots(measurements), summary: try summary())
    }

    /// Rebuild projections from already saved raw batches after installing an update.
    public func savedMeasurements(now: Date = Date()) throws -> [DailySnapshot] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var measurements: [WhoopHistoricalMeasurement] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasSuffix(".history.json") {
            let envelope = try ImportReader.jsonDecoder().decode(Envelope.self, from: Data(contentsOf: file))
            guard envelope.format == "WHOOP_DEVICE_HISTORY", envelope.version == 1 else { throw DeviceHistoryArchiveError.invalidBatch }
            measurements += envelope.batch.measurements.filter {
                $0.timestamp >= now.addingTimeInterval(-8 * 86_400) && $0.timestamp <= now
            }
        }
        return Self.snapshots(measurements)
    }

    private static func snapshots(_ measurements: [WhoopHistoricalMeasurement]) -> [DailySnapshot] {
        var days: [Date: [Int64: HeartRateSample]] = [:]
        for measurement in measurements {
            guard let bpm = measurement.heartRate else { continue }
            let sample = HeartRateSample(timestamp: measurement.timestamp, bpm: bpm, trackerRecorded: true)
            days[DayCalendar.start(of: sample.timestamp), default: [:]][Int64(sample.timestamp.timeIntervalSince1970 / 60)] = sample
        }
        return days.keys.sorted().map { date in
            var day = DailySnapshot.empty(on: date)
            day.heartRates = days[date]!.values.sorted { $0.timestamp < $1.timestamp }
            return day
        }
    }
    public func summary() throws -> DeviceHistoryArchiveSummary {
        guard FileManager.default.fileExists(atPath: directory.path) else { return .init() }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var total = DeviceHistoryArchiveSummary()
        for raw in files where raw.lastPathComponent.hasSuffix(".history.json") {
            let manifest = directory.appendingPathComponent(raw.lastPathComponent.replacingOccurrences(of: ".history.json", with: ".meta.json"))
            let value: DeviceHistoryArchiveSummary
            if let data = try? Data(contentsOf: manifest), let cached = try? ImportReader.jsonDecoder().decode(DeviceHistoryArchiveSummary.self, from: data) {
                value = cached
            } else {
                // A crash after raw-file sync but before manifest commit must not
                // hide the preserved data or its export action on the next launch.
                let envelope = try ImportReader.jsonDecoder().decode(Envelope.self, from: Data(contentsOf: raw))
                guard envelope.format == "WHOOP_DEVICE_HISTORY", envelope.version == 1 else { throw DeviceHistoryArchiveError.invalidBatch }
                let now = Date()
                value = Self.summarize(envelope.batch, measurements: envelope.batch.measurements.filter {
                    $0.timestamp >= Date(timeIntervalSince1970: 946_684_800) && $0.timestamp <= now.addingTimeInterval(300)
                })
            }
            total.batches += value.batches; total.packets += value.packets
            total.heartRateRecords += value.heartRateRecords; total.rrIntervals += value.rrIntervals
            if let date = value.latestMeasurement { total.latestMeasurement = max(total.latestMeasurement ?? date, date) }
        }
        return total
    }
    /// Streaming ZIP creation keeps a large archive out of the UI actor's memory.
    public func export(to output: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.lastPathComponent.hasSuffix(".history.json") || $0.lastPathComponent.hasSuffix(".meta.json") }
        guard !files.isEmpty else { throw DeviceHistoryArchiveError.invalidBatch }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let csv = staging.appendingPathComponent("decoded-heart-rate-and-beats.csv")
        try Self.durableWrite(Data("device_id,batch_token,generation,record_counter,device_time_utc,clock_plausible,heart_rate_bpm,rr_intervals_ms\n".utf8), to: csv)
        let writer = try FileHandle(forWritingTo: csv)
        defer { try? writer.close() }
        _ = try writer.seekToEnd()
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let now = Date()
        for file in files where file.lastPathComponent.hasSuffix(".history.json") {
            let envelope = try ImportReader.jsonDecoder().decode(Envelope.self, from: Data(contentsOf: file))
            for packet in envelope.batch.packets {
                let frame = try Self.checkedFrame(packet, generation: envelope.batch.generation)
                guard let record = WhoopHistoryRecord(frame: frame), let measurement = record.measurement else { continue }
                let plausible = measurement.timestamp >= Date(timeIntervalSince1970: 946_684_800) && measurement.timestamp <= now.addingTimeInterval(300)
                let cursor: String = envelope.batch.token.map { String(format: "%02x", $0) }.joined()
                let counter: String = record.packetCounter.map { String($0) } ?? ""
                let hr: String = measurement.heartRate.map { String(Int($0)) } ?? ""
                let rr: String = measurement.rrIntervalsMilliseconds.map { String($0) }.joined(separator: ";")
                let fields: [String] = [envelope.deviceIdentifier.uuidString, cursor,
                                        envelope.batch.generation.rawValue, counter,
                                        formatter.string(from: measurement.timestamp), plausible ? "true" : "false", hr, rr]
                let row = fields.joined(separator: ",") + "\n"
                try writer.write(contentsOf: Data(row.utf8))
            }
        }
        try writer.synchronize(); try writer.close()
        let readme = "Original tracker packet batches are retained unchanged in the history JSON files. The CSV contains only supported decoded heart-rate and beat-interval records, with original device-clock times; clock_plausible is a range check, not a corrected time. Unknown formats remain in the original packet bytes. No official Recovery, Sleep or Strain score is generated. This raw tracker archive is separate from the app JSON backup.\n"
        try Self.durableWrite(Data(readme.utf8), to: staging.appendingPathComponent("README.txt"))
        let archive = try Archive(url: output, accessMode: .create)
        do {
            for file in files {
                let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { continue }
                try archive.addEntry(with: file.lastPathComponent, relativeTo: directory, compressionMethod: .deflate)
            }
            try archive.addEntry(with: "decoded-heart-rate-and-beats.csv", relativeTo: staging, compressionMethod: .deflate)
            try archive.addEntry(with: "README.txt", relativeTo: staging, compressionMethod: .deflate)
        } catch { try? FileManager.default.removeItem(at: output); throw error }
        return output
    }
    private static func summarize(_ batch: WhoopHistoryBatch, measurements: [WhoopHistoricalMeasurement]) -> DeviceHistoryArchiveSummary {
        var value = DeviceHistoryArchiveSummary(); value.batches = 1; value.packets = batch.packets.count
        value.heartRateRecords = measurements.filter { $0.heartRate != nil }.count
        value.rrIntervals = measurements.reduce(0) { $0 + $1.rrIntervalsMilliseconds.count }
        value.latestMeasurement = measurements.map(\.timestamp).max()
        return value
    }
    private static func checkedFrame(_ data: Data, generation: WhoopGeneration) throws -> WhoopFrame {
        var decoder = WhoopFrameDecoder(generation: generation)
        let frames = decoder.append(data)
        guard frames.count == 1, frames[0].bytes == data, decoder.bufferedByteCount == 0 else { throw DeviceHistoryArchiveError.invalidBatch }
        return frames[0]
    }
    private static func durableWrite(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        try synchronize(url)
        var protectedURL = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }
    private static func synchronize(_ url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        do { try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
    }
}
