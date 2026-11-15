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
            Text(title.uppercased()).font(WFont.label(compact ? 10 : 11)).tracking(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(WFont.number(compact ? 22 : 25, bold: true))
                    if !unit.isEmpty && value != "—" { Text(unit).font(WFont.body(10)).foregroundStyle(WColor.muted) }
                }
                if let previous { Text(previous).font(WFont.number(10)).foregroundStyle(WColor.muted) }
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
                        Text(title).font(WFont.label(9)).tracking(0.5)
                        Text(value).font(WFont.label(9)).foregroundStyle(color)
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
                    Text(activity.strain.map { decimalText($0) } ?? "—").font(WFont.number(17, bold: true))
                }.frame(width: 79, height: 39).background(WColor.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.name.uppercased()).font(WFont.label(11)).lineLimit(1)
                    if activity.strainIsEstimate == true { Text("LOCAL STRAIN ESTIMATE").font(WFont.label(7)).foregroundStyle(WColor.muted) }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(utcDateText(activity.start, style: .dateTime.hour().minute())).font(WFont.number(10))
                    Text(utcDateText(activity.start.addingTimeInterval(Double(activity.durationMinutes) * 60), style: .dateTime.hour().minute())).font(WFont.number(10)).foregroundStyle(WColor.muted)
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
                Text("My Dashboard").font(WFont.body(25).weight(.semibold))
                Spacer()
                Button { customizing = true } label: {
                    Label("CUSTOMIZE", systemImage: "pencil").font(WFont.label(10)).tracking(0.6).foregroundStyle(.white).frame(minHeight: 44)
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
                Button("CHOOSE YOUR METRICS") { customizing = true }.buttonStyle(WButton(filled: false))
            }
        }
        .sheet(isPresented: $customizing) {
            SheetScaffold(title: "MY DASHBOARD") {
                VStack(spacing: 14) {
                    Text("Choose the measurements you want to see. Unavailable measurements stay blank.")
                        .font(WFont.body(15)).foregroundStyle(WColor.muted)
                    WCard {
                        ForEach(DashboardItem.allCases) { item in
                            Toggle(item.title, isOn: Binding(get: { mask & item.bit != 0 }, set: { enabled in
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
            Text(text).font(WFont.body(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack(spacing: 7) {
                    Text(actionTitle).font(WFont.label(10)).tracking(0.7)
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
        WCard {
            VStack(spacing: 9) {
                Text("HEALTH").font(WFont.label(10)).tracking(1.4)
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color.clear, gold.opacity(0.10), gold.opacity(0.70), Color.clear], center: .center, startRadius: 18, endRadius: 108))
                    Circle().stroke(gold.opacity(0.35), lineWidth: 0.7).padding(13)
                    Canvas { context, size in
                        for index in 0..<90 {
                            let angle = Double(index) * 2.399963
                            let radius = Double(65 + (index * 19) % 34)
                            let point = CGPoint(x: Double(size.width) / 2 + cos(angle) * radius,
                                                y: Double(size.height) / 2 + sin(angle) * radius)
                            let diameter = CGFloat(index % 3 == 0 ? 2.5 : 1)
                            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: diameter, height: diameter)), with: .color(.yellow.opacity(index % 4 == 0 ? 0.9 : 0.4)))
                        }
                    }
                    VStack(spacing: 4) {
                        Text(store.profile.whoopAge.isEmpty ? "NO DATA" : store.profile.whoopAge).font(WFont.number(store.profile.whoopAge.isEmpty ? 25 : 48, bold: true)).lineLimit(1).minimumScaleFactor(0.4)
                        Text("WHOOP AGE").font(WFont.label(11)).tracking(0.8)
                        Text(store.profile.whoopAge.isEmpty ? "Not available" : "Personalized display").font(WFont.body(12)).foregroundStyle(WColor.muted)
                    }
                }.frame(width: 220, height: 220)
                Text(store.profile.whoopAge.isEmpty ? "An age score is not included in your current data. You can personalize its display in Profile." : "Your chosen profile value. This is not a calculated health-age measurement.")
                    .font(WFont.body(12)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 6)
        }.accessibilityElement(children: .combine)
    }
}

struct StressMonitorView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        SheetScaffold(title: "STRESS MONITOR") {
            VStack(spacing: 24) {
                Text("TODAY").font(WFont.label(10)).tracking(1.2)
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(AngularGradient(colors: [WColor.sleep, Color.teal, WColor.yellow], center: .center, startAngle: .degrees(135), endAngle: .degrees(405)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    VStack(spacing: 8) {
                        Text("—").font(WFont.number(57, bold: true))
                        Text("NO STRESS DATA").font(WFont.label(10)).tracking(0.8).foregroundStyle(WColor.muted)
                    }
                }.frame(width: 224, height: 224)
                Text("A stress score is not supplied by your current data. Heart-rate samples alone are not a WHOOP stress measurement.")
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
                Text(utcDateText(store.selectedDate, style: .dateTime.weekday(.wide).month(.abbreviated).day())).font(WFont.body(16)).foregroundStyle(WColor.muted)
                Text(store.profile.displayName.isEmpty ? "Your day, in focus" : "Your day, \(store.profile.displayName)").font(WFont.body(26).weight(.semibold))
                WCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !selectedDayExists(in: store) {
                            Text("Import your measurements to review your sleep, Recovery and Strain here.")
                        } else {
                            if let recovery = day.recovery { Text("Your recorded Recovery is \(recovery)%.") }
                            if let strain = day.strain { Text("You reached \(decimalText(strain)) day Strain.") }
                            if day.sleepMinutes > 0 { Text("You logged \(durationText(day.sleepMinutes)) of sleep.") }
                            if day.steps > 0 { Text("You recorded \(day.steps.formatted()) steps.") }
                            if let hrv = day.hrv { Text("Your HRV was \(decimalText(hrv, places: 0)) ms.") }
                        }
                        Text("\(store.dayActivities.count) saved activities for this day.")
                    }.font(WFont.body(18)).lineSpacing(5)
                }
                if !store.dayActivities.isEmpty {
                    ForEach(store.dayActivities) { ReferenceActivityRow(activity: $0) }
                }
                Text("Summary of saved measurements · no AI interpretation").font(WFont.body(12)).foregroundStyle(WColor.muted)
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
                    Text("STRAIN & RECOVERY").font(WFont.label(12)).tracking(0.8)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(WColor.muted).accessibilityLabel("Strain uses a 0 to 21 scale; Recovery uses 0 to 100 percent")
                }
                if recorded.contains(where: { $0.strain != nil || $0.recovery != nil }) {
                    chart.frame(height: 220)
                    HStack(spacing: 20) {
                        Label("STRAIN · 0–21", systemImage: "circle.fill").foregroundStyle(WColor.blue)
                        Label("RECOVERY · 0–100%", systemImage: "circle.fill").foregroundStyle(WColor.yellow)
                    }.font(WFont.label(8))
                } else { MissingInline(symbol: "chart.xyaxis.line", message: "Import a recorded week to see Strain and Recovery trends.") }
            }
        }
    }
    private var chart: some View {
        Chart {
            ForEach(dates, id: \.self) { date in
                if let day = recorded.first(where: { DayCalendar.utc.isDate($0.date, inSameDayAs: date) }) {
                    if let strain = day.strain {
                        PointMark(x: .value("Day", date), y: .value("Strain", strain)).foregroundStyle(WColor.blue).symbolSize(55)
                            .annotation(position: .top) { Text(decimalText(strain)).font(WFont.number(11, bold: true)).foregroundStyle(WColor.blue) }
                    }
                    if let recovery = day.recovery {
                        PointMark(x: .value("Day", date), y: .value("Recovery scaled to Strain axis", Double(recovery) * 21 / 100)).foregroundStyle(PulseColor.recoveryScore(Double(recovery))).symbolSize(55)
                            .annotation(position: .bottom) { Text("\(recovery)%").font(WFont.number(10, bold: true)).foregroundStyle(PulseColor.recoveryScore(Double(recovery))) }
                    }
                }
            }
            ForEach(0..<6, id: \.self) { index in
                let left = dates[index]
                let right = dates[index + 1]
                if let a = recorded.first(where: { DayCalendar.utc.isDate($0.date, inSameDayAs: left) }),
                   let b = recorded.first(where: { DayCalendar.utc.isDate($0.date, inSameDayAs: right) }) {
                    if let av = a.strain, let bv = b.strain {
                        LineMark(x: .value("Day", left), y: .value("Strain", av), series: .value("Segment", "s" + left.description)).foregroundStyle(WColor.blue.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
                        LineMark(x: .value("Day", right), y: .value("Strain", bv), series: .value("Segment", "s" + left.description)).foregroundStyle(WColor.blue.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    if let av = a.recovery, let bv = b.recovery {
                        LineMark(x: .value("Day", left), y: .value("Recovery", Double(av) * 21 / 100), series: .value("Segment", "r" + left.description)).foregroundStyle(WColor.muted.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
                        LineMark(x: .value("Day", right), y: .value("Recovery", Double(bv) * 21 / 100), series: .value("Segment", "r" + left.description)).foregroundStyle(WColor.muted.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
        }.chartYScale(domain: 0...21).chartXScale(domain: (dates.first ?? store.selectedDate)...(dates.last ?? store.selectedDate))
            .chartYAxis { AxisMarks(values: [0, 7, 14, 21]) { AxisGridLine().foregroundStyle(WColor.line); AxisValueLabel().foregroundStyle(WColor.blue) } }
            .chartXAxis { AxisMarks(values: dates) { AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: false).foregroundStyle(WColor.muted) } }
            .accessibilityLabel("Seven-day Strain and Recovery chart. Missing days are not joined.")
    }
}
