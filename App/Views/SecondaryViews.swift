import SwiftUI
import WHOOPCore

struct CommunityView: View {
    @EnvironmentObject private var store: AppStore
    let openActivity: () -> Void
    let importData: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.text("Build Your Community")).font(WFont.body(26).weight(.semibold))
            Text(L10n.text("Better, together.")).font(WFont.body(16)).foregroundStyle(WColor.muted)
            WCard {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "person.2.circle").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(WColor.blue)
                    Text(L10n.text("YOUR TRAINING\nSTARTS HERE.")).font(WFont.number(31, bold: true))
                    Text(L10n.text("This local edition does not connect to WHOOP teams, followers or leaderboards. Your own activity log stays available below."))
                        .font(WFont.body(16)).foregroundStyle(WColor.muted)
                    Button(L10n.text("LOG AN ACTIVITY"), action: openActivity).buttonStyle(WButton())
                }
            }
            SectionHeading(title: "Your recent sessions", subtitle: "Saved on this iPhone")
            if store.activities.isEmpty {
                EmptyCard(symbol: "figure.run", title: "Start your training log", detail: "Add a session to keep a record of your movement.")
            } else {
                ForEach(Array(store.activities.sorted { $0.start > $1.start }.prefix(12))) { activity in ActivityRow(activity: activity) }
            }
            Button(L10n.text("IMPORT YOUR DAY DATA"), action: importData).buttonStyle(WButton(filled: false))
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    let openJournal: () -> Void
    let openDevice: () -> Void
    let exportData: () -> Void
    @State private var personalizing = false
    var body: some View {
        VStack(spacing: 24) {
            HStack { Text(L10n.text("YOUR PROFILE")).font(WFont.number(35, bold: true)); Spacer() }
            VStack(spacing: 13) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 84, weight: .ultraLight)).foregroundStyle(WColor.elevated)
                    .overlay(Image(systemName: "person.crop.circle").font(.system(size: 84, weight: .ultraLight)).foregroundStyle(WColor.muted))
                Text(L10n.text("YOUR PERSONAL RECORD")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 1.2)
                SourceBadge(source: store.selectedDay.source, isEmpty: !selectedDayExists(in: store))
                if !store.profile.displayName.isEmpty { Text(store.profile.displayName).font(WFont.number(25, bold: true)) }
                Button(L10n.text("PERSONALIZE PROFILE & VIEW HIGHLIGHTS")) { personalizing = true }.buttonStyle(WButton(filled: false))
            }.padding(.vertical, 10)
            HStack(spacing: 12) {
                MiniMetric(title: "DAYS", value: store.days.count.formatted(), unit: "saved", symbol: "calendar", color: WColor.blue)
                MiniMetric(title: "ACTIVITIES", value: store.activities.count.formatted(), unit: "logged", symbol: "figure.run", color: WColor.green)
            }
            WCard {
                VStack(spacing: 0) {
                    ProfileActionRow(title: "Device connection", subtitle: "Find nearby devices", symbol: "sensor.tag.radiowaves.forward", action: openDevice)
                    Divider()
                    ProfileActionRow(title: "Daily journal", subtitle: "Your habits and reflections", symbol: "book.closed", action: openJournal)
                    Divider()
                    ProfileActionRow(title: "Export day data", subtitle: "Save a copy in Files", symbol: "square.and.arrow.up", action: exportData)
                }
            }
            Text(L10n.text("Your journal and activity log are stored on this iPhone. Day-data exports include measurements and supplied scores, not your journal notes."))
                .font(WFont.body(14)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
        }.fullScreenCover(isPresented: $personalizing) { WHOOPProfileView(fallbackName: "Your Profile", fallbackInitials: "YOU") }
    }
}

private struct ProfileActionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).foregroundStyle(WColor.muted).frame(width: 25)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(title)).font(WFont.body(16)).foregroundStyle(.white)
                    Text(L10n.text(subtitle)).font(WFont.body(13)).foregroundStyle(WColor.muted)
                }
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(WColor.muted)
            }.padding(.vertical, 16)
        }.buttonStyle(.plain)
    }
}

struct MenuView: View {
    @EnvironmentObject private var store: AppStore
    let openDevice: () -> Void
    let importData: () -> Void
    let exportData: () -> Void
    let openDataHelp: () -> Void
    let openAbout: () -> Void
    let openReference: () -> Void
    let showExamples: () -> Void
    let clearData: () -> Void
    let openHealthImport: () -> Void
    let openWorkout: () -> Void
    let openActivities: () -> Void
    let exportBackup: () -> Void
    let restoreBackup: () -> Void
    let openLive: () -> Void
    let openTier: () -> Void
    let openAccount: () -> Void
    let openHealth: () -> Void
    let openCommunity: () -> Void
    let openProfile: () -> Void
    let openJournal: () -> Void
    @State private var confirmExamples = false
    @State private var referenceHome = false
    @State private var showingSetup = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            LanguagePicker()
            SectionHeading(title: "Your WHOOP")
            WCard {
                VStack(spacing: 0) {
                    MenuActionRow(title: "Nutrition", symbol: "fork.knife") { store.tab = .nutrition }
                    Divider()
                    MenuActionRow(title: "Welcome & tracker setup", symbol: "sparkles") { showingSetup = true }
                    Divider()
                    MenuActionRow(title: "Membership", symbol: "square.stack.3d.up", action: openTier)
                    Divider()
                    MenuActionRow(title: "Live camera & photo overlays", symbol: "camera", action: openLive).accessibilityIdentifier("openLiveCamera")
                    Divider()
                    MenuActionRow(title: "My Account", symbol: "person.crop.circle", action: openAccount)
                    Divider()
                    MenuActionRow(title: "Health Monitor", symbol: "heart.text.square", action: openHealth)
                    Divider()
                    MenuActionRow(title: "Community", symbol: "person.2", action: openCommunity)
                    Divider()
                    MenuActionRow(title: "Profile", symbol: "person.crop.circle", action: openProfile)
                    Divider()
                    MenuActionRow(title: "Journal", symbol: "book.closed", action: openJournal)
                    Divider()
                    MenuActionRow(title: "Device connection", symbol: "sensor.tag.radiowaves.forward", action: openDevice)
                    Divider()
                    MenuActionRow(title: "Record a workout", symbol: "record.circle", action: openWorkout)
                    Divider()
                    MenuActionRow(title: "Your activities", symbol: "figure.run", action: openActivities)
                    Divider()
                    MenuActionRow(title: "Strain reference", symbol: "waveform.path.ecg", action: openReference)
                }
            }
            SectionHeading(title: "Your data")
            WCard {
                VStack(spacing: 0) {
                    MenuActionRow(title: "Import from Apple Health", symbol: "heart.text.square", action: openHealthImport)
                    Divider()
                    MenuActionRow(title: "Import WHOOP ZIP / day data", symbol: "square.and.arrow.down", action: importData)
                    Divider()
                    MenuActionRow(title: "Export day data", symbol: "square.and.arrow.up", action: exportData)
                    Divider()
                    MenuActionRow(title: "Save full backup", symbol: "externaldrive", action: exportBackup)
                    Divider()
                    MenuActionRow(title: "Restore full backup", symbol: "arrow.counterclockwise", action: restoreBackup)
                    Divider()
                    MenuActionRow(title: "File formats", symbol: "doc.text", action: openDataHelp)
                }
            }
            SectionHeading(title: "Explore")
            WCard {
                VStack(spacing: 0) {
                    MenuActionRow(title: "Show example week", symbol: "sparkles") { confirmExamples = true }
                    Divider()
                    MenuActionRow(title: "Screenshot layout preview", symbol: "rectangle.on.rectangle") { referenceHome = true }
                    Divider()
                    MenuActionRow(title: "About this edition", symbol: "info.circle", action: openAbout)
                }
            }
            WCard {
                MenuActionRow(title: "Delete local data", symbol: "trash", destructive: true, action: clearData)
            }
            Text(L10n.text("\(store.days.count) saved days · \(store.activities.count) logged activities"))
                .font(WFont.body(12)).foregroundStyle(WColor.muted).frame(maxWidth: .infinity).padding(.top, 6)
        }
        .confirmationDialog(L10n.text("Replace local data with an example week?"), isPresented: $confirmExamples, titleVisibility: .visible) {
            Button(L10n.text("Replace with examples"), role: .destructive) { showExamples() }
        } message: { Text(L10n.text("This replaces imported days, journal entries and logged activities on this iPhone. Save a full backup first if you want to keep a copy, including journal entries and activities. Example scores are labelled throughout the app.")) }
        .sheet(isPresented: $referenceHome) { PulseHomeView().presentationDragIndicator(.visible) }
        .sheet(isPresented: $showingSetup) { SetupGuideView() }
    }
}

private struct MenuActionRow: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 19, weight: .light)).frame(width: 26)
                Text(L10n.text(title)).font(WFont.body(16))
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(WColor.muted)
            }.foregroundStyle(destructive ? Color.red.opacity(0.9) : Color.white).padding(.vertical, 17)
        }.buttonStyle(.plain)
    }
}

struct DataHelpView: View {
    var body: some View {
        SheetScaffold(title: "YOUR DATA FILES") {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "Import a WHOOP export ZIP")
                WCard {
                    Text(L10n.text("CHOOSE THE ORIGINAL ZIP")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                    Text(L10n.text("Select the ZIP downloaded from WHOOP, or its individual CSV files. Cycle, primary-sleep and workout records are read on this iPhone. You do not need to unzip it or configure a secure bridge."))
                        .font(WFont.body(15)).foregroundStyle(WColor.muted).padding(.top, 8)
                    Text(L10n.text("Timestamps use the CSV timezone and are grouped by UTC day. Journal answers are not applied by this measurement import. Average and maximum heart rates are not converted into a continuous heart-rate trace."))
                        .font(WFont.body(14)).foregroundStyle(WColor.muted).padding(.top, 8)
                }
                SectionHeading(title: "Import a day archive")
                WCard {
                    Text(L10n.text("JSON DAY DATA")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                    Text(L10n.text("Use a day-data export from this app as a template. Dates use ISO 8601. Supplied recovery, sleep and strain scores are shown as imported."))
                        .font(WFont.body(15)).foregroundStyle(WColor.muted).padding(.top, 8)
                }
                SectionHeading(title: "Import heart-rate samples")
                WCard {
                    Text(L10n.text("CSV HEART RATE")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                    Text(L10n.text("A CSV file needs timestamp and heart_rate columns. Use ISO 8601 timestamps with a timezone and heart rate in beats per minute."))
                        .font(WFont.body(15)).foregroundStyle(WColor.muted).padding(.top, 8)
                    Text("timestamp,heart_rate\n2026-11-08T08:00:00Z,62\n2026-11-08T08:00:01Z,63")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(WColor.blue).textSelection(.enabled).padding(.top, 12)
                    Text(L10n.text("Heart-rate-only files do not supply sleep, recovery or daily strain scores. They appear as missing values."))
                        .font(WFont.body(14)).foregroundStyle(WColor.muted).padding(.top, 12)
                }
                WCard {
                    Label(L10n.text("UP TO 10 MB PER FILE"), systemImage: "doc").font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.6)
                    Text(L10n.text("Imports are checked before they are saved. Files that are too large or contain invalid values are rejected with an explanation."))
                        .font(WFont.body(14)).foregroundStyle(WColor.muted).padding(.top, 9)
                }
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        SheetScaffold(title: "ABOUT THIS EDITION") {
            VStack(alignment: .leading, spacing: 24) {
                WhoopWordmark().frame(width: 145, height: 28).padding(.vertical, 14)
                Text(L10n.text("YOUR DATA.\nA CLOSER LOOK.")).font(WFont.number(36, bold: true))
                Text(L10n.text("A local iPhone reconstruction using WHOOP branding and recovered Android client findings. It is not the official WHOOP app and is not affiliated with WHOOP."))
                    .font(WFont.body(16)).foregroundStyle(WColor.muted)
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("WHAT YOU CAN DO")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.7)
                        Text(L10n.text("Import measurements from Apple Health or files, inspect charts, keep a journal, record workouts, manage activities, save full backups and receive compatible Bluetooth heart-rate data."))
                            .font(WFont.body(15)).foregroundStyle(WColor.muted)
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("WHAT STAYS SEPARATE")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.7)
                        Text(L10n.text("Account sync uses a separately configured OAuth bridge to import WHOOP-provided scores. This app does not independently calculate daily Recovery or sleep scores, trim strap history, or provide WHOOP teams and coaching services. The strain reference is a controlled example, not a replacement for your daily score."))
                            .font(WFont.body(15)).foregroundStyle(WColor.muted)
                    }
                }
                Text(L10n.text("No WHOOP account or password is required. Your locally saved data is not uploaded to WHOOP by this app."))
                    .font(WFont.body(14)).foregroundStyle(WColor.muted)
            }
        }
    }
}

struct ReferenceStrainView: View {
    @State private var resting = 55.0
    @State private var maximum = 190.0
    @State private var training = 145.0
    @State private var minutes = 30.0
    @State private var result: Double?
    @State private var raw: Double?
    @State private var error: String?
    var body: some View {
        SheetScaffold(title: "STRAIN REFERENCE") {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.text("EXPLORE THE\nSTRAIN SCALE.")).font(WFont.number(35, bold: true))
                Text(L10n.text("A constant heart-rate example using a recovered local calculation. This does not replace your daily score."))
                    .font(WFont.body(16)).foregroundStyle(WColor.muted)
                WCard {
                    VStack(spacing: 22) {
                        ReferenceSlider(title: "Resting heart rate", value: $resting, range: 30...110, unit: "BPM")
                        ReferenceSlider(title: "Maximum heart rate", value: $maximum, range: 120...230, unit: "BPM")
                        ReferenceSlider(title: "Training heart rate", value: $training, range: 30...230, unit: "BPM")
                        ReferenceSlider(title: "Duration", value: $minutes, range: 1...180, unit: "MIN")
                    }
                }
                Button(L10n.text("CALCULATE EXAMPLE"), action: calculate).buttonStyle(WButton())
                if let error { Text(L10n.text(error)).font(WFont.body(14)).foregroundStyle(WColor.yellow).accessibilityLabel(L10n.text("Calculation error, \(error)")) }
                if let result {
                    WCard {
                        VStack(spacing: 8) {
                            Text(L10n.text("REFERENCE RESULT")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 1.1).foregroundStyle(WColor.blue)
                            Text(L10n.text(decimalText(result))).font(WFont.number(64, bold: true))
                            Text(L10n.text("OUT OF 21")).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 1).foregroundStyle(WColor.muted)
                            if let raw { Text(L10n.text("Raw contribution \(raw.formatted(.number.locale(AppLanguage.current.locale).precision(.fractionLength(8))))")).font(WFont.body(12)).foregroundStyle(WColor.muted).padding(.top, 7) }
                            Text(L10n.text("Scenario only · not saved as your daily strain")).font(WFont.body(13)).foregroundStyle(WColor.muted).padding(.top, 7)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                Text(L10n.text("The scenario uses one constant sample per second and supplied resting and maximum heart rates. It does not estimate sleep, Recovery or strength-training strain."))
                    .font(WFont.body(14)).foregroundStyle(WColor.muted)
            }
        }
        .onChange(of: [resting, maximum, training, minutes]) { _, _ in
            result = nil; raw = nil; error = nil
        }
    }
    private func calculate() {
        error = nil; result = nil; raw = nil
        guard resting < maximum else { error = "Maximum heart rate must be greater than resting heart rate."; return }
        guard training <= maximum else { error = "Set maximum heart rate at or above the training heart rate for this scenario."; return }
        let count = max(60, min(10_800, Int(minutes) * 60))
        let samples = (0..<count).map { HeartRateSample(timestamp: Date(timeIntervalSince1970: Double($0)), bpm: training) }
        do {
            let value = try StrainCalculator.rawContribution(smoothedSamples: samples, restingHeartRate: resting, maximumHeartRate: maximum, terminalTimestampMilliseconds: Int64(count * 1000))
            raw = value; result = try StrainCalculator.scaledScore(raw: value)
        } catch { self.error = error.localizedDescription }
    }
}

private struct ReferenceSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L10n.text(title)).font(WFont.body(15))
                Spacer()
                Text("\(Int(value))").font(WFont.number(24, bold: true))
                Text(L10n.text(unit)).font(WFont.label(9)).foregroundStyle(WColor.muted)
            }
            Slider(value: $value, in: range, step: 1).tint(WColor.blue).accessibilityLabel(L10n.text(title))
        }
    }
}


/// The preference is shared by onboarding, all app screens and AI response language.
struct LanguagePicker: View {
    @AppStorage(AppLanguage.preferenceKey) private var choice = AppLanguage.system.rawValue
    var compact = false
    var body: some View {
        Group {
            if compact {
                Menu {
                    languageOptions
                } label: {
                    Image(systemName: "globe").font(.system(size: 22)).frame(width: 44, height: 44)
                }.accessibilityLabel(L10n.text("Language"))
            } else {
                WCard {
                    HStack {
                        Image(systemName: "globe").foregroundStyle(WColor.muted)
                        Picker(L10n.text("Language"), selection: selection) {
                            Text(L10n.text("Device language")).tag(AppLanguage.system.rawValue)
                            Text("English").tag(AppLanguage.english.rawValue)
                            Text("العربية").tag(AppLanguage.arabic.rawValue)
                        }.frame(minHeight: 44).tint(.white)
                    }
                }
            }
        }
    }
    private var selection: Binding<String> {
        Binding(get: { choice }, set: { AppLanguage.choose(AppLanguage(rawValue: $0) ?? .system); choice = $0 })
    }
    @ViewBuilder private var languageOptions: some View {
        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
            Button { selection.wrappedValue = language.rawValue } label: {
                let title = language == .system ? L10n.text("Device language") : language == .arabic ? "العربية" : "English"
                if choice == language.rawValue { Label(L10n.text(title), systemImage: "checkmark") } else { Text(L10n.text(title)) }
            }
        }
    }
}
