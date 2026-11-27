import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import WHOOPCore

/// CoreBluetooth may relaunch the process to restore a saved connection before a
/// scene appears. Attach persistence before recreating the central manager.
@MainActor
final class TrackerAppDelegate: NSObject, UIApplicationDelegate {
    let tracker = DeviceModel()
    let store = AppStore()
    let recorder = WorkoutRecorder()
    let dailyTracker = DailyTrackerRecorder()
    let health = HealthDataModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        recorder.bind(tracker)
        dailyTracker.bind(tracker, to: store, manualRecorder: recorder)
        tracker.bindHistory(to: store)
        tracker.reconnectSavedDevice()
        health.restoreSleepObserver(store: store)
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        store.retryProtectedRestore()
    }
}

@main
@MainActor
struct WHOOPApp: App {
    @UIApplicationDelegateAdaptor(TrackerAppDelegate.self) private var tracking
    private var tracker: DeviceModel { tracking.tracker }
    private var store: AppStore { tracking.store }
    @StateObject private var account = AccountModel()
    private var recorder: WorkoutRecorder { tracking.recorder }
    private var dailyTracker: DailyTrackerRecorder { tracking.dailyTracker }
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var liveActivity = LiveActivityDriver()
    private var health: HealthDataModel { tracking.health }
    @StateObject private var nutrition = NutritionViewModel()
    @State private var launchAnimationFinished = UIAccessibility.isReduceMotionEnabled
    @AppStorage(AppLanguage.preferenceKey) private var languageChoice = AppLanguage.system.rawValue
    var body: some Scene {
        WindowGroup {
            AppLaunchView(launchAnimationFinished: $launchAnimationFinished).environmentObject(tracker).environmentObject(store).environmentObject(account)
                .environmentObject(recorder).environmentObject(dailyTracker).environmentObject(liveActivity)
                .environmentObject(health).environmentObject(nutrition)
                .task { liveActivity.bind(recorder) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { dailyTracker.flush() } else { store.refreshCurrentDay(); store.refreshTrackerAnalysis(); tracker.reconnectSavedDevice(); tracker.syncStoredReadingsIfDue() }
                }
                .modifier(AutomaticHealthSync(tracker: tracker, store: store, health: health, account: account))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in store.refreshCurrentDay() }
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in store.refreshCurrentDay(now: date); tracker.syncStoredReadingsIfDue() }
                .environment(\.locale, AppLanguage.current.locale)
                .environment(\.layoutDirection, AppLanguage.isArabic ? .rightToLeft : .leftToRight)
                .id(languageChoice)
                .preferredColorScheme(.dark)
        }
    }
}

/// Observe readiness directly: a restored Bluetooth/HealthKit launch can load
/// the store before or after the first active scene appears.
private struct AutomaticHealthSync: ViewModifier {
    @ObservedObject var tracker: DeviceModel
    @ObservedObject var store: AppStore
    @ObservedObject var health: HealthDataModel
    @ObservedObject var account: AccountModel
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        let ready = phase == .active && !store.isLoadingSavedData && !store.isImporting
        return content
            .task(id: ready) { if ready { await tracker.restoreArchivedMeasurements() } }
            .task(id: ready && health.automaticSleepEnabled) {
                if ready && health.automaticSleepEnabled { await health.resumeSleepSync(store: store) }
            }
            .task(id: ready && account.isLinked && account.automaticSyncEnabled) {
                if ready && account.isLinked && account.automaticSyncEnabled { await account.refreshLinkedAccount(store: store) }
            }
    }
}

/// Setup is remembered on this iPhone; reference screenshots are never the launch route.
struct AppLaunchView: View {
    @Binding var launchAnimationFinished: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("whoop.setup.completed.v1") private var completed = false
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if !launchAnimationFinished && !reduceMotion {
            ZStack {
                Color.black.ignoresSafeArea()
                BundledMotionView(resource: "whoop-loading", loops: false) { launchAnimationFinished = true }
                    .frame(width: 375, height: 375).accessibilityLabel(L10n.text("Loading saved data"))
            }
        } else if store.isLoadingSavedData {
            ZStack {
                Color.black.ignoresSafeArea()
                WhoopMonogram().fill(.white).frame(width: 64, height: 64)
                VStack { Spacer(); ProgressView().tint(.white).padding(.bottom, 48) }
            }.accessibilityLabel(L10n.text("Loading saved data"))
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
        case .data: return "Sync your data."
        }
    }
}

private enum SetupSheet: String, Identifiable {
    case health, account, export
    var id: String { rawValue }
}

private struct FirstRunView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tracker: DeviceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("whoop.setup.step.v2") private var savedStep = 0
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
            .onAppear {
                if !initialized {
                    draft = store.profile
                    step = SetupStep(rawValue: savedStep) ?? .welcome
                    initialized = true
                }
            }
            .sheet(item: $sheet) { route in
                switch route { case .health: HealthImportView(); case .account: AccountView(); case .export: MeasurementExportView() }
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
                Spacer(minLength: 80)
                Spacer(minLength: 8)
                Text(L10n.text("WELCOME TO WHOOP")).font(PulseFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 2).foregroundStyle(PulseColor.muted)
                Text(L10n.text("Unlock your potential.")).font(AppLanguage.isArabic ? .system(size: 36, weight: .bold) : PulseFont.number(38))
                    .multilineTextAlignment(.center).minimumScaleFactor(0.75)
                Text(L10n.text("Sleep. Recover. Perform.")).font(PulseFont.body(17)).foregroundStyle(PulseColor.muted)
                Spacer(minLength: 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 24)
                .background {
                    if !reduceMotion {
                        BundledMotionView(resource: "whoop-intro", loops: true).allowsHitTesting(false)
                            .overlay(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    }
                }.clipped()
        }
    }
    private var welcomeActions: some View {
        VStack(spacing: 12) {
            Text(L10n.text("Pair your tracker. Sync your data. Make every day count."))
                .font(PulseFont.body(14)).foregroundStyle(PulseColor.muted).multilineTextAlignment(.center)
            Button(L10n.text("GET STARTED")) { changeStep(1) }
                .buttonStyle(WButton()).accessibilityIdentifier("setupGetStarted")
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
            TrackerConnectionPanel()
        case .data:
            Text(L10n.text("Your tracker stays connected while you sync, import and export."))
                .foregroundStyle(PulseColor.muted)
            TrackerSyncPanel()
            Text(L10n.text("ADD YOUR WHOOP SCORES")).font(PulseFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 1)
            Text(L10n.text("Official Recovery, Sleep and Strain come from your WHOOP account or export file."))
                .font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
            dataSource("Import your WHOOP ZIP", symbol: "square.and.arrow.down", detail: "Choose the downloaded ZIP, CSV or app JSON export.") { importing = true }
            dataSource("WHOOP account", symbol: "person.crop.circle", detail: "Connect through your configured secure bridge.") { sheet = .account }
            dataSource("Apple Health", symbol: "heart.fill", detail: "Choose which measurements to import.") { sheet = .health }
            dataSource("Export Data", symbol: "square.and.arrow.up", detail: "Save your profile, highlights and measurements to Files.") { sheet = .export }

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
            Button(L10n.text(buttonTitle), action: advance).buttonStyle(WButton()).disabled(store.isImporting || tracker.isConnecting || tracker.isDownloadingHistory)
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
                savedStep = 0
                tracker.stop()
                finish()
            } else { changeStep(1) }
        } catch { self.error = error.localizedDescription }
    }
    private func changeStep(_ offset: Int) {
        guard let next = SetupStep(rawValue: step.rawValue + offset) else { return }
        tracker.stop(); error = nil
        savedStep = next.rawValue
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = next }
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
        }.buttonStyle(.plain).disabled(store.isImporting).accessibilityIdentifier("setupData-\(symbol)")
    }
}


/// Bundled APK motion is played locally; no web player, fetch or API key is used.
private struct BundledMotionView: UIViewRepresentable {
    let resource: String
    let loops: Bool
    var finished: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var video: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var observers: [NSObjectProtocol] = []
        var fallback: Timer?
        var finished: (() -> Void)?
        var completed = false
        func complete() {
            guard !completed else { return }; completed = true; fallback?.invalidate(); finished?()
        }
        func stop() {
            player?.pause(); looper?.disableLooping(); player?.removeAllItems()
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
            fallback?.invalidate(); fallback = nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView(); view.backgroundColor = .black
        let coordinator = context.coordinator; coordinator.finished = finished
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            DispatchQueue.main.async { coordinator.complete() }; return view
        }
        let player = AVQueuePlayer(); player.isMuted = true; player.automaticallyWaitsToMinimizeStalling = false
        coordinator.player = player; view.video.player = player; view.video.videoGravity = .resizeAspectFill
        let item = AVPlayerItem(url: url)
        if loops { coordinator.looper = AVPlayerLooper(player: player, templateItem: item) }
        else {
            player.insert(item, after: nil)
            for notification in [Notification.Name.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime] {
                coordinator.observers.append(NotificationCenter.default.addObserver(forName: notification, object: item, queue: .main) { [weak coordinator] _ in coordinator?.complete() })
            }
            coordinator.fallback = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak coordinator] _ in coordinator?.complete() }
        }
        player.play(); return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {
        if scenePhase == .active { context.coordinator.player?.play() } else { context.coordinator.player?.pause() }
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) { coordinator.stop(); view.video.player = nil }
}
