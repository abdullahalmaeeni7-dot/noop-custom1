import SwiftUI
import WHOOPCore

struct AccountView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var account: AccountModel
    @State private var days = 30
    @State private var endingDay = Date()
    @State private var action: Task<Void, Never>?
    @State private var pending: WhoopAccountImport?
    @State private var saveError: String?
    @State private var savedMessage: String?
    @State private var confirmForget = false

    var body: some View {
        SheetScaffold(title: "WHOOP ACCOUNT") {
            VStack(alignment: .leading, spacing: 20) {
                WCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 32)).foregroundStyle(WColor.green)
                        Text(L10n.text(account.displayName.map { "Welcome, \($0)." } ?? "Your WHOOP, connected."))
                            .font(WFont.number(28, bold: true)).foregroundStyle(.white)
                        Text(L10n.text("Bring your account-supplied Recovery, Strain, Sleep Performance, and activities into this app."))
                            .font(WFont.body(16)).foregroundStyle(WColor.muted)
                        Label(L10n.text(account.isLinked ? "Account connected" : "Account not connected"),
                              systemImage: account.isLinked ? "checkmark.circle.fill" : "person.crop.circle")
                            .font(WFont.body(14)).foregroundStyle(account.isLinked ? WColor.green : WColor.muted)
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "Your secure bridge")
                        Text(L10n.text("Enter the HTTPS address of your configured WHOOP bridge. It stores the OAuth credentials and connects to WHOOP on your behalf."))
                            .font(WFont.body(15)).foregroundStyle(WColor.muted)
                        TextField("https://your-bridge.example", text: $account.bridgeURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .font(WFont.body(16)).foregroundStyle(.white)
                            .padding(12).background(WColor.background).clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled(account.isBusy || account.isLinked)
                            .accessibilityIdentifier("accountBridgeURL")
                        Text(L10n.text("Connect opens WHOOP’s official authorization page. This app never asks for your WHOOP password. A bridge with valid WHOOP OAuth configuration is required."))
                            .font(WFont.body(13)).foregroundStyle(WColor.muted)
                    }
                }
                if account.isLinked {
                    WCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "Choose your days")
                            Picker(L10n.text("Date range"), selection: $days) {
                                Text(L10n.text("14 days")).tag(14)
                                Text(L10n.text("30 days")).tag(30)
                            }.pickerStyle(.segmented).disabled(account.isBusy || pending != nil)
                            DatePicker("Ending on", selection: $endingDay,
                                       in: Date(timeIntervalSince1970: 946_684_800)...Date(), displayedComponents: .date)
                                .environment(\.calendar, DayCalendar.utc)
                                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                                .font(WFont.body(16)).foregroundStyle(.white).tint(WColor.green)
                                .disabled(account.isBusy || pending != nil)
                                .accessibilityIdentifier("accountEndingDay")
                            Text(L10n.text("Dates use UTC. The range includes your ending day; today includes data available so far. Choose an earlier date to sync historical records."))
                                .font(WFont.body(14)).foregroundStyle(WColor.muted)
                            Text(L10n.text("Includes available account scores and scored sleep measurements. Missing scores stay unavailable. Activities retain WHOOP’s supplied Strain; no heart-rate stream is created."))
                                .font(WFont.body(15)).foregroundStyle(WColor.muted)
                        }
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "Account data, in context")
                        Text(L10n.text("Each WHOOP cycle is placed on the UTC date when that cycle started. This can differ from the day shown in WHOOP. If two cycles share one UTC date, the import stops so neither score is silently lost."))
                        Text(L10n.text("Recovery and Sleep Performance come from your account; this app does not calculate them. Sleep stages and need components are converted to minutes. Percentage scores use whole-number display precision."))
                        Text(L10n.text("WHOOP’s API does not supply steps or a continuous heart-rate trace here. The import adds no steps or heart-rate samples. Cycle energy includes the energy reported by WHOOP for that cycle."))
                        Text(L10n.text("Sync saves your imported days and activities locally. Your chosen bridge can access the WHOOP data you authorize. Disconnect removes its account session; saved imports can be deleted from Your Data Files."))
                    }.font(WFont.body(14)).foregroundStyle(WColor.muted)
                }
                if account.isBusy {
                    HStack(spacing: 12) {
                        ProgressView().tint(WColor.green)
                        Text(L10n.text(account.status)).font(WFont.body(15)).foregroundStyle(.white)
                    }.accessibilityElement(children: .combine)
                } else {
                    Text(L10n.text(account.status)).font(WFont.body(14)).foregroundStyle(WColor.muted)
                        .accessibilityIdentifier("accountStatus")
                }
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill").font(WFont.body(15)).foregroundStyle(WColor.green)
                }
                if let message = saveError ?? account.error {
                    WCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text(saveError == nil ? "Couldn’t finish account action" : "Couldn’t save account data"))
                                .font(WFont.label(13)).foregroundStyle(WColor.yellow)
                            Text(L10n.text(message)).font(WFont.body(15)).foregroundStyle(.white)
                        }
                    }.accessibilityIdentifier("accountError")
                }
                if pending != nil {
                    Button(L10n.text("RETRY SAVING")) { savePending() }.buttonStyle(WButton())
                    Button(L10n.text("DISCARD UNSAVED IMPORT")) { pending = nil; saveError = nil }.buttonStyle(WButton(filled: false))
                } else if account.isBusy {
                    Button(L10n.text("CANCEL")) { action?.cancel(); account.cancel() }.buttonStyle(WButton(filled: false))
                } else if account.isLinked {
                    Button(L10n.text("SYNC WHOOP ACCOUNT")) { sync() }.buttonStyle(WButton())
                        .accessibilityIdentifier("accountSyncButton")
                    Button(L10n.text("DISCONNECT ACCOUNT")) {
                        savedMessage = nil
                        action = Task { await account.disconnect() }
                    }.buttonStyle(WButton(filled: false))
                    Button(L10n.text("Forget connection on this iPhone"), role: .destructive) { confirmForget = true }
                        .font(WFont.body(14)).frame(maxWidth: .infinity)
                } else {
                    Button(L10n.text("CONNECT WHOOP ACCOUNT")) {
                        savedMessage = nil; saveError = nil
                        action = Task { try? await account.connect() }
                    }.buttonStyle(WButton()).accessibilityIdentifier("accountConnectButton")
                }
            }
        }
        .confirmationDialog(L10n.text("Forget this iPhone’s account connection?"), isPresented: $confirmForget, titleVisibility: .visible) {
            Button(L10n.text("Forget local connection"), role: .destructive) {
                do { try account.forgetLocalConnection(); savedMessage = nil }
                catch { saveError = error.localizedDescription }
            }
        } message: {
            Text(L10n.text("This removes the saved sign-in on this iPhone and attempts to disconnect the bridge. If the server is offline, its stored session and WHOOP grant may remain. Your imported measurements are kept."))
        }
        .onDisappear { action?.cancel(); account.cancel() }
    }

    private func sync() {
        savedMessage = nil; saveError = nil
        action = Task { @MainActor in
            do {
                let result = try await account.fetch(days: days, ending: endingDay)
                try Task.checkCancellation()
                if result.days.isEmpty && result.activities.isEmpty {
                    savedMessage = "Your account returned no cycles or activities in this range."
                    return
                }
                pending = result
                savePending()
            } catch { /* AccountModel publishes redacted, actionable errors. */ }
        }
    }

    private func savePending() {
        guard let result = pending else { return }
        do {
            try store.mergeAccount(result)
            savedMessage = "Saved \(result.days.count) days and \(result.activities.count) activities from your WHOOP account."
            pending = nil; saveError = nil
        } catch {
            saveError = "\(error.localizedDescription) Your import is ready. Retry Saving to try again."
        }
    }
}
