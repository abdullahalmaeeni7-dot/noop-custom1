import SwiftUI
import UniformTypeIdentifiers
import WHOOPCore

@main
@MainActor
struct WHOOPApp: App {
    @StateObject private var tracker = DeviceModel()
    @StateObject private var store = AppStore()
    @StateObject private var account = AccountModel()
    @StateObject private var recorder = WorkoutRecorder()
    @StateObject private var liveActivity = LiveActivityDriver()
    @StateObject private var health = HealthDataModel()
    @StateObject private var nutrition = NutritionViewModel()
    @AppStorage(AppLanguage.preferenceKey) private var languageChoice = AppLanguage.system.rawValue
    var body: some Scene {
        WindowGroup {
            AppLaunchView().environmentObject(tracker).environmentObject(store).environmentObject(account)
                .environmentObject(recorder).environmentObject(liveActivity)
                .environmentObject(health).environmentObject(nutrition)
                .task { recorder.bind(tracker); liveActivity.bind(recorder) }
                .environment(\.locale, AppLanguage.current.locale)
                .environment(\.layoutDirection, AppLanguage.isArabic ? .rightToLeft : .leftToRight)
                .id(languageChoice)
                .preferredColorScheme(.dark)
        }
    }
}

/// Setup is remembered on this iPhone; reference screenshots are never the launch route.
struct AppLaunchView: View {
    @AppStorage("whoop.setup.completed.v1") private var completed = false
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if store.isLoadingSavedData {
            VStack(spacing: 24) {
                WhoopWordmark().frame(width: 150, height: 30)
                ProgressView().tint(.white).accessibilityLabel(L10n.text("Loading saved data"))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(PulseColor.background)
        } else if completed { RootView() }
        else { FirstRunView { completed = true } }
    }
}

/// Reopen setup without clearing saved data or changing the first-launch preference.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            FirstRunView { dismiss() }
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Done")) { dismiss() }.frame(minWidth: 44, minHeight: 44)
                } }
                .toolbarBackground(PulseColor.background, for: .navigationBar)
        }.tint(.white).preferredColorScheme(.dark)
    }
}

private enum SetupStep: Int, CaseIterable {
    case welcome, profile, tracker, data
    var title: String {
        switch self {
        case .welcome: return "Your day.\nYour potential."
        case .profile: return "Make it yours."
        case .tracker: return "Meet your tracker."
        case .data: return "Bring your day to life."
        }
    }
}

private enum SetupSheet: String, Identifiable {
    case health, account
    var id: String { rawValue }
}

private struct FirstRunView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tracker: DeviceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = SetupStep.welcome
    @State private var draft = ProfilePersonalization()
    @State private var initialized = false
    @State private var sheet: SetupSheet?
    @State private var importing = false
    @State private var error: String?
    @State private var importedSummary: String?
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if step == .welcome { welcomeContent }
            else { ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L10n.text(step.title)).font(AppLanguage.isArabic ? .system(size: 42, weight: .bold) : PulseFont.number(42)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    stepContent.id(step).transition(.opacity)
                    if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(PulseFont.body(14)).accessibilityIdentifier("setupError") }
                }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden) }
            if step == .welcome { welcomeActions } else { bottomBar }
        }.foregroundStyle(PulseColor.text).font(PulseFont.body(16))
            .background(LinearGradient(colors: [PulseColor.top, PulseColor.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear { if !initialized { draft = store.profile; initialized = true } }
            .sheet(item: $sheet) { route in
                switch route { case .health: HealthImportView(); case .account: AccountView() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .json, .commaSeparatedText]) { result in
                Task { @MainActor in
                    do { try await store.importFile(result.get()); draft = store.profile; importedSummary = store.lastImportSummary; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
            .onChange(of: tracker.connectedName) { _, name in if name != nil { tracker.stop() } }
            .onDisappear { tracker.stop() }
    }

    private var welcomeContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                ZStack {
                    Ellipse().fill(PulseColor.load.opacity(0.10)).blur(radius: 45).frame(width: 250, height: 300)
                    RoundedRectangle(cornerRadius: 80).stroke(Color(white: 0.13), lineWidth: 57).frame(width: 130, height: 240)
                    RoundedRectangle(cornerRadius: 80).stroke(Color(white: 0.24), style: StrokeStyle(lineWidth: 50, dash: [1, 3])).frame(width: 130, height: 240)
                    RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Color(white: 0.29), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 158, height: 88).overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14), lineWidth: 1))
                        .overlay(WhoopWordmark().frame(width: 88, height: 18).opacity(0.7)).offset(y: -64)
                }.rotationEffect(.degrees(-24)).scaleEffect(min(1, geometry.size.height / 420))
                    .frame(height: max(170, min(300, geometry.size.height * 0.58))).accessibilityHidden(true)
                Spacer(minLength: 8)
                Text(L10n.text("WELCOME TO WHOOP")).font(PulseFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 2).foregroundStyle(PulseColor.muted)
                Text(L10n.text("Unlock your potential.")).font(AppLanguage.isArabic ? .system(size: 36, weight: .bold) : PulseFont.number(38))
                    .multilineTextAlignment(.center).minimumScaleFactor(0.75)
                Text(L10n.text("Sleep. Recover. Perform.")).font(PulseFont.body(17)).foregroundStyle(PulseColor.muted)
                Spacer(minLength: 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 24)
        }
    }
    private var welcomeActions: some View {
        VStack(spacing: 10) {
            Button(L10n.text("SET UP MY TRACKER")) { changeStep(2) }.buttonStyle(WButton()).accessibilityIdentifier("setupTrackerFirst")
            Button(L10n.text("I HAVE WHOOP DATA")) { changeStep(3) }.buttonStyle(WButton(filled: false)).accessibilityIdentifier("setupImportFirst")
            Button(L10n.text("PERSONALIZE FIRST")) { changeStep(1) }.font(PulseFont.label(11)).frame(minHeight: 44)
        }.padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: 560).frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button { changeStep(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Previous setup step"))
            }
            Spacer()
            WhoopWordmark().frame(width: 94, height: 19).accessibilityLabel("WHOOP")
            Spacer()
            if step != .welcome { Color.clear.frame(width: 44, height: 44) }
            else { LanguagePicker(compact: true) }
        }.padding(.horizontal, 16).frame(height: 70)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome: EmptyView()
        case .profile:
            Text(L10n.text("Choose how you appear in the app. You can change this later in Profile.")).foregroundStyle(PulseColor.muted)
            PulseCard {
                Text(L10n.text("YOUR NAME")).font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                TextField(L10n.text("What should we call you?"), text: $draft.displayName).textContentType(.givenName).textInputAutocapitalization(.words).frame(minHeight: 48).accessibilityLabel(L10n.text("Your name"))
                Divider()
                Text(L10n.text("AGE · OPTIONAL")).font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                TextField(L10n.text("Your age"), text: $draft.age).keyboardType(.decimalPad).frame(minHeight: 48).accessibilityLabel(L10n.text("Your age, optional"))
            }
            Text(L10n.text("Your name and age are stored on this iPhone. Recovery and sleep scores come from measurements you import; setup does not create scores.")).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
        case .tracker:
            Text(L10n.text("Wear your sensor and keep it close to your iPhone. If it has a heart-rate broadcast setting, turn that on.")).foregroundStyle(PulseColor.muted)
            PulseCard {
                Label(L10n.text(tracker.connectedName ?? "Ready to connect"), systemImage: tracker.connectedName == nil ? "sensor.tag.radiowaves.forward" : "checkmark.circle.fill")
                    .font(PulseFont.body(21).weight(.semibold)).foregroundStyle(tracker.connectedName == nil ? PulseColor.text : PulseColor.mint)
                Text(L10n.text(tracker.status)).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted).accessibilityIdentifier("setupTrackerStatus")
                if tracker.isScanning || tracker.isConnecting { ProgressView().tint(PulseColor.load).frame(minHeight: 44).accessibilityLabel(tracker.isScanning ? "Searching for trackers" : "Connecting to tracker") }
                if tracker.connectedName == nil {
                    Button(L10n.text(tracker.isScanning ? "STOP SEARCHING" : "SEARCH FOR MY TRACKER")) {
                        if tracker.isScanning { tracker.stop() } else { tracker.scan() }
                    }.buttonStyle(WButton(filled: false)).disabled(tracker.isConnecting).accessibilityIdentifier("setupSearchTracker")
                }
                if tracker.isConnecting {
                    Button(L10n.text("CANCEL CONNECTION")) { tracker.disconnect() }.buttonStyle(WButton(filled: false))
                }
                if tracker.canStartCustomStream || tracker.startingCustomStream {
                    Button(L10n.text(tracker.startingCustomStream ? "STARTING HEART RATE…" : "ENABLE LIVE HEART RATE")) { tracker.startCustomStream() }
                        .buttonStyle(WButton(filled: false)).disabled(tracker.startingCustomStream)
                }
            }
            if tracker.connectedName == nil {
                ForEach(tracker.devices) { device in
                    Button { tracker.connect(device) } label: {
                        PulseCard {
                            HStack(spacing: 12) {
                                Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(PulseColor.load)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).font(PulseFont.body(17).weight(.semibold))
                                    Text(L10n.text("Signal \(device.rssi) dBm")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(minHeight: 44)
                        }
                    }.buttonStyle(.plain).disabled(tracker.isConnecting).accessibilityLabel(L10n.text("Connect to \(device.name)"))
                }
            }
            Text(L10n.text("You can connect later from Home. Bluetooth heart rate does not provide a full sleep or Recovery history; those can be imported in the next step.")).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
        case .data:
            Text(L10n.text("Choose where your measurements come from, or start fresh and add them later.")).foregroundStyle(PulseColor.muted)
            dataSource("Apple Health", symbol: "heart.fill", detail: "Choose which measurements to import.") { sheet = .health }
            dataSource("WHOOP account", symbol: "person.crop.circle", detail: "Connect through your configured secure bridge.") { sheet = .account }
            dataSource("Import your WHOOP ZIP", symbol: "square.and.arrow.down", detail: "Choose the downloaded ZIP, CSV or app JSON export.") { importing = true }
            if let importedSummary { Text(L10n.text(importedSummary)).font(PulseFont.body(14)).foregroundStyle(PulseColor.mint) }
            let count = store.days.filter { $0.source != .example }.count
            if count > 0 {
                Label(L10n.text("\(count) saved days ready for your dashboard"), systemImage: "checkmark.circle.fill").foregroundStyle(PulseColor.mint)
            } else {
                Text(L10n.text("No measurements yet. Home will help you connect and start recording; no sample scores will be shown as yours.")).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
            }
            if store.isImporting { ProgressView(L10n.text("Saving your measurements…")).tint(PulseColor.load).frame(minHeight: 44) }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(SetupStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item == step ? PulseColor.text : PulseColor.muted.opacity(0.25)).frame(width: item == step ? 24 : 7, height: 6)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel(L10n.text("Setup step \(step.rawValue + 1) of 4"))
            Button(L10n.text(buttonTitle), action: advance).buttonStyle(WButton()).disabled(store.isImporting || tracker.isConnecting)
                .accessibilityIdentifier("setupContinue")
        }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), solid: PulseColor.background))
            .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: return "GET STARTED"
        case .profile: return "CONTINUE"
        case .tracker: return tracker.connectedName == nil ? "CONNECT LATER" : "CONTINUE"
        case .data: return "OPEN MY HOME"
        }
    }
    private func advance() {
        error = nil
        do {
            if step == .profile { draft.age = AppLanguage.canonicalDigits(draft.age); try store.updateProfile(draft) }
            if step == .data {
                try store.completeSetup()
                tracker.stop()
                finish()
            } else { changeStep(1) }
        } catch { self.error = error.localizedDescription }
    }
    private func changeStep(_ offset: Int) {
        guard let next = SetupStep(rawValue: step.rawValue + offset) else { return }
        tracker.stop(); error = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = next }
    }
    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(PulseColor.load).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) { Text(L10n.text(title)).font(PulseFont.body(18).weight(.semibold)); Text(L10n.text(detail)).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted) }
        }.padding(.vertical, 4)
    }
    private func dataSource(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PulseCard {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(PulseColor.load).frame(width: 32)
                    VStack(alignment: .leading, spacing: 5) { Text(L10n.text(title)).font(PulseFont.body(18).weight(.semibold)); Text(L10n.text(detail)).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted) }
                    Spacer(); Image(systemName: "chevron.right")
                }.frame(minHeight: 54)
            }
        }.buttonStyle(.plain).disabled(store.isImporting)
    }
}
