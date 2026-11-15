import Foundation
import ZIPFoundation

public enum ImportError: Error, LocalizedError, Equatable {
    case tooLarge, tooManyRows, unsupported, noData
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a file smaller than 10 MB."
        case .tooManyRows: return "This file has more than 100,000 heart-rate rows."
        case .unsupported: return "Choose a WHOOP export ZIP, WHOOP CSV, JSON archive or heart-rate CSV file."
        case .noData: return "The file contains no daily or heart-rate data."
        case .invalid(let detail): return detail
        }
    }
}

/// Reads WHOOP's downloaded CSV export locally. ZIP contents are never written to disk.
public enum WhoopExportImporter {
    private static let maximumExpandedBytes = 32 * 1024 * 1024
    private static let recognizedNames: Set<String> = ["physiological_cycles.csv", "sleeps.csv", "workouts.csv", "journal_entries.csv"]

    public static func recognizesCSV(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(4096), encoding: .utf8) else { return false }
        let header = normalize(String(text.prefix { $0 != "\n" && $0 != "\r" }))
        return header.contains("cyclestarttime") || header.contains("workoutstarttime")
    }

    public static func readZIP(_ data: Data) throws -> ImportedMeasurementArchive {
        guard data.count <= ImportReader.maximumBytes else { throw ImportError.tooLarge }
        let archive: Archive
        do { archive = try Archive(data: data, accessMode: .read) }
        catch { throw ImportError.invalid("This ZIP could not be opened. Choose the original, unencrypted WHOOP export ZIP.") }
        var files: [String: Data] = [:], expanded: UInt64 = 0, count = 0
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            guard count <= 256 else { throw ImportError.invalid("The ZIP contains too many files. Choose a single WHOOP data export.") }
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let parts = path.split(separator: "/")
            guard !path.hasPrefix("/"), !parts.contains(".."), !path.contains(":"), entry.type != .symlink else {
                throw ImportError.invalid("The ZIP contains an unsupported file path or symbolic link.")
            }
            guard entry.uncompressedSize <= UInt64(maximumExpandedBytes) - expanded else { throw ImportError.invalid("The ZIP expands beyond 32 MB. Export a shorter date range.") }
            expanded += entry.uncompressedSize
            guard entry.type == .file, let leaf = parts.last else { continue }
            let name = leaf.lowercased()
            guard recognizedNames.contains(name), !parts.contains("__MACOSX") else { continue }
            guard files[name] == nil else { throw ImportError.invalid("The ZIP contains duplicate \(name) files. Choose one WHOOP export.") }
            guard entry.uncompressedSize <= UInt64(ImportReader.maximumBytes) else { throw ImportError.tooLarge }
            var content = Data()
            do {
                let checksum = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                    try Task.checkCancellation()
                    guard chunk.count <= ImportReader.maximumBytes - content.count else { throw ImportError.tooLarge }
                    content.append(chunk)
                }
                guard checksum == entry.checksum, UInt64(content.count) == entry.uncompressedSize else {
                    throw ImportError.invalid("A CSV in the ZIP is damaged. Download a fresh WHOOP export.")
                }
            } catch let error as ImportError { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { throw ImportError.invalid("A CSV in the ZIP could not be read. Use an unencrypted WHOOP export.") }
            files[name] = content
        }
        guard !files.isEmpty else {
            throw ImportError.invalid("No WHOOP CSV files were found. The ZIP should contain physiological_cycles.csv, sleeps.csv or workouts.csv.")
        }
        return try importFiles(files)
    }

    public static func readCSV(_ data: Data) throws -> ImportedMeasurementArchive {
        let table = try Table(data)
        let name: String
        if table.has("Recovery score %") || table.has("Day Strain") { name = "physiological_cycles.csv" }
        else if table.has("Workout start time") { name = "workouts.csv" }
        else if table.has("Sleep onset") { name = "sleeps.csv" }
        else { throw ImportError.invalid("This WHOOP CSV does not contain cycle, sleep or workout measurements.") }
        return try importFiles([name: data])
    }

    private static func importFiles(_ files: [String: Data]) throws -> ImportedMeasurementArchive {
        var days: [Date: DailySnapshot] = [:], cycleStarts: [Date: Date] = [:]
        var activities: [UUID: ActivityRecord] = [:]
        var totalRows = 0
        let dates = Dates()
        func table(_ name: String) throws -> Table? {
            guard let data = files[name] else { return nil }
            let value = try Table(data)
            totalRows += value.rows.count
            guard totalRows <= ImportReader.maximumRows else { throw ImportError.tooManyRows }
            return value
        }
        if let cycles = try table("physiological_cycles.csv") {
            guard cycles.has("Cycle start time") else { throw ImportError.invalid("The cycle CSV is missing Cycle start time.") }
            for row in cycles.rows {
                try Task.checkCancellation()
                let start = try dates.date(cycles, row, ["Cycle start time"])
                let key = DayCalendar.start(of: start)
                if let previous = cycleStarts[key], previous != start {
                    throw ImportError.invalid("Two WHOOP cycles fall on the same UTC date. No records were saved; choose a shorter export range.")
                }
                var day = DailySnapshot.empty(on: key)
                day.recovery = try cycles.integer(row, ["Recovery score %", "Recovery score"])
                day.strain = try cycles.number(row, ["Day Strain", "Strain"])
                day.restingHeartRate = try cycles.number(row, ["Resting heart rate (bpm)"])
                day.hrv = try cycles.number(row, ["Heart rate variability (ms)", "HRV (ms)"])
                day.respiratoryRate = try cycles.number(row, ["Respiratory rate (rpm)"])
                day.energyKcal = try cycles.number(row, ["Energy burned (cal)", "Energy burned (kcal)"]) ?? 0
                try addSleep(cycles, row, to: &day)
                try ImportReader.validate(day)
                if let previous = days[key], previous != day { throw ImportError.invalid("The cycle CSV contains conflicting duplicate rows.") }
                days[key] = day; cycleStarts[key] = start
            }
        }
        if let sleeps = try table("sleeps.csv") {
            var primarySleeps: [Date: DailySnapshot] = [:]
            for row in sleeps.rows {
                try Task.checkCancellation()
                if let nap = sleeps.value(row, ["Nap"]), ["true", "yes", "1"].contains(nap.lowercased()) { continue }
                if let nap = sleeps.value(row, ["Nap"]), !["false", "no", "0"].contains(nap.lowercased()) {
                    throw ImportError.invalid("A sleep CSV row has an invalid Nap flag.")
                }
                let start = try dates.date(sleeps, row, ["Cycle start time"])
                let key = DayCalendar.start(of: start)
                var incoming = DailySnapshot.empty(on: key)
                try addSleep(sleeps, row, to: &incoming)
                try ImportReader.validate(incoming)
                if let previous = primarySleeps[key], previous != incoming { throw ImportError.invalid("The sleep CSV has conflicting primary sleeps on the same UTC day.") }
                primarySleeps[key] = incoming
                var day = days[key] ?? incoming
                if day.sleepPerformance == nil { day.sleepPerformance = incoming.sleepPerformance }
                if day.sleepMinutes == 0 { day.sleepMinutes = incoming.sleepMinutes }
                if day.sleepNeededMinutes == 0 { day.sleepNeededMinutes = incoming.sleepNeededMinutes }
                if day.respiratoryRate == nil { day.respiratoryRate = incoming.respiratoryRate }
                days[key] = day
            }
        }
        if let workouts = try table("workouts.csv") {
            for row in workouts.rows {
                try Task.checkCancellation()
                let start = try dates.date(workouts, row, ["Workout start time"], zones: ["Workout timezone", "Cycle timezone"])
                let end = try dates.date(workouts, row, ["Workout end time"], zones: ["Workout timezone", "Cycle timezone"])
                let seconds = end.timeIntervalSince(start)
                guard seconds > 0, seconds <= 86_400, let name = workouts.value(row, ["Activity name"]), name.count <= 80 else {
                    throw ImportError.invalid("A workout needs a name and a duration of more than zero and at most 24 hours.")
                }
                let strain = try workouts.number(row, ["Activity Strain", "Strain"])
                guard strain.map({ (0...21).contains($0) }) ?? true else { throw ImportError.invalid("A workout Strain is outside 0–21.") }
                let id = workoutID(start: start, end: end)
                let activity = ActivityRecord(id: id, start: start, durationMinutes: max(1, Int(seconds / 60)), name: name, strain: strain, strainIsEstimate: false)
                if let previous = activities[id], previous != activity { throw ImportError.invalid("The workout CSV contains conflicting duplicate sessions.") }
                activities[id] = activity
            }
        }
        guard !days.isEmpty || !activities.isEmpty else { throw ImportError.noData }
        var notices: [String] = []
        if files["journal_entries.csv"] != nil { notices.append("Journal answers are not part of this measurement import.") }
        return ImportedMeasurementArchive(days: days.values.sorted { $0.date < $1.date }, profile: nil,
            activities: activities.values.sorted { $0.start < $1.start }, notices: notices)
    }

    private static func addSleep(_ table: Table, _ row: [String], to day: inout DailySnapshot) throws {
        day.sleepPerformance = try table.integer(row, ["Sleep performance %"])
        day.sleepMinutes = try table.integer(row, ["Asleep duration (min)"]) ?? 0
        day.sleepNeededMinutes = try table.integer(row, ["Sleep need (min)"]) ?? 0
        if day.respiratoryRate == nil { day.respiratoryRate = try table.number(row, ["Respiratory rate (rpm)"]) }
    }

    // Stable, non-security identity for exports without provider workout IDs.
    private static func workoutID(start: Date, end: Date) -> UUID {
        let key = "whoop-csv|\(Int64((start.timeIntervalSince1970 * 1000).rounded()))|\(Int64((end.timeIntervalSince1970 * 1000).rounded()))"
        var first: UInt64 = 14_695_981_039_346_656_037, second: UInt64 = 7_809_847_782_465_536_322
        for byte in key.utf8 { first = (first ^ UInt64(byte)) &* 1_099_511_628_211; second = (second ^ UInt64(byte)) &* 1_099_511_628_211 }
        var bytes = (0..<8).map { UInt8(truncatingIfNeeded: first >> (56 - $0 * 8)) }
        bytes += (0..<8).map { UInt8(truncatingIfNeeded: second >> (56 - $0 * 8)) }
        bytes[6] = (bytes[6] & 15) | 128; bytes[8] = (bytes[8] & 63) | 128
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }

    private static func normalize(_ string: String) -> String { string.lowercased().filter { $0.isLetter || $0.isNumber } }
    private struct Table {
        let columns: [String: Int]
        let rows: [[String]]
        init(_ data: Data) throws {
            guard data.count <= ImportReader.maximumBytes, var text = String(data: data, encoding: .utf8) else { throw ImportError.invalid("WHOOP CSV files must be UTF-8 and smaller than 10 MB.") }
            if text.first == "\u{feff}" { text.removeFirst() }
            let parsed = try ImportReader.csvRows(text)
            guard let header = parsed.first else { throw ImportError.noData }
            let names = header.map(normalize)
            guard !names.contains(""), Set(names).count == names.count else { throw ImportError.invalid("The CSV has empty or duplicate column names.") }
            columns = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
            rows = Array(parsed.dropFirst())
            guard rows.allSatisfy({ $0.count == header.count }) else { throw ImportError.invalid("A WHOOP CSV row has the wrong number of columns.") }
        }
        func has(_ name: String) -> Bool { columns[normalize(name)] != nil }
        func value(_ row: [String], _ names: [String]) -> String? {
            for name in names {
                if let index = columns[normalize(name)] {
                    let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
            return nil
        }
        func number(_ row: [String], _ names: [String]) throws -> Double? {
            guard var text = value(row, names) else { return nil }
            if text.hasSuffix("%") { text.removeLast() }
            guard let value = Double(text), value.isFinite else { throw ImportError.invalid("The \(names[0]) column contains a non-numeric value.") }
            return value
        }
        func integer(_ row: [String], _ names: [String]) throws -> Int? {
            guard let value = try number(row, names) else { return nil }
            guard value >= 0, value <= 1_000_000 else { throw ImportError.invalid("The \(names[0]) column contains an invalid value.") }
            return Int(value.rounded())
        }
    }
    private final class Dates {
        private let iso = ImportReader.DateParser()
        private var formatters: [String: DateFormatter] = [:]
        func date(_ table: Table, _ row: [String], _ fields: [String], zones: [String] = ["Cycle timezone"]) throws -> Date {
            guard let text = table.value(row, fields) else { throw ImportError.invalid("The CSV is missing \(fields[0]).") }
            if let value = iso.parse(text, allowDayOnly: false) { return value }
            guard let label = table.value(row, zones), let zone = timezone(label) else {
                throw ImportError.invalid("Local CSV timestamps need a valid Cycle timezone, such as UTC+04:00.")
            }
            for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"] {
                let key = zone.identifier + pattern
                let formatter: DateFormatter
                if let cached = formatters[key] { formatter = cached }
                else {
                    formatter = DateFormatter(); formatter.calendar = DayCalendar.utc; formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = zone; formatter.dateFormat = pattern; formatter.isLenient = false; formatters[key] = formatter
                }
                if let value = formatter.date(from: text), formatter.string(from: value) == text { return value }
            }
            throw ImportError.invalid("The \(fields[0]) column contains an invalid timestamp.")
        }
        private func timezone(_ label: String) -> TimeZone? {
            if ["UTC", "GMT", "Z"].contains(label.uppercased()) { return TimeZone(secondsFromGMT: 0) }
            var offset = label.uppercased()
            if offset.hasPrefix("UTC") || offset.hasPrefix("GMT") { offset = String(offset.dropFirst(3)) }
            if let sign = offset.first, sign == "+" || sign == "-" {
                let digits = offset.dropFirst().replacingOccurrences(of: ":", with: "")
                guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)), hours <= 14, minutes < 60, hours != 14 || minutes == 0 else { return nil }
                return TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
            }
            return TimeZone(identifier: label)
        }
    }
}

public enum ImportReader {
    public static let maximumBytes = 10 * 1024 * 1024
    public static let maximumRows = 100_000

    public static func read(_ data: Data, filename: String) throws -> [DailySnapshot] {
        guard data.count <= maximumBytes else { throw ImportError.tooLarge }
        guard !data.isEmpty else { throw ImportError.noData }
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "csv":
            if WhoopExportImporter.recognizesCSV(data) { return try WhoopExportImporter.readCSV(data).days }
            return try readCSV(data)
        case "zip": return try WhoopExportImporter.readZIP(data).days
        case "json": return try readJSON(data)
        default: throw ImportError.unsupported
        }
    }

    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Paired date codec for app persistence as well as imported day archives.
    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let parser = DateParser()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = parser.parse(value, allowDayOnly: true) else {
                throw ImportError.invalid("Use ISO 8601 dates with an explicit timezone, such as 2026-11-08T08:00:00Z.")
            }
            return date
        }
        return decoder
    }

    private static func readJSON(_ data: Data) throws -> [DailySnapshot] {
        let decoder = jsonDecoder()
        let snapshots: [DailySnapshot]
        do {
            // A leading JSON array and a {"days": [...]} archive are both supported.
            if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
                snapshots = try decoder.decode([DailySnapshot].self, from: data)
            } else {
                snapshots = try decoder.decode(DayArchive.self, from: data).days
            }
        } catch let error as ImportError { throw error }
        catch {
            throw ImportError.invalid("The JSON archive is invalid. It must contain a days array with ISO 8601 dates and numeric metric values.")
        }
        guard !snapshots.isEmpty else { throw ImportError.noData }
        guard snapshots.count <= maximumRows else { throw ImportError.tooManyRows }
        var days = Set<Date>()
        var sampleCount = 0
        return try snapshots.map { original in
            var day = original
            day.date = DayCalendar.start(of: day.date)
            guard days.insert(day.date).inserted else {
                throw ImportError.invalid("The JSON archive contains more than one entry for the same UTC day.")
            }
            sampleCount += day.heartRates.count
            guard sampleCount <= maximumRows else { throw ImportError.tooManyRows }
            try validate(day)
            day.heartRates = try uniqueSamples(day.heartRates)
            // Preserve explicit example provenance when an example archive is exported/reimported.
            // Missing source defaults to imported in the model decoder; CSV is always imported.
            return day
        }.sorted { $0.date < $1.date }
    }

    private static func readCSV(_ data: Data) throws -> [DailySnapshot] {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ImportError.invalid("The CSV file must use UTF-8 text.")
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        let rows = try csvRows(text)
        guard let header = rows.first else { throw ImportError.noData }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(names).count == names.count,
              let timeIndex = names.firstIndex(of: "timestamp"),
              let rateIndex = names.firstIndex(of: "heart_rate") else {
            throw ImportError.invalid("CSV headers must include timestamp and heart_rate, with no duplicate column names.")
        }
        guard rows.count > 1 else { throw ImportError.noData }
        var samples: [HeartRateSample] = []
        let parser = DateParser()
        for (offset, row) in rows.dropFirst().enumerated() {
            let number = offset + 2
            guard row.count == header.count else {
                throw ImportError.invalid("CSV row \(number) has the wrong number of columns.")
            }
            let time = row[timeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let heartRate = row[rateIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = parser.parse(time, allowDayOnly: false),
                  let bpm = Double(heartRate), bpm.isFinite, bpm > 0, bpm <= 300 else {
                throw ImportError.invalid("CSV row \(number) needs an ISO 8601 timestamp with timezone and a heart_rate above 0 and at most 300.")
            }
            samples.append(.init(timestamp: date, bpm: bpm))
        }
        let grouped = Dictionary(grouping: try uniqueSamples(samples)) { DayCalendar.start(of: $0.timestamp) }
        return grouped.keys.sorted().map { date in
            var day = DailySnapshot.empty(on: date)
            day.heartRates = grouped[date] ?? []
            return day
        }
    }

    fileprivate final class DateParser {
        let fractional = ISO8601DateFormatter()
        let whole = ISO8601DateFormatter()
        let day = DateFormatter()
        init() {
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            whole.formatOptions = [.withInternetDateTime]
            day.calendar = DayCalendar.utc
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone(secondsFromGMT: 0)
            day.dateFormat = "yyyy-MM-dd"
            day.isLenient = false
        }
        func parse(_ string: String, allowDayOnly: Bool) -> Date? {
            if let date = fractional.date(from: string) { return date }
            if let date = whole.date(from: string) { return date }
            if allowDayOnly, string.count == 10,
               let date = day.date(from: string), day.string(from: date) == string { return date }
            return nil
        }
    }

    private static func uniqueSamples(_ samples: [HeartRateSample]) throws -> [HeartRateSample] {
        var seen: [Date: Double] = [:]
        for sample in samples {
            if let old = seen[sample.timestamp], old != sample.bpm {
                throw ImportError.invalid("The file has conflicting heart rates at the same timestamp.")
            }
            seen[sample.timestamp] = sample.bpm
        }
        return seen.keys.sorted().map { .init(timestamp: $0, bpm: seen[$0]!) }
    }

    fileprivate static func validate(_ day: DailySnapshot) throws {
        func optionalRange<T: Comparable>(_ value: T?, _ range: ClosedRange<T>) -> Bool {
            value.map(range.contains) ?? true
        }
        guard optionalRange(day.recovery, 0...100), optionalRange(day.sleepPerformance, 0...100),
              optionalRange(day.strain, 0.0...21.0),
              (0...1440).contains(day.sleepMinutes), (0...1440).contains(day.sleepNeededMinutes),
              optionalRange(day.restingHeartRate, 1.0...300.0), optionalRange(day.hrv, 0.0...1000.0),
              optionalRange(day.respiratoryRate, 0.0...100.0),
              (0...1_000_000).contains(day.steps), day.energyKcal.isFinite, day.energyKcal >= 0,
              day.energyKcal <= 100_000 else {
            throw ImportError.invalid("A daily metric is outside the supported range. Recovery and sleep scores must be 0–100, and strain must be 0–21.")
        }
        for sample in day.heartRates {
            guard sample.bpm.isFinite, sample.bpm > 0, sample.bpm <= 300,
                  DayCalendar.start(of: sample.timestamp) == day.date else {
                throw ImportError.invalid("Heart-rate samples must be valid and belong to their archive entry's UTC day.")
            }
        }
    }

    /// RFC4180-style fields, including doubled quotes and CRLF. No silent quote repair.
    fileprivate static func csvRows(_ text: String) throws -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false, index = 0
        func finishField() throws {
            row.append(field); field = ""; closedQuote = false
            if row.count > 64 { throw ImportError.invalid("CSV files may have at most 64 columns.") }
        }
        func finishRow() throws {
            try finishField()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            row = []
            if rows.count > maximumRows + 1 { throw ImportError.tooManyRows }
        }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(char) }
            } else if char == "," { try finishField() }
            else if char == "\n" || char == "\r" || char == "\r\n" {
                try finishRow()
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else if char == "\"" {
                guard field.isEmpty, !closedQuote else { throw ImportError.invalid("The CSV contains an unexpected quote.") }
                quoted = true
            } else {
                if closedQuote {
                    guard char == " " || char == "\t" else { throw ImportError.invalid("The CSV has text after a closing quote.") }
                } else { field.append(char) }
            }
            index += 1
        }
        guard !quoted else { throw ImportError.invalid("The CSV ends inside a quoted field.") }
        if !field.isEmpty || !row.isEmpty || closedQuote { try finishRow() }
        return rows
    }
}
