import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WHOOPCore

private enum AppSheet: String, Identifiable {
    case journal, activity, device, data, about, reference, workout, activities, stress, live, tier, measurementExport, review
    var id: String { rawValue }
}

private struct DashboardScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Measure the window's physical inset, independently of nested scroll-view safe areas.
private struct WindowBottomInsetProbe: UIViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe(frame: .zero); view.changed = changed; view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.report() }
    final class Probe: UIView {
        var changed: (CGFloat) -> Void = { _ in }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() {
            guard let window else { return }
            let inset = window.safeAreaInsets.bottom
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.changed(inset)
            }
        }
    }
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
    @State private var showingHealthMonitor = false
    @State private var showingLive = false
    @State private var showingProfile = false
    @State private var compactMetrics = false
    @State private var windowBottomInset: CGFloat = 0
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
                case .workout: WorkoutView()
                case .activities: ActivityLibraryView()
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
        .fullScreenCover(isPresented: $showingHealthMonitor) { HealthMonitorView() }
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
                    if offset < 0 || !DashboardDatePolicy.isToday(store.selectedDate) { store.moveDay(offset) }
                })

        }
        .background { if store.tab == .nutrition { NColor.background.ignoresSafeArea() } else { WhoopBackground(healthGlow: store.tab == .health) } }
        .background(WindowBottomInsetProbe { value in
            if windowBottomInset != value { windowBottomInset = value }
        })
        .overlay(alignment: .bottom) {
            // Floating row already contains 3 points of bottom padding.
            floatingNavigation.offset(y: windowBottomInset + 3 - 26)
        }
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
            HomeView(openMetric: openMetric, openJournal: { sheet = .journal }, openActivity: { sheet = .activity }, openWorkout: { showingStartOptions = true }, openHealth: { showingHealthMonitor = true }, openStress: { sheet = .stress }, openActivities: { sheet = .activities }, openDevice: { sheet = .device }, importData: { restoringBackup = false; importing = true }, exportData: { sheet = .measurementExport }, openLive: { showingLive = true }, openReview: { sheet = .review })
        case .sleep: MetricDetailView(metric: .sleep, embedded: true)
        case .recovery: MetricDetailView(metric: .recovery, embedded: true)
        case .strain: MetricDetailView(metric: .strain, embedded: true)
        case .nutrition: NutritionRootView()
        case .health:
            HealthView(openMonitor: { showingHealthMonitor = true }, importData: { restoringBackup = false; importing = true })
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
                     openWorkout: { sheet = .workout },
                     openActivities: { sheet = .activities }, exportBackup: exportBackup,
                     restoreBackup: { restoringBackup = true; importing = true }, openLive: { showingLive = true }, openTier: { sheet = .tier }, openHealth: { showingHealthMonitor = true }, openCommunity: { store.tab = .community }, openProfile: { showingProfile = true }, openJournal: { sheet = .journal })
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
                Button { sheet = .device } label: {
                    TrackerStatusIcon(connected: device.connectedName != nil, offBody: device.wearState == .offBody)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("Open tracker status"))
                    .accessibilityIdentifier("homeTracker")
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
                    let selected = store.tab == tab || ([AppTab.profile, .nutrition].contains(store.tab) && tab == .menu)
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { store.tab = tab }
                    } label: {
                        VStack(spacing: 3) {
                            WhoopNavigationIcon(tab: tab)
                            Text(L10n.text(tab.title)).font(WFont.body(11).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }.foregroundStyle(selected ? Color.white : WColor.muted)
                            .frame(maxWidth: .infinity, minHeight: ReferenceSize.navigationHeight)
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("tab-\(tab.rawValue)")
                }
            }.padding(.horizontal, 4).background {
                AppGlassSurface(shape: RoundedRectangle(cornerRadius: 25, style: .continuous), solid: PulseColor.top, interactive: true)
                    .background(PulseColor.top.opacity(0.88), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            }
            DayReviewButton { sheet = .review }
        }.padding(.horizontal, 11).padding(.top, 6).padding(.bottom, 3).frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.65), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 96).offset(y: 27).allowsHitTesting(false)
            }
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
                    }.accessibilityLabel(L10n.text("Choose date, \(dayTitle)")).accessibilityIdentifier("openRecoveryCalendar")
                    dayArrow(1)
                }.background { Capsule().fill(PulseColor.elevated.opacity(0.48)).frame(height: ReferenceSize.dayStripHeight) }
            } else {
                HStack {
                    dayArrow(-1)
                    Spacer()
                    Button { pickingDate = true } label: {
                        VStack(spacing: 4) {
                            Text(L10n.text(dayTitle)).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 1.2)
                            Text(L10n.text(utcDateText(store.selectedDate, style: .dateTime.month(.abbreviated).day()))).font(WFont.body(13)).foregroundStyle(WColor.muted)
                        }.frame(minHeight: 44)
                    }.accessibilityLabel(L10n.text("Choose date, \(dayTitle)")).accessibilityIdentifier("openRecoveryCalendar")
                    Spacer()
                    dayArrow(1)
                }
            }
        }.foregroundStyle(.white)
            .sheet(isPresented: $pickingDate) {
                RecoveryCalendarSheet(selection: $store.selectedDate, days: store.days)
                    .presentationDetents([.large])
            }
    }
    private var dayTitle: String {
        DashboardDatePolicy.isToday(store.selectedDate) ? "TODAY" : utcDateText(store.selectedDate, style: .dateTime.month(.abbreviated).day()).uppercased()
    }
    private func dayArrow(_ offset: Int) -> some View {
        Button { store.moveDay(offset) } label: {
            Image(systemName: offset < 0 ? "chevron.backward" : "chevron.forward").font(.system(size: compact ? 11 : 16, weight: .bold)).frame(width: 44, height: 44)
        }.disabled(offset > 0 && DashboardDatePolicy.isToday(store.selectedDate))
            .accessibilityLabel(L10n.text(offset < 0 ? "Previous day" : "Next day"))
    }

}


/// The same recovery-colored calendar is used by Home, metric details and Live.
struct RecoveryCalendarSheet: View {
    @Binding var selection: Date
    let days: [DailySnapshot]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Date
    init(selection: Binding<Date>, days: [DailySnapshot]) {
        _selection = selection; self.days = days
        _displayed = State(initialValue: RecoveryCalendarMonth(containing: selection.wrappedValue).start)
    }
    private var today: Date { DashboardDatePolicy.today() }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    let month = RecoveryCalendarMonth(containing: displayed)
                    let index = days.reduce(into: [Date: DailySnapshot]()) { $0[DayCalendar.start(of: $1.date)] = $1 }
                    VStack(spacing: 22) {
                        HStack {
                            Button { move(-1) } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }
                                .accessibilityLabel(L10n.text("Previous month"))
                            Spacer()
                            Menu {
                                ForEach((min(1900, days.map { DayCalendar.utc.component(.year, from: $0.date) }.min() ?? 1900)...DayCalendar.utc.component(.year, from: today)).reversed(), id: \.self) { year in
                                    Button(String(year)) { selectYear(year) }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(utcDateText(displayed, style: .dateTime.month(.wide).year())).font(PulseFont.body(24).weight(.semibold))
                                    Image(systemName: "chevron.down").font(.system(size: 12))
                                }.frame(minHeight: 44)
                            }.accessibilityLabel(L10n.text("Choose month and year"))
                            Spacer()
                            Button { move(1) } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44) }
                                .disabled(month.shifted(by: 1).start > RecoveryCalendarMonth(containing: today).start)
                                .accessibilityLabel(L10n.text("Next month"))
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 10) {
                            ForEach(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], id: \.self) { name in
                                Text(L10n.text(name)).font(PulseFont.label(9)).foregroundStyle(PulseColor.muted).frame(maxWidth: .infinity, minHeight: 32)
                            }
                            ForEach(Array(month.cells.enumerated()), id: \.offset) { _, date in
                                if let date { cell(date, day: index[date]) }
                                else { Color.clear.frame(height: 60).accessibilityHidden(true) }
                            }
                        }.accessibilityIdentifier("recoveryCalendarGrid")
                        HStack(spacing: 18) {
                            legend("High", color: PulseColor.readiness)
                            legend("Moderate", color: PulseColor.recoveryYellow)
                            legend("Low", color: Color(red: 1, green: 0, blue: 0.18))
                        }.frame(maxWidth: .infinity)
                        Text(L10n.text("Colors show recorded Recovery. Dates without a score stay uncolored."))
                            .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted).multilineTextAlignment(.center)
                        Button(L10n.text("GO TO TODAY")) { choose(today) }.buttonStyle(WButton()).accessibilityIdentifier("calendarToday")
                    }.padding(.horizontal, max(0, min(14, (geometry.size.width - 308) / 2))).padding(.vertical, 20)
                }
            }.background(PulseColor.background).navigationTitle(L10n.text("Recovery Calendar")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Done")) { dismiss() }.frame(minWidth: 44, minHeight: 44)
                } }
        }.foregroundStyle(PulseColor.text).tint(.white).preferredColorScheme(.dark)
    }
    private func cell(_ date: Date, day: DailySnapshot?) -> some View {
        let band = RecoveryBand(score: day?.recovery)
        let selected = DayCalendar.start(of: selection) == date
        let future = date > today
        let color: Color = band == .green ? PulseColor.readiness : band == .yellow ? PulseColor.recoveryYellow : band == .red ? Color(red: 1, green: 0, blue: 0.18) : PulseColor.muted
        return Button { choose(date) } label: {
            VStack(spacing: 3) {
                Text(String(DayCalendar.utc.component(.day, from: date))).font(PulseFont.number(17))
                    .frame(width: 36, height: 36).foregroundStyle(band == .unavailable ? PulseColor.text : color)
                    .background(Circle().fill(color.opacity(band == .unavailable ? 0 : 0.15)))
                    .overlay(Circle().stroke(selected ? PulseColor.text : color.opacity(band == .unavailable ? 0.12 : 0.6), lineWidth: selected ? 2 : 1))
                Text(day?.recovery.map { "\($0)%" } ?? " ").font(PulseFont.label(8)).foregroundStyle(color)
            }.frame(maxWidth: .infinity, minHeight: 60).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(future).opacity(future ? 0.25 : 1)
            .accessibilityIdentifier("calendarDay-\(NutritionDay.key(date))")
            .accessibilityLabel(utcDateText(date, style: .dateTime.month(.wide).day().year()) + ", " + L10n.text(day?.recovery.map { "Recovery \($0)%" } ?? "No recorded Recovery"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); Text(L10n.text(title)).font(PulseFont.body(12)) }
    }
    private func choose(_ date: Date) { selection = DayCalendar.start(of: date); dismiss() }
    private func move(_ value: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { displayed = RecoveryCalendarMonth(containing: displayed).shifted(by: value).start }
    }
    private func selectYear(_ year: Int) {
        var components = DayCalendar.utc.dateComponents([.year, .month], from: displayed)
        components.year = year; components.day = 1
        if let date = DayCalendar.utc.date(from: components) { displayed = min(date, RecoveryCalendarMonth(containing: today).start) }
    }
}

struct DayReviewButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(LinearGradient(colors: [WColor.purple, WColor.blue], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    .frame(width: 29, height: 29)
                WhoopMonogram().environment(\.layoutDirection, .leftToRight).frame(width: 18, height: 15)
            }.frame(width: ReferenceSize.navigationHeight, height: ReferenceSize.navigationHeight)
        }
        .buttonStyle(.plain)
        .background {
            let shape = RoundedRectangle(cornerRadius: 23, style: .continuous)
            AppGlassSurface(shape: shape, tint: WColor.purple.opacity(0.08), interactive: true)
                .background(LinearGradient(colors: [Color(red: 0.16, green: 0.15, blue: 0.23), PulseColor.top], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
        }
        .accessibilityLabel(L10n.text("Open your day in review"))
    }
}
