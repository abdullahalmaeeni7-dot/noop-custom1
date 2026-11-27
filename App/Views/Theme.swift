import SwiftUI
import WHOOPCore

// Palette and geometry follow the user's supplied visual references.
enum WColor {
    static let background = Color(red: 0.065, green: 0.080, blue: 0.089)
    static let backgroundTop = Color(red: 0.149, green: 0.192, blue: 0.212)
    static let card = PulseColor.card
    static let elevated = Color(red: 0.192, green: 0.231, blue: 0.251)
    static let muted = Color(red: 0.60, green: 0.64, blue: 0.67)
    static let line = Color.white.opacity(0.085)
    static let green = Color(red: 0.12, green: 0.88, blue: 0.0)
    static let blue = Color(red: 0.0, green: 0.62, blue: 0.91)
    static let sleep = PulseColor.sleep
    static let purple = Color(red: 0.62, green: 0.53, blue: 0.98)
    static let yellow = PulseColor.recoveryYellow
}

enum WFont {
    static func body(_ size: CGFloat = 16) -> Font { AppLanguage.isArabic ? .system(size: size) : .custom("ProximaNova-Regular", size: size, relativeTo: .body) }
    static func number(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "DINPro-Bold" : "DINPro-Medium", size: size, relativeTo: .title)
    }
    static func label(_ size: CGFloat = 12) -> Font { AppLanguage.isArabic ? .system(size: size, weight: .bold) : .custom("DINPro-Bold", size: size, relativeTo: .caption).weight(.bold) }
}

/// SwiftUI material equivalent for the installed desktop glass skill's visual rules.
/// Backgrounds are sampled by the system; Reduce Transparency uses an opaque surface.
struct AppGlassSurface<S: Shape>: View {
    let shape: S
    var tint = Color.white.opacity(0.025)
    var solid = WColor.card
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Group {
            if reduceTransparency { shape.fill(solid) }
            else { material }
        }.overlay(shape.stroke(LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.40 : 0.08), .white.opacity(0.02), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5))
            .allowsHitTesting(false)
    }
    @ViewBuilder private var material: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else { fallback }
        #else
        fallback
        #endif
    }
    private var fallback: some View {
        shape.fill(.ultraThinMaterial).overlay(shape.fill(solid.opacity(0.32)))
    }
}

struct WCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat
    private let surface: Color?
    private let radius: CGFloat
    init(padding: CGFloat = 14, surface: Color? = nil, cornerRadius: CGFloat = ReferenceSize.cardRadius, @ViewBuilder content: () -> Content) {
        self.padding = padding; self.surface = surface; self.radius = cornerRadius; self.content = content()
    }
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background((surface ?? WColor.card), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title.uppercased())).font(WFont.label(14)).tracking(AppLanguage.isArabic ? 0 : 1.1).foregroundStyle(.white)
            if let subtitle { Text(L10n.text(subtitle)).font(WFont.body(14)).foregroundStyle(WColor.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SourceBadge: View {
    let source: DataSource
    var isEmpty = false
    private var label: String { isEmpty ? "NO DAY DATA" : (source == .example ? "EXAMPLE DAY" : "IMPORTED DATA") }
    private var symbol: String { isEmpty ? "calendar.badge.exclamationmark" : (source == .example ? "sparkles" : "arrow.down.doc") }
    private var color: Color { isEmpty ? WColor.muted : (source == .example ? WColor.yellow : WColor.blue) }
    var body: some View {
        Label(L10n.text(label), systemImage: symbol)
            .font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.8).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.09), in: Capsule())
            .accessibilityLabel(isEmpty ? "No saved measurements for this day" : (source == .example ? "Example data, not your measurements" : "Imported measurements"))
    }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        WCard {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(WColor.muted)
                Text(L10n.text(title)).font(WFont.number(22, bold: true)).foregroundStyle(.white)
                Text(L10n.text(detail)).font(WFont.body(15)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }
}

struct WButton: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(WFont.label(13)).tracking(AppLanguage.isArabic ? 0 : 0.9)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(filled ? WColor.background : Color.white)
            .background(filled ? Color.white : PulseColor.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

func clockDuration(_ minutes: Int) -> String {
    String(format: "%d:%02d", minutes / 60, minutes % 60)
}

func durationText(_ minutes: Int) -> String {
    let value = max(0, minutes)
    return AppLanguage.isArabic ? "\(value / 60) س \(value % 60) د" : "\(value / 60)h \(value % 60)m"
}

func decimalText(_ value: Double?, places: Int = 1) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.locale(AppLanguage.current.locale).precision(.fractionLength(places)))
}

enum WhoopScoreDisplay {
    static let estimatePreferenceKey = "whoop.showLocalStrainEstimates.v1"
    static var allowsLocalEstimates: Bool { true }
}

enum ScoreMetric: String, CaseIterable, Identifiable {
    case sleep, recovery, strain
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var color: Color {
        switch self { case .sleep: return WColor.sleep; case .recovery: return WColor.green; case .strain: return WColor.blue }
    }
    var symbol: String {
        switch self { case .sleep: return "moon.fill"; case .recovery: return "heart.fill"; case .strain: return "waveform.path.ecg" }
    }
    func value(_ day: DailySnapshot) -> Double? {
        switch self {
        case .sleep: return day.sleepPerformance.map(Double.init)
        case .recovery: return day.recovery.map(Double.init)
        case .strain: return day.displayedStrain
        }
    }
    func text(_ day: DailySnapshot) -> String {
        guard let value = value(day) else { return "—" }
        return self == .strain ? decimalText(value) : "\(Int(value))%"
    }
    func fraction(_ day: DailySnapshot) -> Double {
        min(max((value(day) ?? 0) / (self == .strain ? 21 : 100), 0), 1)
    }
    var description: String {
        switch self {
        case .sleep: return "Sleep performance compares sleep achieved with sleep needed. This view displays the score supplied in your day data."
        case .recovery: return "Recovery brings your readiness into focus. This view displays the supplied score alongside resting heart rate and heart rate variability."
        case .strain: return "Strain is shown on a 0–21 scale. An imported WHOOP score takes priority. Otherwise, the local estimate counts received heart-rate intervals only and may differ from WHOOP."
        }
    }
}

struct ScoreRing: View {
    let metric: ScoreMetric
    let day: DailySnapshot
    var large = false
    var comparisonFraction: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            PulseRingTrack(fraction: metric.fraction(day),
                           tint: metric == .recovery ? PulseColor.recoveryScore(day.recovery.map(Double.init)) : metric.color,
                           lineWidth: large ? 16 : ReferenceSize.ringStroke, marker: comparisonFraction)
            VStack(spacing: large ? 8 : 0) {
                if large { WhoopWordmark().frame(width: 94, height: 17).opacity(0.46).padding(.bottom, 2) }
                if large {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(L10n.text(number)).font(WFont.number(74, bold: true)).monospacedDigit().contentTransition(.numericText(value: metric.value(day) ?? 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: metric.value(day))
                        if metric != .strain && metric.value(day) != nil { Text("%").font(WFont.number(37, bold: true)) }
                    }.foregroundStyle(.white).minimumScaleFactor(0.55).lineLimit(1)
                    Text(L10n.text(metric == .sleep ? (day.sleepPerformance == nil && day.displayedSleepMinutes > 0 ? "TIME ASLEEP" : "SLEEP\nPERFORMANCE") : metric == .strain ? "DAY STRAIN" : "RECOVERY"))
                        .font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 1.2).multilineTextAlignment(.center)
                } else {
                    Text(L10n.text(metric.value(day) == nil ? "NO DATA" : metric.text(day))).font(WFont.number(metric.value(day) == nil ? 12 : 25, bold: true))
                        .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                }
            }.padding(10)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: large ? 270 : nil, height: large ? 270 : nil)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(metric.text(day))\(day.source == .example ? ", example data" : "")")
    }
    private var number: String {
        if metric == .sleep, day.sleepPerformance == nil, day.displayedSleepMinutes > 0 { return clockDuration(day.displayedSleepMinutes) }
        guard let value = metric.value(day) else { return "—" }
        return metric == .strain ? decimalText(value) : String(Int(value))
    }
}

struct WhoopBackground: View {
    var healthGlow = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [WColor.backgroundTop, WColor.background, WColor.background], startPoint: .top, endPoint: .bottom)
            if healthGlow {
                RadialGradient(colors: [PulseColor.mint.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 410)
            }
        }.ignoresSafeArea()
    }
}

func utcDateFormat(_ style: Date.FormatStyle) -> Date.FormatStyle {
    var format = style
    format.locale = AppLanguage.current.locale
    format.calendar = DayCalendar.utc
    format.timeZone = TimeZone(secondsFromGMT: 0)!
    return format
}

func utcDateText(_ date: Date, style: Date.FormatStyle) -> String {
    date.formatted(utcDateFormat(style))
}

@MainActor
func selectedDayExists(in store: AppStore) -> Bool {
    store.days.contains { DayCalendar.utc.isDate($0.date, inSameDayAs: store.selectedDate) }
}

struct WhoopNavigationIcon: View {
    let tab: AppTab
    private var asset: String? {
        switch tab {
        case .home: return "NavigationHome"
        case .health: return "NavigationHealth"
        case .community: return "NavigationCommunity"
        case .menu: return "NavigationMore"
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let asset {
                Image(asset).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: tab.symbol).resizable().scaledToFit()
            }
        }.frame(width: 22, height: 22).accessibilityHidden(true)
    }
}
