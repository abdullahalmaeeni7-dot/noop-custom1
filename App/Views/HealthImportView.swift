import SwiftUI
import WHOOPCore

struct HealthImportView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthDataModel
    @State private var days = 14
    @State private var importTask: Task<Void, Never>?
    @State private var pendingDays: [DailySnapshot] = []
    @State private var saveError: String?
    @State private var savedMessage: String?

    var body: some View {
        SheetScaffold(title: "APPLE HEALTH") {
            VStack(alignment: .leading, spacing: 20) {
                WCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "heart.text.clipboard.fill")
                            .font(.system(size: 30)).foregroundStyle(WColor.green)
                        Text(L10n.text("Your health, together.")).font(WFont.number(29, bold: true)).foregroundStyle(.white)
                        Text(L10n.text("Bring measurements from Apple Health into your daily overview. You choose what to share, and this app never writes to Apple Health."))
                            .font(WFont.body(16)).foregroundStyle(WColor.muted)
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle(L10n.text("Automatically sync sleep"), isOn: Binding(
                            get: { health.automaticSleepEnabled },
                            set: { enabled in Task { await health.setAutomaticSleep(enabled, store: store) } }
                        )).disabled(!health.isAvailable || health.requestingSleepAccess)
                            .tint(WColor.green).accessibilityIdentifier("automaticSleepSync")
                        Text(L10n.text("Read sleep recorded in Apple Health for the past seven days, grouped by wake date. Allow Sleep access when prompted."))
                            .font(WFont.body(14)).foregroundStyle(WColor.muted)
                        if let syncStatus = health.sleepSyncStatus {
                            Text(L10n.text(syncStatus)).font(WFont.body(14)).foregroundStyle(WColor.muted)
                        }
                        if health.automaticSleepEnabled && health.backgroundSleepAvailable == false {
                            Text(L10n.text("Background delivery is unavailable. Sleep refreshes when you open the app."))
                                .font(WFont.body(14)).foregroundStyle(WColor.muted)
                        }
                        Divider()
                        SectionHeading(title: "Choose your days", subtitle: "Today so far and your recent days")
                        Picker(L10n.text("Date range"), selection: $days) {
                            Text(L10n.text("14 days")).tag(14)
                            Text(L10n.text("30 days")).tag(30)
                        }
                        .pickerStyle(.segmented)
                        .disabled(health.isLoading || !pendingDays.isEmpty)
                        Text(L10n.text("Includes steps, active energy, resting heart rate, respiratory rate, heart rate, and time asleep when available."))
                            .font(WFont.body(15)).foregroundStyle(WColor.muted)
                        Text(L10n.text("Sleep uses the local wake date. Other measurements use UTC days."))
                            .font(WFont.body(14)).foregroundStyle(WColor.muted)
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "Measurements, in context")
                        Text(L10n.text("Recovery, Sleep Performance, Strain, and sleep need are not provided by this import. They stay unavailable unless supplied in your day data."))
                        Text(L10n.text("Apple Health’s HRV uses SDNN. WHOOP’s HRV uses RMSSD. These are different measurements, so HRV isn’t included in this import."))
                        Text(L10n.text("Only readable days are saved. Importing updates available measurements on matching days. You can export or delete saved data from Your Data Files."))
                    }
                    .font(WFont.body(15)).foregroundStyle(WColor.muted)
                }
                if !health.isAvailable {
                    EmptyCard(symbol: "heart.slash", title: "Apple Health unavailable",
                              detail: "Open this app on an iPhone with Apple Health to import your measurements.")
                }
                if health.isLoading {
                    HStack(spacing: 12) {
                        ProgressView().tint(WColor.green)
                        Text(L10n.text(health.status)).font(WFont.body(15)).foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(L10n.text(health.status)).font(WFont.body(14)).foregroundStyle(WColor.muted)
                        .accessibilityIdentifier("healthImportStatus")
                }
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(WFont.body(15)).foregroundStyle(WColor.green)
                }
                if let message = saveError ?? health.error {
                    WCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text(saveError == nil ? "Couldn’t import measurements" : "Couldn’t save measurements"))
                                .font(WFont.label(13)).foregroundStyle(WColor.yellow)
                            Text(L10n.text(message)).font(WFont.body(15)).foregroundStyle(.white)
                        }
                    }
                    .accessibilityIdentifier("healthImportError")
                }
                if !pendingDays.isEmpty {
                    Button(L10n.text("RETRY SAVING")) { savePendingDays() }.buttonStyle(WButton())
                    Button(L10n.text("DISCARD UNSAVED IMPORT")) {
                        pendingDays = []
                        saveError = nil
                    }.buttonStyle(WButton(filled: false))
                } else if health.isLoading {
                    Button(L10n.text("CANCEL IMPORT")) { importTask?.cancel() }.buttonStyle(WButton(filled: false))
                } else {
                    Button(L10n.text(health.error == nil ? "IMPORT FROM APPLE HEALTH" : "TRY IMPORT AGAIN")) { beginImport() }
                        .buttonStyle(WButton())
                        .disabled(!health.isAvailable)
                        .opacity(health.isAvailable ? 1 : 0.45)
                        .accessibilityIdentifier("healthImportButton")
                }
                Text(L10n.text("Apple Health asks for access when you tap Import. If no measurements appear, check this app’s access in Apple Health. For privacy, Apple does not tell apps whether read access was denied."))
                    .font(WFont.body(13)).foregroundStyle(WColor.muted)
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private func beginImport() {
        savedMessage = nil
        saveError = nil
        importTask = Task { @MainActor in
            do {
                let measurements = try await health.fetch(days: days)
                try Task.checkCancellation()
                pendingDays = measurements
                savePendingDays()
            } catch {
                // HealthDataModel publishes actionable query/no-data errors.
                // Cancellation leaves existing saved measurements untouched.
            }
        }
    }

    private func savePendingDays() {
        do {
            try store.mergeMeasurements(pendingDays)
            savedMessage = "Saved measurements for \(pendingDays.count) \(pendingDays.count == 1 ? "day" : "days")."
            pendingDays = []
            saveError = nil
        } catch {
            saveError = "\(error.localizedDescription) Your import is ready to save. Tap Retry Saving to try again."
        }
    }
}
