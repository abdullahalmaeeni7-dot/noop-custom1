import SwiftUI
import UniformTypeIdentifiers
import WHOOPCore

private enum AppSheet: String, Identifiable {
    case journal, activity, device, data, about, reference, healthImport, workout, activities, account, stress, live, tier, measurementExport, review
    var id: String { rawValue }
}

private struct DashboardScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var device: DeviceModel
    @EnvironmentObject private var recorder: WorkoutRecorder
    @EnvironmentObject private var liveActivity: LiveActivityDriver
    @State private var sheet: AppSheet?
    @State private var metricRoute: ScoreMetric?
    @State private var showingStartOptions = false
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = JSONExportDocument()
    @State private var message: String?
    @State private var importReport: String?
    @State private var confirmClear = false
    @State private var restoringBackup = false
    @State private var pendingBackup: LocalBackup?
    @State private var exportName = "WHOOP-day-data"
    @State private var showingLive = false
    @State private var showingProfile = false
    @State private var attemptedReconnect = false
    @State private var compactMetrics = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        dataInterface
        .alert(L10n.text("Something needs attention"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L10n.text("OK"), role: .cancel) { message = nil }
        } message: { Text(L10n.text(message ?? "")) }
        .alert(L10n.text("Import complete"), isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
            Button(L10n.text("OK")) { importReport = nil }
        } message: { Text(L10n.text(importReport ?? "")) }
        .confirmationDialog(L10n.text("Delete all day data, profile preferences, journal entries, activities and nutrition records from this iPhone?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.text("Delete local data"), role: .destructive) {
                if recorder.isRecording { message = "Finish or discard your recording before deleting local data." }
                else { do { try store.clearData() } catch { message = error.localizedDescription } }
            }
        }
        .confirmationDialog(L10n.text("Replace local data with this complete backup?"), isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }), titleVisibility: .visible) {
            Button(L10n.text("Restore backup"), role: .destructive) {
                if recorder.isRecording { message = "Finish or discard your recording before restoring a backup." }
                else if let pendingBackup {
                    do { try store.restoreBackup(pendingBackup) } catch { message = error.localizedDescription }
                }
                pendingBackup = nil
            }
        } message: { Text(L10n.text("This replaces saved day data, journal entries, activities and nutrition records. Save a full backup first if you want to keep the current data.")) }
        .task { recorder.bind(device); liveActivity.bind(recorder) }
        .onAppear {
            if !attemptedReconnect { attemptedReconnect = true; device.reconnectSavedDevice() }
        }
        .alert(L10n.text("Your data needs attention"), isPresented: Binding(get: { store.persistenceError != nil }, set: { if !$0 { store.persistenceError = nil } })) {
            Button(L10n.text("OK")) { store.persistenceError = nil }
        } message: { Text(L10n.text(store.persistenceError ?? "")) }
    }

    private var dataInterface: some View {
        presentedInterface
        .fileImporter(isPresented: $importing, allowedContentTypes: restoringBackup ? [.json] : [.zip, .json, .commaSeparatedText], allowsMultipleSelection: false) { result in
            Task { @MainActor in
                do {
                    guard let url = try result.get().first else { return }
                    if restoringBackup { pendingBackup = try await store.readBackupFile(url) }
                    else { try await store.importFile(url); importReport = store.lastImportSummary }
                } catch { message = error.localizedDescription }
            }
        }
        .disabled(store.isImporting)
        .overlay {
            if store.isImporting {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ProgressView(L10n.text("Importing your data…")).tint(.white)
                        .padding(28).background(WColor.elevated, in: RoundedRectangle(cornerRadius: 18))
                }.accessibilityLabel(L10n.text("Importing data. Please wait."))
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
    }

    private var presentedInterface: some View {
        appLayout
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .journal: JournalEditorView()
                case .activity: ActivityEditorView()
                case .device: PulseTrackerView()
                case .data: DataHelpView()
                case .about: AboutView()
                case .reference: ReferenceStrainView()
                case .healthImport: HealthImportView()
                case .workout: WorkoutView()
                case .activities: ActivityLibraryView()
                case .account: AccountView()
                case .stress: StressMonitorView()
                case .live: LiveView()
                case .tier: ExperienceTierView()
                case .measurementExport: MeasurementExportView()
                case .review: DayReviewView()
                }
            }.preferredColorScheme(.dark).presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $metricRoute) { metric in
            MetricDetailView(metric: metric).preferredColorScheme(.dark)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.calendar, DayCalendar.utc)
        }
        .fullScreenCover(isPresented: $showingProfile) { WHOOPProfileView(fallbackName: "Your Profile", fallbackInitials: "YOU") }
        .fullScreenCover(isPresented: $showingLive) { ReferenceLiveView(reference: nil) }
        .confirmationDialog(L10n.text("Start activity"), isPresented: $showingStartOptions, titleVisibility: .visible) {
            Button(L10n.text("Record workout without camera")) { sheet = .workout }
            Button(L10n.text("Record with Live camera")) { showingLive = true }
        }

    }

    private var appLayout: some View {
        VStack(spacing: 0) {
            if store.tab != .nutrition { header }
            if store.tab == .home && compactMetrics {
                HomeMetricStrip(openMetric: openMetric).padding(.horizontal, 25).frame(height: 39).transition(.opacity)
            }
            ScrollView {
                VStack(spacing: 22) {
                    selectedScreen
                }.padding(.horizontal, ReferenceSize.pageInset).padding(.top, 8).padding(.bottom, 100)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
                    .background(GeometryReader { proxy in Color.clear.preference(key: DashboardScrollOffset.self, value: proxy.frame(in: .named("dashboardScroll")).minY) })
            }.coordinateSpace(name: "dashboardScroll").scrollIndicators(.hidden)
                .id(store.tab)
                .onPreferenceChange(DashboardScrollOffset.self) { offset in
                    let next = store.tab == .home && offset < -155
                    if next != compactMetrics { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { compactMetrics = next } }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 55).onEnded { drag in
                    guard store.tab == .home, abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                    let offset = drag.translation.width < 0 ? 1 : -1
                    if offset < 0 || !DayCalendar.utc.isDateInToday(store.selectedDate) { store.moveDay(offset) }
                })

        }
        .background { if store.tab == .nutrition { NColor.background.ignoresSafeArea() } else { WhoopBackground(healthGlow: store.tab == .health) } }
        .overlay(alignment: .bottom) { floatingNavigation.padding(.bottom, 8) }
        .onChange(of: store.tab) { _, _ in compactMetrics = false }
        .preferredColorScheme(.dark)
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.calendar, DayCalendar.utc)
        .font(WFont.body())
        .tint(.white)
    }

    @ViewBuilder private var selectedScreen: some View {
        switch store.tab {
        case .home:
            HomeView(openMetric: openMetric, openJournal: { sheet = .journal }, openActivity: { sheet = .activity }, openWorkout: { showingStartOptions = true }, openHealth: { store.tab = .health }, openStress: { sheet = .stress }, openActivities: { sheet = .activities }, openDevice: { sheet = .device }, openHealthImport: { sheet = .healthImport }, openAccount: { sheet = .account }, openLive: { showingLive = true }, openReview: { sheet = .review })
        case .sleep: MetricDetailView(metric: .sleep, embedded: true)
        case .recovery: MetricDetailView(metric: .recovery, embedded: true)
        case .strain: MetricDetailView(metric: .strain, embedded: true)
        case .nutrition: NutritionRootView()
        case .health:
            HealthView(openMetric: openMetric, importData: { restoringBackup = false; importing = true }, openHealthImport: { sheet = .healthImport })
        case .community:
            CommunityView(openActivity: { sheet = .activity }, importData: { restoringBackup = false; importing = true })
        case .profile:
            ProfileView(openJournal: { sheet = .journal }, openDevice: { sheet = .device }, exportData: exportData)
        case .menu:
            MenuView(openDevice: { sheet = .device }, importData: { restoringBackup = false; importing = true }, exportData: exportData,
                     openDataHelp: { sheet = .data }, openAbout: { sheet = .about }, openReference: { sheet = .reference },
                     showExamples: {
                         if recorder.isRecording { message = "Finish or discard your recording before replacing local data." }
                         else { store.restoreExamples() }
                     }, clearData: { confirmClear = true },
                     openHealthImport: { sheet = .healthImport }, openWorkout: { sheet = .workout },
                     openActivities: { sheet = .activities }, exportBackup: exportBackup,
                     restoreBackup: { restoringBackup = true; importing = true }, openLive: { showingLive = true }, openTier: { sheet = .tier }, openAccount: { sheet = .account }, openHealth: { store.tab = .health }, openCommunity: { store.tab = .community }, openProfile: { store.tab = .profile }, openJournal: { sheet = .journal })
        }
    }

    private var header: some View {
        ZStack {
            if [.home, .sleep, .recovery, .strain].contains(store.tab) {
                DaySelector(compact: true).frame(width: ReferenceSize.dayStripWidth)
            } else {
                Text(L10n.text(store.tab.title.uppercased())).font(WFont.label(14)).tracking(AppLanguage.isArabic ? 0 : 1.5)
            }
            if store.tab == .menu {
                HStack {
                    Button { showingProfile = true } label: { Image(systemName: "gearshape").font(.system(size: 25, weight: .light)).frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Profile settings"))
                    Spacer()
                    Link(destination: URL(string: "https://shop.whoop.com/")!) { Image(systemName: "cart").font(.system(size: 25, weight: .light)).frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Open the official WHOOP shop"))
                }
            } else if store.tab != .health && store.tab != .community {
            HStack(spacing: 0) {
                Button { showingProfile = true } label: {
                    HStack(spacing: 0) {
                        Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.69, blue: 0.43), Color(red: 1, green: 0.52, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30).overlay(Text(store.profile.initials(fallback: "YOU")).font(WFont.body(12).weight(.bold)).foregroundStyle(.black))
                        HStack(spacing: 6) {
                            Text("🔥").font(.system(size: 15))
                            Text(L10n.text(streak.formatted())).font(WFont.number(14, bold: true)).lineLimit(1).minimumScaleFactor(0.5)
                        }.padding(.horizontal, 10).frame(height: 30).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).padding(.leading, -4)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).frame(width: 92, alignment: .leading).accessibilityLabel(L10n.text("Profile, \(streak) day streak"))
                Spacer(minLength: 145)
                Button { sheet = recorder.isRecording ? .workout : .device } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: recorder.isRecording ? "record.circle" : "applewatch").font(.system(size: 25, weight: .light)).foregroundStyle(.white)
                        Circle().fill(recorder.isRecording ? .red : device.connectedName == nil ? WColor.muted : PulseColor.mint).frame(width: 6, height: 6)
                    }.frame(width: 44, height: 44)
                }.accessibilityLabel(recorder.isRecording ? "Return to recording" : device.connectedName == nil ? "Connect your tracker" : "View connected tracker")
            }
            }
        }.frame(height: 44).padding(.horizontal, 18)
    }
    private var streak: Int {
        store.profile.dayStreakOverride ?? ProfileHighlightsCalculator.calculate(days: store.days).currentLoggedDayStreak
    }
    private var floatingNavigation: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.navigationTabs) { tab in
                    let selected = store.tab == tab || (store.tab == .profile && tab == .menu)
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { store.tab = tab }
                    } label: {
                        VStack(spacing: 4) {
                            WhoopNavigationIcon(tab: tab)
                            Text(L10n.text(tab.title)).font(WFont.body(9)).lineLimit(1).minimumScaleFactor(0.8)
                        }.foregroundStyle(selected ? Color.white : WColor.muted)
                            .frame(maxWidth: .infinity, minHeight: ReferenceSize.navigationHeight)
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.horizontal, 9).background(AppGlassSurface(shape: Capsule(), interactive: true))
            Button { sheet = .review } label: {
                WhoopMonogram()
                    .frame(width: 23, height: 23).padding(15.5)
                    .overlay(Circle().stroke(LinearGradient(colors: [WColor.purple, WColor.blue], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).padding(11))
            }.buttonStyle(.plain).background(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 22), tint: WColor.purple.opacity(0.12), interactive: true))
                .accessibilityLabel(L10n.text("Open your day in review"))
        }.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 3).frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    private func openMetric(_ metric: ScoreMetric) {
        metricRoute = metric
    }
    private func exportBackup() {
        do {
            exportDocument = JSONExportDocument(data: try store.makeBackup())
            exportName = "WHOOP-full-backup"; exporting = true
        } catch { message = error.localizedDescription }
    }
    private func exportData() {
        sheet = .measurementExport
    }
}

struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    private let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        NavigationStack {
            ScrollView { content.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity) }
                .scrollIndicators(.hidden).background(WColor.background)
                .navigationTitle(L10n.text(title)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.text("Done")) { dismiss() }.font(WFont.label(13)) } }
                .toolbarBackground(WColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.tint(.white)
    }
}

struct DaySelector: View {
    @EnvironmentObject private var store: AppStore
    @State private var pickingDate = false
    var compact = false
    var body: some View {
        Group {
            if compact {
                HStack(spacing: 0) {
                    dayArrow(-1)
                    Button { pickingDate = true } label: {
                        Text(L10n.text(dayTitle)).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.7).lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, minHeight: 44)
                            .background { Capsule().fill(.white.opacity(0.09)).frame(width: 75, height: 28) }
                    }.accessibilityLabel(L10n.text("Choose date, \(dayTitle)"))
                    dayArrow(1)
                }.background { AppGlassSurface(shape: Capsule(), interactive: true).frame(height: ReferenceSize.dayStripHeight) }
            } else {
                HStack {
                    dayArrow(-1)
                    Spacer()
                    Button { pickingDate = true } label: {
                        VStack(spacing: 4) {
                            Text(L10n.text(dayTitle)).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 1.2)
                            Text(L10n.text(utcDateText(store.selectedDate, style: .dateTime.month(.abbreviated).day()))).font(WFont.body(13)).foregroundStyle(WColor.muted)
                        }.frame(minHeight: 44)
                    }.accessibilityLabel(L10n.text("Choose date, \(dayTitle)"))
                    Spacer()
                    dayArrow(1)
                }
            }
        }.foregroundStyle(.white)
            .sheet(isPresented: $pickingDate) {
                SheetScaffold(title: "Choose a day") {
                    DatePicker("Day", selection: $store.selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical).tint(WColor.green)
                }.presentationDetents([.medium, .large])
            }
    }
    private var dayTitle: String {
        DayCalendar.utc.isDateInToday(store.selectedDate) ? "TODAY" : utcDateText(store.selectedDate, style: .dateTime.month(.abbreviated).day()).uppercased()
    }
    private func dayArrow(_ offset: Int) -> some View {
        Button { store.moveDay(offset) } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right").font(.system(size: compact ? 11 : 16, weight: .bold)).frame(width: 44, height: 44)
        }.disabled(offset > 0 && DayCalendar.utc.isDateInToday(store.selectedDate))
            .accessibilityLabel(offset < 0 ? "Previous day" : "Next day")
    }

}
