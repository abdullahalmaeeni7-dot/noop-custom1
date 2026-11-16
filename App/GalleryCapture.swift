#if targetEnvironment(simulator)
import SwiftUI
import UIKit
import WHOOPCore

/// Capture-only entry point, absent from device binaries. It uses the existing app views.
enum GalleryLaunch {
    static var overrideRoute: String?
    static var route: String? {
        if let overrideRoute { return overrideRoute }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--gallery-screen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var active: Bool { route != nil }
    static var scroll: CGFloat {
        guard let route else { return 0 }
        if route.hasSuffix("-bottom") || route == "home-discover" { return -1 }
        return ["home-actions": 160, "home-day": 430, "home-plan": 1050, "home-dashboard": 1450, "home-trends": 1850, "profile-highlights": 380, "profile-records": 800, "nutrition-meals": 520][route].map(CGFloat.init) ?? 0
    }
}

struct GalleryCaptureView: View {
    let route: String
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    var body: some View {
        selected.font(WFont.body()).foregroundStyle(.white).tint(.white)
            .preferredColorScheme(.dark)
            .environment(\.calendar, DayCalendar.utc).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .task {
                await model.refresh(store.nutrition, date: store.selectedDate)
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                GalleryScroll.apply(GalleryLaunch.scroll)
                try? await Task.sleep(nanoseconds: 350_000_000)
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                if let data = try? JSONEncoder().encode(["route": route, "language": AppLanguage.current.code]) {
                    try? data.write(to: documents.appendingPathComponent("gallery-ready.json"), options: .atomic)
                }
            }
    }
    @ViewBuilder private var selected: some View {
        if route.hasPrefix("home") || ["health", "health-bottom", "community", "more", "more-bottom", "nutrition", "nutrition-meals", "nutrition-bottom"].contains(route) {
            RootView().onAppear {
                store.tab = route.hasPrefix("health") ? .health : route == "community" ? .community : route.hasPrefix("more") ? .menu : route.hasPrefix("nutrition") ? .nutrition : .home
            }
        } else if route.hasPrefix("sleep") || route.hasPrefix("recovery") || route.hasPrefix("strain-detail") || route == "coach" {
            MetricDetailView(metric: route.hasPrefix("sleep") ? .sleep : route.hasPrefix("strain") ? .strain : .recovery)
        } else if route.hasPrefix("profile") {
            WHOOPProfileView()
        } else if route.hasPrefix("live-") && route != "live-settings" {
            ReferenceLiveView(reference: nil)
        } else if route.hasPrefix("nutrition-") || route.hasPrefix("food-") {
            nutritionScreen
        } else { utilityScreen }
    }
    @ViewBuilder private var nutritionScreen: some View {
        switch route {
        case "nutrition-calories", "nutrition-calories-30", "nutrition-calories-bottom": NutritionDeepDive(kind: .calories)
        case "nutrition-protein": NutritionDeepDive(kind: .protein)
        case "nutrition-deficit", "nutrition-deficit-30", "nutrition-deficit-bottom": NutritionDeepDive(kind: .deficit)
        case "nutrition-activity": NutritionExerciseForm()
        case "nutrition-weight", "nutrition-weight-bottom": NutritionWeightView()
        case "nutrition-settings", "nutrition-settings-bottom": NutritionSettingsView()
        case "nutrition-service": NutritionServiceView()
        case "nutrition-camera": NutritionCameraView { _ in }
        case "nutrition-date": NPage(title: "Nutrition date") { DatePicker(L10n.text("Date"), selection: $store.selectedDate, displayedComponents: .date).datePickerStyle(.graphical) }
        default: NutritionFoodForm()
        }
    }
    @ViewBuilder private var utilityScreen: some View {
        switch route {
        case "health-monitor", "health-monitor-bottom": SheetScaffold(title: "HEALTH MONITOR") { HealthMonitorView(openMetric: { _ in }, importData: { }, openHealthImport: { }) }
        case "stress": StressMonitorView()
        case "day-review", "day-review-bottom": DayReviewView()
        case "journal", "journal-bottom": JournalEditorView()
        case "activity-add": ActivityEditorView()
        case "activities", "activities-bottom": ActivityLibraryView()
        case "workout": WorkoutView()
        case "tracker", "tracker-bottom": PulseTrackerView()
        case "account", "account-bottom": AccountView()
        case "apple-health", "apple-health-bottom": HealthImportView()
        case "export", "export-bottom": MeasurementExportView()
        case "data-help", "data-help-bottom": DataHelpView()
        case "tiers", "tiers-bottom": ExperienceTierView()
        case "about", "about-bottom": AboutView()
        case "strain-reference": ReferenceStrainView()
        case "live-settings": LiveView()
        case "coach-preview":
            if let data = try? PulseHomeData.load() { PulseCoachPreview(data: data) }
        default: RootView()
        }
    }
}

@MainActor private enum GalleryScroll {
    static func apply(_ offset: CGFloat) {
        guard offset != 0 else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) else { return }
        func collect(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? [] + view.subviews.flatMap(collect)
        }
        // Prefer the visible main vertical scroller, rather than horizontal pills or pickers.
        let scroll = collect(window).filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.height > 220 && $0.contentSize.height > $0.bounds.height + 20 }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        guard let scroll else { return }
        let maximum = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset < 0 ? maximum : min(maximum, offset)), animated: false)
    }
}
#endif
