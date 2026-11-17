import XCTest
import ZIPFoundation
@testable import WHOOPCore

final class WhoopHistoryTransferTests: XCTestCase {
    private struct Fixtures: Decodable {
        let records: [Record]
        let synthetic: [String: String]
        struct Record: Decodable {
            let name: String
            let generation: WhoopGeneration
            let frameHex: String
            let expectedHR: Int
            let expectedRR: [UInt16]
            let expectedUnixSeconds: Int
        }
    }
    private func fixtures() throws -> Fixtures {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/WhoopCapturedHistory.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }
    private func bytes(_ hex: String) -> Data {
        let chars = Array(hex); return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0+1]), radix: 16)! })
    }
    private func frame(_ data: Data, _ generation: WhoopGeneration) throws -> WhoopFrame {
        var decoder = WhoopFrameDecoder(generation: generation)
        return try XCTUnwrap(decoder.append(data).first)
    }
    private func marker(_ name: String, generation: WhoopGeneration = .gen4) throws -> WhoopFrame {
        try frame(bytes(XCTUnwrap(fixtures().synthetic[generation.rawValue + "_" + name])), generation)
    }
    private func pendingBatch(_ record: Fixtures.Record) throws -> (WhoopHistoryTransfer, WhoopHistoryBatch) {
        var transfer = WhoopHistoryTransfer(generation: record.generation)
        let request = try transfer.begin()
        XCTAssertEqual(request, try bytes(XCTUnwrap(fixtures().synthetic[record.generation.rawValue + "_request"])))
        _ = try transfer.receive(frame(bytes(record.frameHex), record.generation))
        let batch = try XCTUnwrap(transfer.receive(marker("end_1", generation: record.generation)))
        XCTAssertEqual(transfer.state, .awaitingStorage)
        return (transfer, batch)
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    func testCapturedGen4AndGen5PhysiologyAndFragmentedFrames() throws {
        for record in try fixtures().records {
            let data = bytes(record.frameHex)
            for boundary in 0...data.count {
                var decoder = WhoopFrameDecoder(generation: record.generation)
                let frames = decoder.append(Data(data.prefix(boundary))) + decoder.append(Data(data.dropFirst(boundary)))
                XCTAssertEqual(frames.count, 1)
                let history = try XCTUnwrap(WhoopHistoryRecord(frame: frames[0]))
                let value = try XCTUnwrap(history.measurement)
                XCTAssertEqual(value.heartRate, Double(record.expectedHR))
                XCTAssertEqual(value.rrIntervalsMilliseconds, record.expectedRR)
                XCTAssertEqual(Int(value.timestamp.timeIntervalSince1970), record.expectedUnixSeconds)
            }
        }
    }
    func testOnlySynchronizedSavedReceiptCanProduceAckAndComplete() async throws {
        for record in try fixtures().records {
            var (transfer, batch) = try pendingBatch(record)
            let store = DeviceHistoryArchiveStore(directory: try temporaryDirectory())
            let saved = try await store.save(batch, deviceIdentifier: UUID())
            let ack = try transfer.confirmDurablySaved(saved.receipt)
            XCTAssertEqual(ack, try bytes(XCTUnwrap(fixtures().synthetic[record.generation.rawValue + "_ack"])))
            XCTAssertEqual(transfer.state, .receiving)
            _ = try transfer.receive(marker("complete", generation: record.generation))
            XCTAssertEqual(transfer.state, .completed)
            XCTAssertEqual(saved.summary.packets, 1)
            XCTAssertEqual(saved.summary.heartRateRecords, 1)
            XCTAssertNil(saved.days.first?.recovery)
            XCTAssertNil(saved.days.first?.strain)
            XCTAssertNil(saved.days.first?.hrv)
            XCTAssertEqual(saved.days.first?.heartRates.first?.bpm, Double(record.expectedHR))
            XCTAssertEqual(Int(try XCTUnwrap(saved.days.first?.heartRates.first?.timestamp).timeIntervalSince1970), record.expectedUnixSeconds)
        }
    }
    func testDiskFailureLeavesBatchUnacknowledgedAndWrongReceiptRejected() async throws {
        let records = try fixtures().records
        var (transfer, _) = try pendingBatch(records[0])
        let (_, other) = try pendingBatch(records[1])
        let directory = try temporaryDirectory()
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocker)
        let blockedStore = DeviceHistoryArchiveStore(directory: blocker)
        let (_, batch) = try pendingBatch(records[0])
        do { _ = try await blockedStore.save(batch, deviceIdentifier: UUID()); XCTFail("Save should fail") } catch { }
        XCTAssertEqual(transfer.state, .awaitingStorage)
        let otherStore = DeviceHistoryArchiveStore(directory: directory.appendingPathComponent("other"))
        let receipt = try await otherStore.save(other, deviceIdentifier: UUID()).receipt
        XCTAssertThrowsError(try transfer.confirmDurablySaved(receipt))
        XCTAssertEqual(transfer.state, .awaitingStorage)
    }
    func testReplayIsIdempotentConflictCannotOverwriteAndRawZipRetainsBytes() async throws {
        let records = try fixtures().records
        let (_, batch) = try pendingBatch(records[0])
        let (_, conflicting) = try pendingBatch(records[1])
        let directory = try temporaryDirectory(), identifier = UUID()
        let store = DeviceHistoryArchiveStore(directory: directory)
        _ = try await store.save(batch, deviceIdentifier: identifier)
        for meta in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where meta.lastPathComponent.hasSuffix(".meta.json") {
            try FileManager.default.removeItem(at: meta)
        }
        let recovered = try await store.summary()
        XCTAssertEqual(recovered.batches, 1)
        XCTAssertEqual(recovered.heartRateRecords, 1)
        let replay = try await store.save(batch, deviceIdentifier: identifier)
        XCTAssertEqual(replay.summary.batches, 1)
        XCTAssertEqual(replay.summary.packets, 1)
        do { _ = try await store.save(conflicting, deviceIdentifier: identifier); XCTFail("Conflicting cursor must fail") }
        catch { XCTAssertTrue(error is DeviceHistoryArchiveError) }
        let zip = try await store.export(to: directory.appendingPathComponent("raw.zip"))
        let archive = try Archive(url: zip, accessMode: .read)
        let entry = try XCTUnwrap(archive.first { $0.path.hasSuffix(".history.json") })
        var data = Data(); _ = try archive.extract(entry) { data.append($0) }
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let storedBatch = try XCTUnwrap(envelope["batch"] as? [String: Any])
        let packets = try XCTUnwrap(storedBatch["packets"] as? [String])
        XCTAssertEqual(packets.compactMap { Data(base64Encoded: $0) }, batch.packets)
        let csvEntry = try XCTUnwrap(archive["decoded-heart-rate-and-beats.csv"])
        var csvData = Data(); _ = try archive.extract(csvEntry) { csvData.append($0) }
        let csv = try XCTUnwrap(String(data: csvData, encoding: .utf8))
        XCTAssertTrue(csv.contains("device_time_utc,clock_plausible,heart_rate_bpm,rr_intervals_ms"))
        XCTAssertTrue(csv.contains(",true,\(records[0].expectedHR),"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }
    func testIncompleteCountsShortMarkersAndUnknownEnvelopeNeverAllowCommit() throws {
        let record = try XCTUnwrap(fixtures().records.first)
        for bad in ["end_2", "short_end", "complete"] {
            var transfer = WhoopHistoryTransfer(generation: .gen4); _ = try transfer.begin()
            _ = try transfer.receive(frame(bytes(record.frameHex), .gen4))
            XCTAssertThrowsError(try transfer.receive(marker(bad)))
            XCTAssertEqual(transfer.state, .failed)
        }
        var future = WhoopHistoryTransfer(generation: .maverick); _ = try future.begin()
        let unsupported = try frame(bytes(XCTUnwrap(fixtures().synthetic["gen5_future_envelope"])), .maverick)
        XCTAssertNil(WhoopHistoryRecord(frame: unsupported)?.measurement)
        XCTAssertThrowsError(try future.receive(unsupported))
        XCTAssertEqual(future.state, .failed)
    }
    func testUnknownRecordAndSidebandAreRetainedWithoutInventedMeasurements() async throws {
        var transfer = WhoopHistoryTransfer(generation: .gen4); _ = try transfer.begin()
        let first = try marker("unknown_record"), second = try marker("side_record")
        _ = try transfer.receive(first); _ = try transfer.receive(second)
        let batch = try XCTUnwrap(transfer.receive(marker("end_2")))
        XCTAssertTrue(batch.measurements.isEmpty)
        let saved = try await DeviceHistoryArchiveStore(directory: temporaryDirectory()).save(batch, deviceIdentifier: UUID())
        XCTAssertEqual(saved.summary.packets, 2)
        XCTAssertEqual(saved.summary.heartRateRecords, 0)
        XCTAssertTrue(saved.days.isEmpty)
        _ = try transfer.confirmDurablySaved(saved.receipt)
    }
    func testPacketBufferIsBoundedAndInvalidAckTokenCannotBeEncoded() throws {
        var transfer = WhoopHistoryTransfer(generation: .gen4); _ = try transfer.begin()
        let packet = try marker("unknown_record")
        for _ in 0..<WhoopHistoryTransfer.maximumBatchPackets { _ = try transfer.receive(packet) }
        XCTAssertThrowsError(try transfer.receive(packet))
        XCTAssertEqual(transfer.state, .failed)
        XCTAssertThrowsError(try WhoopCommands.frame(.acknowledgeHistory(Data([1])), generation: .gen4, sequence: 1))
    }
}
