import SwiftUI
import Charts
import WHOOPCore

/// View-only comparisons use the previous UTC day of the same provenance.
@MainActor
func precedingDay(in store: AppStore) -> DailySnapshot? {
    guard let date = DayCalendar.utc.date(byAdding: .day, value: -1, to: store.selectedDay.date) else { return nil }
    return store.days.first { $0.source == store.selectedDay.source && DayCalendar.utc.isDate($0.date, inSameDayAs: date) }
}

struct ReferenceMetricRow: View {
    let title: String
    let value: String
    var symbol: String = ""
    var unit: String = ""
    var previous: String? = nil
    var difference: Double? = nil
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty {
                Image(systemName: symbol).font(.system(size: compact ? 15 : 18, weight: .light))
                    .foregroundStyle(WColor.muted).frame(width: compact ? 20 : 24)
            }
            Text(L10n.text(title.uppercased())).font(WFont.label(compact ? 10 : 11)).tracking(AppLanguage.isArabic ? 0 : 0.7)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(L10n.text(value == "—" ? "NO DATA" : value)).font(WFont.number(value == "—" ? 12 : compact ? 20 : 22, bold: true))
                    if !unit.isEmpty && value != "—" { Text(L10n.text(unit)).font(WFont.body(10)).foregroundStyle(WColor.muted) }
                }
                if let previous { Text(L10n.text(previous)).font(WFont.number(10)).foregroundStyle(WColor.muted) }
            }
            if let difference, difference.isFinite, difference != 0 {
                Image(systemName: difference > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 6)).foregroundStyle(WColor.muted)
                    .accessibilityLabel(difference > 0 ? "Increased from previous day" : "Decreased from previous day")
            }
        }.padding(.vertical, compact ? 1 : 13)
            .accessibilityElement(children: .combine)
    }
}

struct MonitorShortcut: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            WCard(padding: 12) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text(title)).font(WFont.label(9)).tracking(AppLanguage.isArabic ? 0 : 0.5)
                        Text(L10n.text(value)).font(WFont.label(9)).foregroundStyle(color)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(WColor.muted)
                }.frame(minHeight: 34, alignment: .center)
            }
        }.buttonStyle(.plain)
    }
}

struct ReferenceActivityRow: View {
    let activity: ActivityRecord
    var body: some View {
        WCard(padding: 8) {
            HStack(spacing: 11) {
                HStack(spacing: 5) {
                    Image(systemName: activity.name.localizedCaseInsensitiveContains("walk") ? "figure.walk" : activity.name.localizedCaseInsensitiveContains("soccer") ? "figure.soccer" : "figure.run").font(.system(size: 20, weight: .light))
                    Text(L10n.text(activity.strain.map { decimalText($0) } ?? "—")).font(WFont.number(17, bold: true))
                }.frame(width: 79, height: 39).background(WColor.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text(activity.name.uppercased())).font(WFont.label(11)).lineLimit(1)
                    if activity.strainIsEstimate == true { Text(L10n.text("LOCAL STRAIN ESTIMATE")).font(WFont.label(7)).foregroundStyle(WColor.muted) }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L10n.text(utcDateText(activity.start, style: .dateTime.hour().minute()))).font(WFont.number(10))
                    Text(L10n.text(utcDateText(activity.start.addingTimeInterval(Double(activity.durationMinutes) * 60), style: .dateTime.hour().minute()))).font(WFont.number(10)).foregroundStyle(WColor.muted)
                }
            }
        }
    }
}

enum DashboardItem: Int, CaseIterable, Identifiable {
    case hrv, restingHeartRate, steps, zonesLow, zonesHigh, vo2, calories, stress
    var id: Int { rawValue }
    var bit: Int { 1 << rawValue }
    var title: String {
        switch self {
        case .hrv: return "Heart rate variability"
        case .restingHeartRate: return "Resting heart rate"
        case .steps: return "Steps"
        case .zonesLow: return "HR zones 1–3 (weekly)"
        case .zonesHigh: return "HR zones 4–5 (weekly)"
        case .vo2: return "VO₂ max"
        case .calories: return "Calories"
        case .stress: return "Stress monitor"
        }
    }
    func value(in day: DailySnapshot) -> String {
        switch self {
        case .hrv: return decimalText(day.hrv, places: 0)
        case .restingHeartRate: return decimalText(day.restingHeartRate, places: 0)
        case .steps: return day.steps > 0 ? day.steps.formatted() : "—"
        case .calories: return day.energyKcal > 0 ? Int(day.energyKcal).formatted() : "—"
        case .zonesLow, .zonesHigh, .vo2, .stress: return "—"
        }
    }
}

struct ReferenceDashboard: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("whoop.dashboard.visibleRows") private var mask = 255
    @State private var customizing = false
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L10n.text("My Dashboard")).font(WFont.body(20).weight(.semibold))
                Spacer()
                Button { customizing = true } label: {
                    Label(L10n.text("CUSTOMIZE"), systemImage: "pencil").font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.6).foregroundStyle(.white).frame(minHeight: 44)
                }
            }
            ForEach([DashboardItem.calories, .steps, .restingHeartRate].filter { mask & $0.bit != 0 }) { item in
                WCard(padding: 12) {
                    ReferenceMetricRow(title: item.title, value: item.value(in: store.selectedDay), symbol: dashboardSymbol(item),
                                       previous: precedingDay(in: store).map { item.value(in: $0) }, compact: false)
                }
            }
            WeeklyReadinessChart()
            ForEach([DashboardItem.hrv, .zonesLow, .zonesHigh, .vo2, .stress].filter { mask & $0.bit != 0 }) { item in
                WCard(padding: 14) {
                    ReferenceMetricRow(title: item.title, value: item.value(in: store.selectedDay), symbol: dashboardSymbol(item),
                                       previous: precedingDay(in: store).map { item.value(in: $0) }, compact: false)
                }
            }
            if mask == 0 {
                Button(L10n.text("CHOOSE YOUR METRICS")) { customizing = true }.buttonStyle(WButton(filled: false))
            }
        }
        .sheet(isPresented: $customizing) {
            SheetScaffold(title: "MY DASHBOARD") {
                VStack(spacing: 14) {
                    Text(L10n.text("Choose the measurements you want to see. Unavailable measurements stay blank."))
                        .font(WFont.body(15)).foregroundStyle(WColor.muted)
                    WCard {
                        ForEach(DashboardItem.allCases) { item in
                            Toggle(L10n.text(item.title), isOn: Binding(get: { mask & item.bit != 0 }, set: { enabled in
                                if enabled { mask |= item.bit } else { mask &= ~item.bit }
                            })).font(WFont.body(15)).padding(.vertical, 8)
                        }
                    }.tint(WColor.green)
                }
            }.preferredColorScheme(.dark)
        }
    }
    private func dashboardSymbol(_ item: DashboardItem) -> String {
        switch item {
        case .calories: return "flame"
        case .steps: return "shoeprints.fill"
        case .restingHeartRate: return "heart"
        case .hrv: return "waveform.path.ecg"
        case .zonesLow, .zonesHigh: return "heart.text.square"
        case .vo2: return "lungs"
        case .stress: return "waveform.path"
        }
    }

}

struct DetailInsight: View {
    let text: String
    var actionTitle = "ABOUT THIS SCORE"
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(text)).font(WFont.body(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack(spacing: 7) {
                    Text(L10n.text(actionTitle)).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.7)
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .light))
                }.foregroundStyle(WColor.purple)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(WColor.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [WColor.purple.opacity(0.7), WColor.blue.opacity(0.7)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
    }
}

struct HealthAgeCard: View {
    @EnvironmentObject private var store: AppStore
    private let gold = Color(red: 0.84, green: 0.66, blue: 0.22)
    var body: some View {
        VStack(spacing: 18) {
                ZStack {
                    Circle().fill(RadialGradient(stops: [.init(color: .black, location: 0.45), .init(color: gold.opacity(0.16), location: 0.70), .init(color: gold.opacity(0.7), location: 1)], center: .center, startRadius: 0, endRadius: 95))
                    Circle().stroke(gold.opacity(0.65), lineWidth: 1)
                    Canvas { context, size in
                        for index in 0..<150 {
                            let angle = Double(index) * 2.399963
                            let radius = Double(20 + (index * 19) % 72)
                            let point = CGPoint(x: Double(size.width) / 2 + cos(angle) * radius,
                                                y: Double(size.height) / 2 + sin(angle) * radius)
                            let diameter = CGFloat(index % 3 == 0 ? 2.5 : 1)
                            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: diameter, height: diameter)), with: .color(Color(red: 1, green: 0.91, blue: 0.61).opacity(index % 4 == 0 ? 0.9 : 0.5)))
                        }
                    }
                    VStack(spacing: 4) {
                        Text(L10n.text(store.profile.whoopAge.isEmpty ? "NO DATA" : store.profile.whoopAge)).font(WFont.number(store.profile.whoopAge.isEmpty ? 20 : 34, bold: true)).lineLimit(1).minimumScaleFactor(0.4)
                        Text(L10n.text("WHOOP AGE")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                        Text(L10n.text(store.profile.whoopAge.isEmpty ? "Not available" : "Personalized display")).font(WFont.body(12)).foregroundStyle(WColor.muted)
                    }
                }.frame(width: 190, height: 190)
                Text(L10n.text(store.profile.whoopAge.isEmpty ? "An age score is not included in your current data. You can personalize its display in Profile." : "Your chosen profile value. This is not a calculated health-age measurement."))
                    .font(WFont.body(12)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 20).accessibilityElement(children: .combine)
    }
}

struct StressMonitorView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        SheetScaffold(title: "STRESS MONITOR") {
            VStack(spacing: 24) {
                Text(L10n.text("TODAY")).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 1.2)
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(AngularGradient(colors: [WColor.sleep, Color.teal, WColor.yellow], center: .center, startAngle: .degrees(135), endAngle: .degrees(405)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    VStack(spacing: 8) {
                        Text("—").font(WFont.number(57, bold: true))
                        Text(L10n.text("NO STRESS DATA")).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.8).foregroundStyle(WColor.muted)
                    }
                }.frame(width: 224, height: 224)
                Text(L10n.text("A stress score is not supplied by your current data. Heart-rate samples alone are not a WHOOP stress measurement."))
                    .font(WFont.body(15)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
                if !store.selectedDay.heartRates.isEmpty {
                    SectionHeading(title: "Heart rate", subtitle: "Your recorded heart rate, not a stress score")
                    WCard { HeartRateChart(samples: store.selectedDay.heartRates).frame(height: 180) }
                }
            }
        }
    }
}

/// A local, factual review. This never substitutes a canned response for an AI service.
struct DayReviewView: View {
    @EnvironmentObject private var store: AppStore
    private var day: DailySnapshot { store.selectedDay }
    var body: some View {
        SheetScaffold(title: "DAY IN REVIEW") {
            VStack(alignment: .leading, spacing: 22) {
                Text(L10n.text(utcDateText(store.selectedDate, style: .dateTime.weekday(.wide).month(.abbreviated).day()))).font(WFont.body(16)).foregroundStyle(WColor.muted)
                SourceBadge(source: day.source, isEmpty: !selectedDayExists(in: store))
                Text(L10n.text(store.profile.displayName.isEmpty ? "Your day, in focus" : "Your day, \(store.profile.displayName)")).font(WFont.body(26).weight(.semibold))
                WCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !selectedDayExists(in: store) {
                            Text(L10n.text("Import your measurements to review your sleep, Recovery and Strain here."))
                        } else {
                            if let recovery = day.recovery { Text(L10n.text("Your recorded Recovery is \(recovery)%.")) }
                            if let strain = day.strain { Text(L10n.text("You reached \(decimalText(strain)) day Strain.")) }
                            if day.sleepMinutes > 0 { Text(L10n.text("You logged \(durationText(day.sleepMinutes)) of sleep.")) }
                            if day.steps > 0 { Text(L10n.text("You recorded \(day.steps.formatted()) steps.")) }
                            if let hrv = day.hrv { Text(L10n.text("Your HRV was \(decimalText(hrv, places: 0)) ms.")) }
                        }
                        Text(L10n.text("\(store.dayActivities.count) saved activities for this day."))
                    }.font(WFont.body(18)).lineSpacing(5)
                }
                if !store.dayActivities.isEmpty {
                    ForEach(store.dayActivities) { ReferenceActivityRow(activity: $0) }
                }
                Text(L10n.text("Summary of saved measurements · no AI interpretation")).font(WFont.body(12)).foregroundStyle(WColor.muted)
            }
        }
    }
}

struct WeeklyReadinessChart: View {
    @EnvironmentObject private var store: AppStore
    private var dates: [Date] {
        (-6...0).compactMap { DayCalendar.utc.date(byAdding: .day, value: $0, to: DayCalendar.start(of: store.selectedDate)) }
    }
    private var recorded: [DailySnapshot] {
        dates.compactMap { date in store.days.first { $0.source == store.selectedDay.source && DayCalendar.utc.isDate($0.date, inSameDayAs: date) } }
    }
    var body: some View {
        WCard(padding: 15) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(L10n.text("STRAIN & RECOVERY")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(WColor.muted).accessibilityLabel(L10n.text("Strain uses a 0 to 21 scale; Recovery uses 0 to 100 percent"))
                }
                if recorded.contains(where: { $0.strain != nil || $0.recovery != nil }) {
                    chart.frame(height: 220)
                    HStack(spacing: 20) {
                        Label(L10n.text("STRAIN · 0–21"), systemImage: "circle.fill").foregroundStyle(WColor.blue)
                        Label(L10n.text("RECOVERY · 0–100%"), systemImage: "circle.fill").foregroundStyle(WColor.yellow)
                    }.font(WFont.label(8))
                } else { MissingInline(symbol: "chart.xyaxis.line", message: "Import a recorded week to see Strain and Recovery trends.") }
            }
        }
    }
    private var chart: some View {
        Chart {
            ForEach(recorded) { day in points(day) }
            ForEach(0..<6, id: \.self) { index in segments(index) }
        }.chartYScale(domain: 0...21).chartXScale(domain: (dates.first ?? store.selectedDate)...(dates.last ?? store.selectedDate))
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 7, 14, 21]) {
                    AxisGridLine().foregroundStyle(WColor.line)
                    AxisValueLabel().foregroundStyle(WColor.blue)
                }
                AxisMarks(position: .trailing, values: [0.0, 6.93, 13.86, 21.0]) { value in
                    AxisValueLabel {
                        if let score = value.as(Double.self) {
                            Text("\(Int((score / 21 * 100).rounded()))%").font(WFont.label(9)).foregroundStyle(PulseColor.recoveryScore(score / 21 * 100))
                        }
                    }
                }
            }
            .chartXAxis { AxisMarks(values: dates) { AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: false).foregroundStyle(WColor.muted) } }
            .accessibilityLabel(L10n.text("Seven-day Strain and Recovery chart. Missing days are not joined."))
    }
    @ChartContentBuilder private func points(_ day: DailySnapshot) -> some ChartContent {
        if let strain = day.strain {
            PointMark(x: .value("Day", DayCalendar.start(of: day.date)), y: .value("Strain", strain)).foregroundStyle(WColor.blue).symbolSize(55)
                .annotation(position: .top) { Text(L10n.text(decimalText(strain))).font(WFont.number(11, bold: true)).foregroundStyle(WColor.blue) }
                .accessibilityLabel(Text(L10n.text("Strain on ") + utcDateText(day.date, style: .dateTime.month().day())))
                .accessibilityValue(Text(L10n.text(decimalText(strain))))
        }
        if let recovery = day.recovery {
            PointMark(x: .value("Day", DayCalendar.start(of: day.date)), y: .value("Recovery scaled to Strain axis", Double(recovery) * 21 / 100)).foregroundStyle(PulseColor.recoveryScore(Double(recovery))).symbolSize(55)
                .annotation(position: .bottom) { Text("\(recovery)%").font(WFont.number(10, bold: true)).foregroundStyle(PulseColor.recoveryScore(Double(recovery))) }
                .accessibilityLabel(Text(L10n.text("Recovery on ") + utcDateText(day.date, style: .dateTime.month().day())))
                .accessibilityValue(Text("\(recovery)%"))
        }
    }
    @ChartContentBuilder private func segments(_ index: Int) -> some ChartContent {
        let left = dates[index]
        let right = dates[index + 1]
        if let a = recorded.first(where: { DayCalendar.utc.isDate($0.date, inSameDayAs: left) }),
           let b = recorded.first(where: { DayCalendar.utc.isDate($0.date, inSameDayAs: right) }) {
            if let av = a.strain, let bv = b.strain {
                segment(left, right, av, bv, id: "s" + left.description, tint: WColor.blue)
            }
            if let av = a.recovery, let bv = b.recovery {
                segment(left, right, Double(av) * 21 / 100, Double(bv) * 21 / 100, id: "r" + left.description, tint: WColor.muted)
            }
        }
    }
    @ChartContentBuilder private func segment(_ left: Date, _ right: Date, _ a: Double, _ b: Double, id: String, tint: Color) -> some ChartContent {
        LineMark(x: .value("Day", left), y: .value("Score", a), series: .value("Segment", id)).foregroundStyle(tint.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
        LineMark(x: .value("Day", right), y: .value("Score", b), series: .value("Segment", id)).foregroundStyle(tint.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
    }

}

struct HomeMetricStrip: View {
    @EnvironmentObject private var store: AppStore
    let openMetric: (ScoreMetric) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScoreMetric.allCases) { metric in
                Button { openMetric(metric) } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.10), lineWidth: 2)
                            Circle().trim(from: 0, to: metric.fraction(store.selectedDay))
                                .stroke(metric == .recovery ? PulseColor.recoveryScore(store.selectedDay.recovery.map(Double.init)) : metric.color, lineWidth: 2).rotationEffect(.degrees(-90))
                        }.frame(width: 21, height: 21)
                        Text(L10n.text(metric.title)).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("\(metric.title), \(metric.value(store.selectedDay) == nil ? "no data" : metric.text(store.selectedDay)). Open details"))
            }
        }
    }
}
