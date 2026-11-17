import Foundation
import SwiftUI
import WHOOPCore

enum AppTab: String, CaseIterable, Identifiable {
    case home, sleep, recovery, strain, nutrition, menu, health, community, profile
    static let navigationTabs: [AppTab] = [.home, .health, .community, .menu]
    var id: String { rawValue }
    var title: String { self == .menu ? "More" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .sleep: return "moon"
        case .recovery: return "arrow.triangle.2.circlepath"
        case .strain: return "waveform.path.ecg"
        case .nutrition: return "fork.knife"
        case .health: return "heart"
        case .community: return "person.2"
        case .profile: return "person.crop.circle"
        case .menu: return "line.3.horizontal"
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var tab: AppTab = .home
    private(set) var trackerDataGeneration = UUID()
    @Published var selectedDate: Date
    @Published private(set) var days: [DailySnapshot] {
        didSet { dayIndex = days.enumerated().reduce(into: [:]) { $0[DayCalendar.start(of: $1.element.date)] = $1.offset } }
    }
    private var dayIndex: [Date: Int] = [:]
    @Published private(set) var isLoadingSavedData = false
    @Published private(set) var activities: [ActivityRecord]
    @Published private(set) var nutrition = NutritionData()
    @Published private(set) var profile = ProfilePersonalization()
    @Published private(set) var whoopAccountUserID: Int64?
    @Published var persistenceError: String?
    @Published private(set) var isImporting = false
    @Published private(set) var lastImportSummary: String?
    @Published private var journal: [JournalEntry]
    private let storageURL: URL
    private var storageWritable = true
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private struct SavedState: Codable, Sendable {
        let version: Int
        let days: [DailySnapshot]
        let activities: [ActivityRecord]
        let journal: [JournalEntry]
        let selectedDate: Date
        let whoopAccountUserID: Int64?
        let nutrition: NutritionData?
        let profile: ProfilePersonalization?
    }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = documents.appendingPathComponent("whoop-local-data.json")
        days = []; activities = []; journal = []; selectedDate = DayCalendar.start(of: Date())
        if FileManager.default.fileExists(atPath: storageURL.path) {
            isLoadingSavedData = true
            Task { await restoreFromDisk() }
        }
    }

    private struct DiskRestore: Sendable {
        var state: SavedState?
        var error: String?
        var writable = true
    }
    private nonisolated static func readSavedState(at url: URL) -> DiskRestore {
        do {
            let data = try Data(contentsOf: url)
            let state = try ImportReader.jsonDecoder().decode(SavedState.self, from: data)
            guard state.version == 1 else { throw ImportProblem.protectedFile }
            _ = try (state.profile ?? ProfilePersonalization()).validated()
            return DiskRestore(state: state)
        } catch {
            let backup = url.deletingLastPathComponent().appendingPathComponent("whoop-unreadable-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: url, to: backup)
                return DiskRestore(error: "Your saved file could not be opened. A separate copy has been kept on this iPhone. Import a backup to restore your days.")
            } catch {
                return DiskRestore(error: "Your saved file could not be opened or backed up. Saving is paused to protect it.", writable: false)
            }
        }
    }
    private func restoreFromDisk() async {
        let url = storageURL
        let restored = await Task.detached(priority: .userInitiated) { Self.readSavedState(at: url) }.value
        if let state = restored.state {
            let initial = LaunchDayData(savedDays: state.days, selectedDate: state.selectedDate)
            days = initial.days; activities = state.activities; journal = state.journal
            selectedDate = initial.selectedDate; whoopAccountUserID = state.whoopAccountUserID
            nutrition = state.nutrition ?? NutritionData(); profile = (try? (state.profile ?? ProfilePersonalization()).validated()) ?? ProfilePersonalization()
        }
        storageWritable = restored.writable; persistenceError = restored.error; isLoadingSavedData = false
    }

    var isExampleMode: Bool { !days.isEmpty && days.allSatisfy { $0.source == .example } }
    var selectedDay: DailySnapshot {
        dayIndex[Self.utc.startOfDay(for: selectedDate)].map { days[$0] } ??
        DailySnapshot(date: Self.utc.startOfDay(for: selectedDate), recovery: nil, strain: nil,
                      sleepPerformance: nil, sleepMinutes: 0, sleepNeededMinutes: 0,
                      restingHeartRate: nil, hrv: nil, respiratoryRate: nil, steps: 0,
                      energyKcal: 0, heartRates: [], source: .imported)
    }
    func hasJournal(on date: Date) -> Bool { journal.contains { Self.utc.isDate($0.date, inSameDayAs: date) } }
    var currentJournal: JournalEntry {
        journal.first { Self.utc.isDate($0.date, inSameDayAs: selectedDate) } ?? JournalEntry(date: selectedDate)
    }
    var dayActivities: [ActivityRecord] {
        activities.filter { Self.utc.isDate($0.start, inSameDayAs: selectedDate) }.sorted { $0.start > $1.start }
    }

    func moveDay(_ offset: Int) {
        if let date = Self.utc.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = date
        }
    }
    func saveJournal(_ entry: JournalEntry) {
        journal.removeAll { Self.utc.isDate($0.date, inSameDayAs: entry.date) }
        var limited = entry
        limited.note = String(entry.note.prefix(LocalBackupCodec.maximumNoteCharacters))
        journal.append(limited)
        persist()
    }
    func logActivity(name: String, minutes: Int) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let start = Self.utc.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        activities.append(ActivityRecord(start: start, durationMinutes: max(1, min(1440, minutes)),
                                         name: trimmed.isEmpty ? "Activity" : trimmed, strain: nil))
        persist()
    }
    func importFile(_ url: URL) async throws {
        guard !isImporting else { return }
        lastImportSummary = nil
        isImporting = true
        defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let imported = try await Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.int64Value > ImportReader.maximumBytes {
                throw WHOOPCore.ImportError.tooLarge
            }
            let data = try Data(contentsOf: url)
            guard !LocalBackupCodec.isBackup(data) else {
                throw WHOOPCore.ImportError.invalid("This is a complete backup. Choose Restore full backup in the Menu to restore its journal and activities too.")
            }
            return try MeasurementExport.readImport(data, filename: url.lastPathComponent)
        }.value
        guard !imported.days.isEmpty || !imported.activities.isEmpty || imported.profile != nil else { throw ImportProblem.empty }
        let before = stateSnapshot()
        if !imported.days.isEmpty {
            var merged = days.filter { $0.source == .imported }.reduce(into: [Date: DailySnapshot]()) { $0[Self.utc.startOfDay(for: $1.date)] = $1 }
            for day in imported.days {
                var day = day
                if day.trackerRecording == nil { day.trackerRecording = merged[day.date]?.trackerRecording }
                if let existing = merged[day.date],
                   URL(fileURLWithPath: url.lastPathComponent).pathExtension.lowercased() != "json" {
                    if day.heartRates.isEmpty { day.heartRates = existing.heartRates }
                    if day.steps == 0 { day.steps = existing.steps }
                    if day.recovery == nil { day.recovery = existing.recovery }
                    if day.strain == nil { day.strain = existing.strain }
                    if day.hrv == nil { day.hrv = existing.hrv }
                    if day.restingHeartRate == nil { day.restingHeartRate = existing.restingHeartRate }
                    if day.sleepPerformance == nil { day.sleepPerformance = existing.sleepPerformance }
                    if day.respiratoryRate == nil { day.respiratoryRate = existing.respiratoryRate }
                    if day.sleepMinutes == 0 { day.sleepMinutes = existing.sleepMinutes }
                    if day.sleepNeededMinutes == 0 { day.sleepNeededMinutes = existing.sleepNeededMinutes }
                    if day.energyKcal == 0 { day.energyKcal = existing.energyKcal }
                }
                merged[day.date] = day
            }
            days = merged.values.sorted { $0.date < $1.date }
            if let latest = imported.days.map(\.date).max() { selectedDate = latest }
        }
        for activity in imported.activities {
            if let index = activities.firstIndex(where: { $0.id == activity.id }) { activities[index] = activity }
            else { activities.append(activity) }
        }
        if imported.days.isEmpty, let latest = imported.activities.map(\.start).max() { selectedDate = Self.utc.startOfDay(for: latest) }
        if let personalized = imported.profile { profile = personalized }
        do { try writeState() } catch { restoreState(before); throw error }
        lastImportSummary = (["Imported \(imported.days.count) days and \(imported.activities.count) workouts."] + (imported.profile == nil ? [] : ["Profile preferences included."]) + imported.notices).joined(separator: " ")
    }

    /// Merge measurements without replacing supplied WHOOP day scores with local estimates.
    func mergeMeasurements(_ incoming: [DailySnapshot]) throws {
        let before = stateSnapshot()
        var merged = days.filter { $0.source != .example }
        for incomingDay in incoming {
            var day = incomingDay
            day.date = Self.utc.startOfDay(for: day.date)
            day.source = .imported
            if let index = merged.firstIndex(where: { $0.date == day.date }) {
                var previous = merged[index]
                if let value = day.restingHeartRate { previous.restingHeartRate = value }
                if let value = day.hrv { previous.hrv = value }
                if let value = day.respiratoryRate { previous.respiratoryRate = value }
                if day.steps > 0 { previous.steps = day.steps }
                if day.energyKcal > 0 { previous.energyKcal = day.energyKcal }
                if day.sleepMinutes > 0 { previous.sleepMinutes = day.sleepMinutes }
                var rates = Dictionary(uniqueKeysWithValues: previous.heartRates.map { ($0.timestamp, $0) })
                for sample in day.heartRates { rates[sample.timestamp] = sample }
                previous.heartRates = rates.values.sorted { $0.timestamp < $1.timestamp }
                merged[index] = previous
            } else { merged.append(day) }
        }
        days = merged.sorted { $0.date < $1.date }
        if let latest = incoming.map(\.date).max() { selectedDate = Self.utc.startOfDay(for: latest) }
        do { try writeState() } catch { restoreState(before); throw error }
    }

    func mergeAccount(_ account: WhoopAccountImport) throws {
        guard !account.days.isEmpty || !account.activities.isEmpty else { return }
        guard account.userID > 0 else { throw WhoopAccountError.invalidData("the account identity is missing.") }
        if let stored = whoopAccountUserID, stored != account.userID {
            throw WhoopAccountError.invalidData("saved data belongs to another WHOOP account. Save a full backup and clear local data before importing a different account.")
        }
        let before = stateSnapshot()
        var merged = days.filter { $0.source != .example }.reduce(into: [Date: DailySnapshot]()) { $0[Self.utc.startOfDay(for: $1.date)] = $1 }
        for supplied in account.days {
            var day = supplied
            if let previous = merged[supplied.date] {
                // The API supplies authoritative score states. Keep the two measurements
                // it does not provide, while allowing pending scores to clear stale ones.
                day.steps = previous.steps
                day.heartRates = previous.heartRates
                day.trackerRecording = previous.trackerRecording
            }
            merged[day.date] = day
        }
        days = merged.values.sorted { $0.date < $1.date }
        for activity in account.activities {
            if let index = activities.firstIndex(where: { $0.id == activity.id }) { activities[index] = activity }
            else { activities.append(activity) }
        }
        whoopAccountUserID = account.userID
        if let latest = account.days.map(\.date).max() { selectedDate = latest }
        do { try writeState() } catch { restoreState(before); throw error }
    }

    func updateNutrition(_ data: NutritionData) throws {
        try NutritionValidation.validate(data)
        let previous = nutrition
        nutrition = data
        do { try writeState() } catch { nutrition = previous; throw error }
    }

    func updateProfile(_ proposed: ProfilePersonalization) throws {
        guard !isImporting else { throw ProfilePersonalizationError.invalid("Wait for the current import to finish before saving your profile.") }
        let validated = try proposed.validated()
        let previous = profile
        profile = validated
        do { try writeState() } catch { profile = previous; throw error }
    }

    func completeSetup() throws {
        guard !isImporting else { throw ProfilePersonalizationError.invalid("Wait for your import to finish before opening Home.") }
        let before = stateSnapshot()
        let initial = LaunchDayData(savedDays: days, selectedDate: selectedDate)
        days = initial.days
        selectedDate = initial.selectedDate
        do { try writeState(); tab = .home }
        catch { restoreState(before); throw error }
    }

    func makeBackup() throws -> Data {
        try LocalBackupCodec.encode(LocalBackup(selectedDate: selectedDate, days: days, journal: journal, activities: activities, whoopAccountUserID: whoopAccountUserID, nutrition: nutrition, profile: profile))
    }
    func readBackupFile(_ url: URL) async throws -> LocalBackup {
        isImporting = true
        defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.int64Value > LocalBackupCodec.maximumBytes { throw LocalBackupError.tooLarge }
            return try LocalBackupCodec.decode(Data(contentsOf: url))
        }.value
    }
    /// The sheet supplies only a complete, validated LocalBackup from readBackupFile.
    func restoreBackup(_ backup: LocalBackup) throws {
        let restoredProfile = try (backup.profile ?? ProfilePersonalization()).validated()
        let before = stateSnapshot()
        days = backup.days.sorted { $0.date < $1.date }
        journal = backup.journal; activities = backup.activities
        selectedDate = backup.selectedDate
        whoopAccountUserID = backup.whoopAccountUserID
        nutrition = backup.nutrition ?? NutritionData()
        profile = restoredProfile
        do { try writeState() } catch { restoreState(before); throw error }
        trackerDataGeneration = UUID()
    }
    func deleteActivity(_ id: UUID) {
        activities.removeAll { $0.id == id }; persist()
    }
    func updateActivity(_ id: UUID, name: String, minutes: Int) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        activities[index].name = title.isEmpty ? "Activity" : title
        let duration = max(1, min(1440, minutes))
        if activities[index].durationMinutes != duration {
            activities[index].strain = nil; activities[index].strainIsEstimate = nil
        }
        activities[index].durationMinutes = duration
        persist()
    }
    func deleteJournal() {
        journal.removeAll { Self.utc.isDate($0.date, inSameDayAs: selectedDate) }; persist()
    }
    func saveRecordedWorkout(name: String, start: Date, durationSeconds: Int, heartRates: [HeartRateSample], localStrain: Double?) throws {
        let before = stateSnapshot()
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        activities.append(ActivityRecord(start: start, durationMinutes: max(1, min(1440, Int(ceil(Double(durationSeconds) / 60)))),
                                         name: title.isEmpty ? "Workout" : title,
                                         strain: localStrain, strainIsEstimate: localStrain == nil ? nil : true))
        let grouped = Dictionary(grouping: heartRates) { Self.utc.startOfDay(for: $0.timestamp) }
        selectedDate = Self.utc.startOfDay(for: start)
        do {
            if !grouped.isEmpty {
                let measurements = grouped.map { date, samples -> DailySnapshot in
                    var day = DailySnapshot.empty(on: date)
                    day.heartRates = samples.sorted { $0.timestamp < $1.timestamp }
                    return day
                }
                try mergeMeasurements(measurements)
            } else { try writeState() }
        } catch { restoreState(before); throw error }
    }
    /// One atomic save for automatically received tracker data; provider scores are untouched.
    func saveTrackerReadings(_ batches: [DailyTrackerBatch]) throws {
        guard !batches.isEmpty else { return }
        let before = stateSnapshot()
        var merged = days.filter { $0.source != .example }.reduce(into: [Date: DailySnapshot]()) { $0[$1.date] = $1 }
        for batch in batches {
            let day = merged[batch.date] ?? .empty(on: batch.date)
            merged[batch.date] = try day.applyingTrackerBatch(batch)
        }
        days = merged.values.sorted { $0.date < $1.date }
        do { try writeState() } catch { restoreState(before); throw error }
    }

    private func stateSnapshot() -> SavedState {
        SavedState(version: 1, days: days, activities: activities, journal: journal, selectedDate: selectedDate, whoopAccountUserID: whoopAccountUserID, nutrition: nutrition, profile: profile)
    }
    private func restoreState(_ state: SavedState) {
        days = state.days; activities = state.activities; journal = state.journal; selectedDate = state.selectedDate
        whoopAccountUserID = state.whoopAccountUserID
        nutrition = state.nutrition ?? NutritionData()
        profile = state.profile ?? ProfilePersonalization()
    }

    func restoreExamples() {
        days = ExampleData.days()
        selectedDate = days.last?.date ?? Self.utc.startOfDay(for: Date())
        activities = []
        journal = []
        whoopAccountUserID = nil
        persist()
    }
    func clearData() throws {
        let previous = SavedState(version: 1, days: days, activities: activities, journal: journal, selectedDate: selectedDate, whoopAccountUserID: whoopAccountUserID, nutrition: nutrition, profile: profile)
        days = []; activities = []; journal = []; whoopAccountUserID = nil; nutrition = NutritionData(); profile = ProfilePersonalization()
        selectedDate = Self.utc.startOfDay(for: Date())
        do { try writeState(); trackerDataGeneration = UUID() }
        catch {
            days = previous.days; activities = previous.activities; journal = previous.journal
            selectedDate = previous.selectedDate
            whoopAccountUserID = previous.whoopAccountUserID
            nutrition = previous.nutrition ?? NutritionData()
            profile = previous.profile ?? ProfilePersonalization()
            throw error
        }
    }
    private func persist() {
        do { try writeState() }
        catch { persistenceError = "Your changes are visible, but couldn’t be saved: \(error.localizedDescription)" }
    }
    private func writeState() throws {
        guard storageWritable, !isLoadingSavedData else { throw ImportProblem.protectedFile }
        let state = LocalBackup(selectedDate: selectedDate, days: days, journal: journal, activities: activities, whoopAccountUserID: whoopAccountUserID, nutrition: nutrition, profile: profile)
        let data = try LocalBackupCodec.encode(state)
        // Retain encryption while allowing BLE-delivered readings to save after lock.
        try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protectedURL = storageURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(values)
    }
    private enum ImportProblem: LocalizedError {
        case tooLarge, empty, protectedFile
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Choose a file smaller than 10 MB."
            case .empty: return "This file doesn’t contain any days or heart-rate samples."
            case .protectedFile: return "Saving is paused to protect an unreadable data file. Export the data you can see before closing the app."
            }
        }
    }
}
