import SwiftUI
import Charts
import WHOOPCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tracker: DeviceModel
    let openMetric: (ScoreMetric) -> Void
    let openJournal: () -> Void
    let openActivity: () -> Void
    let openWorkout: () -> Void
    let openHealth: () -> Void
    let openStress: () -> Void
    let openActivities: () -> Void
    let openDevice: () -> Void
    let openHealthImport: () -> Void
    let openAccount: () -> Void
    private var day: DailySnapshot { store.selectedDay }

    let openLive: () -> Void
    @State private var quickMenu = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            overview.padding(.top, 14).padding(.bottom, 7)
            if !selectedDayExists(in: store) { setupCard }
            else { dailyHighlight }
            HStack(spacing: 11) {
                monitor("HEALTH MONITOR", detail: "View your measurements", symbol: "heart.text.square", tint: WColor.sleep, action: openHealth)
                monitor("STRESS MONITOR", detail: "About stress data", symbol: "waveform.path", tint: PulseColor.mint, action: openStress)
            }
            myDay
            plan
            ReferenceDashboard()
            if tracker.connectedName != nil { liveHeartRate }
            discover
        }
    }
    private var myDay: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L10n.text("My Day")).font(WFont.body(20).weight(.semibold))
                Spacer()
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { quickMenu.toggle() } } label: {
                    Image(systemName: quickMenu ? "xmark" : "plus").font(.system(size: 22, weight: .regular)).foregroundStyle(.black)
                        .frame(width: 34, height: 34).background(.white, in: RoundedRectangle(cornerRadius: 11))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel(quickMenu ? "Close day actions" : "Add to your day")
            }.overlay(alignment: .bottomTrailing) {
                if quickMenu {
                    PulseQuickMenu(strengthTitle: "RECORD WORKOUT") { panel in
                        quickMenu = false
                        switch panel {
                        case .live: openLive()
                        case .journal: openJournal()
                        case .strength, .session: openWorkout()
                        case .activity: openActivity()
                        default: break
                        }
                    }.offset(y: -55).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                }
            }.zIndex(3)
            Button(action: openReview) {
                HStack(spacing: 10) {
                    Image(systemName: "moon").font(.system(size: 23, weight: .light)).foregroundStyle(WColor.purple)
                    Text(L10n.text(reviewTitle)).font(WFont.body(14).weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(WColor.blue)
                }.padding(.horizontal, 15).padding(.vertical, 9).frame(maxWidth: .infinity, minHeight: 44)
                    .background(LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.34), Color(red: 0.12, green: 0.27, blue: 0.31)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)
            tonight
            activities
            journalCard
        }.zIndex(3)
    }
    private var reviewTitle: String {
        let first = store.profile.displayName.split(separator: " ").first.map(String.init)
        return first.map { "\($0)’s Day In Review" } ?? "Your Day In Review"
    }
    private func monitor(_ title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            WCard(padding: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(L10n.text(title)).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.7).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right").foregroundStyle(WColor.muted)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: symbol).font(.system(size: 18, weight: .light)).foregroundStyle(tint)
                        Text(L10n.text(detail)).font(WFont.body(12)).foregroundStyle(WColor.muted)
                    }
                }.frame(minHeight: 58)
            }
        }.buttonStyle(.plain)
    }
    private var journalCard: some View {
        Button(action: openJournal) {
            WCard(padding: 15) {
                VStack(spacing: 25) {
                    HStack {
                        Text(L10n.text("MY JOURNAL")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(WColor.muted)
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<7) { index in
                            if let date = DayCalendar.utc.date(byAdding: .day, value: index - 6, to: store.selectedDate) {
                                VStack(spacing: 9) {
                                    Text(L10n.text(utcDateText(date, style: .dateTime.weekday(.abbreviated)).uppercased())).font(WFont.label(9))
                                    ZStack {
                                        Circle().stroke(index == 6 ? .white.opacity(0.8) : WColor.muted.opacity(0.45), lineWidth: 1).frame(width: 20, height: 20)
                                        if store.hasJournal(on: date) { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(PulseColor.mint) }
                                    }
                                }.foregroundStyle(index == 6 ? .white : WColor.muted).frame(maxWidth: .infinity)
                            }
                        }
                    }.padding(.horizontal, 10)
                    Label(L10n.text("LOG YOUR BEHAVIORS"), systemImage: "lightbulb").font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                        .frame(maxWidth: .infinity, minHeight: 40).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }.buttonStyle(.plain)
    }
    private var plan: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.text("My Plan")).font(WFont.body(20).weight(.semibold))
            Button { store.tab = .nutrition } label: {
                WCard(padding: 18) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("Build Your Best Self")).font(WFont.body(18).weight(.semibold))
                            Text(L10n.text("Set nutrition goals and track the habits that support your training.")).font(WFont.body(14)).foregroundStyle(WColor.muted)
                            Label(L10n.text("EXPLORE NUTRITION"), systemImage: "arrow.right").font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8).foregroundStyle(WColor.sleep)
                        }
                        PulsePlanArtwork().frame(width: 90, height: 100).accessibilityHidden(true)
                    }
                }
            }.buttonStyle(.plain)
        }
    }
    private var discover: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.text("Discover More")).font(WFont.body(20).weight(.semibold))
            monitor("YOUR CONNECTED TRACKER", detail: "Find a sensor, check its status and record your next session.", symbol: "applewatch", tint: WColor.blue, action: openDevice)
            monitor("YOUR HEALTH HISTORY", detail: "Import measurements from Apple Health.", symbol: "heart.text.square", tint: PulseColor.mint, action: openHealthImport)
            monitor("YOUR WHOOP ACCOUNT", detail: "Connect to sync your saved WHOOP measurements.", symbol: "person.crop.circle", tint: WColor.sleep, action: openAccount)
        }
    }

    private var setupCard: some View {
        WCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("Your day starts here")).font(WFont.number(23, bold: true))
                Text(L10n.text("Connect your tracker to see live heart rate and record workouts. Import saved measurements to add sleep, Recovery and daily Strain to your overview."))
                    .font(WFont.body(15)).foregroundStyle(WColor.muted)
                Button(L10n.text(tracker.connectedName == nil ? "CONNECT MY TRACKER" : "VIEW MY TRACKER"), action: openDevice).buttonStyle(WButton())
                HStack(spacing: 12) {
                    Button(L10n.text("APPLE HEALTH"), action: openHealthImport).buttonStyle(WButton(filled: false))
                    Button(L10n.text("WHOOP ACCOUNT"), action: openAccount).buttonStyle(WButton(filled: false))
                }
                Text(L10n.text("You can also import a data file in More → Your data.")).font(WFont.body(12)).foregroundStyle(WColor.muted)
            }
        }
    }

    private var liveHeartRate: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            WCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(L10n.text("LIVE HEART RATE")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8); Spacer(); Image(systemName: "heart.fill").foregroundStyle(WColor.blue) }
                    if let bpm = tracker.heartRate, let received = tracker.heartRateReceivedAt, (0...10).contains(timeline.date.timeIntervalSince(received)) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(L10n.text(bpm.formatted(.number.locale(AppLanguage.current.locale).precision(.fractionLength(0))))).font(WFont.number(40, bold: true)).monospacedDigit()
                            Text(L10n.text("BPM")).font(WFont.label(12)).foregroundStyle(WColor.muted)
                        }
                        Text(L10n.text(tracker.connectedName ?? "Connected sensor")).font(WFont.body(13)).foregroundStyle(WColor.green)
                    } else {
                        Text(L10n.text(tracker.connectedName == nil ? "Connect a tracker to begin" : "Waiting for a heart-rate sample")).font(WFont.body(17))
                        Button(L10n.text(tracker.connectedName == nil ? "FIND MY TRACKER" : "CHECK CONNECTION"), action: openDevice)
                            .font(WFont.label(11)).foregroundStyle(WColor.blue).frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private var overview: some View {
        VStack(spacing: 20) {
            WhoopWordmark().frame(width: 66, height: 12)
            HStack(alignment: .top, spacing: 32) {
                ForEach(ScoreMetric.allCases) { metric in
                    PulseRing(value: metric.value(day) == nil ? "NO DATA" : metric.text(day), fraction: metric.fraction(day),
                              previous: precedingDay(in: store).flatMap { metric.value($0) == nil ? nil : metric.fraction($0) },
                              tint: metric == .recovery ? PulseColor.recoveryScore(day.recovery.map(Double.init)) : metric.color,
                              label: metric.title, action: { openMetric(metric) })
                }
            }.padding(.horizontal, 15)

            if day.source == .example {
                Text(L10n.text("EXAMPLE DATA · NOT PERSONAL MEASUREMENTS")).font(WFont.label(7)).tracking(AppLanguage.isArabic ? 0 : 0.8).foregroundStyle(WColor.muted)
            }
        }.padding(.bottom, 1)
    }

    private var dailyHighlight: some View {
        Button { openMetric(.recovery) } label: {
            WCard(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("Your day, in focus")).font(WFont.body(15).weight(.semibold))
                        Text(L10n.text(highlightText)).font(WFont.body(13)).foregroundStyle(WColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 17, weight: .light))
                        Text(L10n.text(decimalText(day.hrv, places: 0))).font(WFont.number(15, bold: true))
                    }.foregroundStyle(WColor.sleep)
                }.frame(minHeight: 80, alignment: .top)
            }
        }.buttonStyle(.plain)
    }

    private var highlightText: String {
        if let recovery = day.recovery, let strain = day.strain {
            return "Your Recovery is \(recovery)% and your day Strain is \(decimalText(strain)). Review your sleep and recorded activities for the full picture."
        }
        guard let hrv = day.hrv else { return "Your HRV will appear here when a measurement is available. Tap to view your Recovery details." }
        if let previous = precedingDay(in: store)?.hrv, previous > 0 {
            let percent = (hrv - previous) / previous * 100
            if abs(percent) < 0.5 { return "Your HRV is \(decimalText(hrv, places: 0)) ms, similar to the previous recorded day. View your Recovery details for more context." }
            return "Your HRV is \(decimalText(abs(percent), places: 0))% \(percent > 0 ? "higher" : "lower") than the previous recorded day. View your Recovery details for more context."
        }
        return "Your recorded HRV is \(decimalText(hrv, places: 0)) ms. View your Recovery details alongside your resting heart rate."
    }

    private var activities: some View {
        WCard(padding: 12) {
        VStack(spacing: 11) {
            HStack {
                Text(L10n.text("TODAY’S ACTIVITIES")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                Spacer()
                Button(L10n.text("VIEW ALL"), action: openActivities).font(WFont.label(8)).foregroundStyle(WColor.muted)
                    .accessibilityLabel(L10n.text("View all saved activities"))
            }
            if day.sleepMinutes > 0 {
                Button { openMetric(.sleep) } label: {
                    WCard(padding: 8) {
                        HStack(spacing: 11) {
                            HStack(spacing: 5) {
                                Image(systemName: "moon.fill").font(.system(size: 15))
                                Text(L10n.text(clockDuration(day.sleepMinutes))).font(WFont.number(16, bold: true))
                            }.frame(width: 79, height: 39).background(WColor.sleep, in: RoundedRectangle(cornerRadius: 4))
                            Text(L10n.text("SLEEP")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(WColor.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
            ForEach(store.dayActivities.sorted { $0.start < $1.start }) { activity in ReferenceActivityRow(activity: activity) }
            if day.sleepMinutes == 0 && store.dayActivities.isEmpty {
                Text(L10n.text("No activities recorded for this day.")).font(WFont.body(13)).foregroundStyle(WColor.muted).padding(.vertical, 7)
            }
            HStack(spacing: 9) {
                compactAction("+  ADD ACTIVITY", action: openActivity)
                compactAction("START ACTIVITY", action: openWorkout)
            }.padding(.top, 7)
        }
        }
    }

    private var tonight: some View {
        Button { openMetric(.sleep) } label: {
            WCard {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(L10n.text("SLEEP OVERVIEW")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.7)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(WColor.muted)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text(day.sleepNeededMinutes > 0 ? clockDuration(day.sleepNeededMinutes) : "NO TARGET")).font(WFont.number(day.sleepNeededMinutes > 0 ? 28 : 16, bold: true)).foregroundStyle(WColor.sleep)
                            Text(L10n.text("SLEEP NEEDED")).font(WFont.label(8)).foregroundStyle(WColor.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(L10n.text(day.sleepMinutes > 0 ? clockDuration(day.sleepMinutes) : "NO DATA")).font(WFont.number(day.sleepMinutes > 0 ? 28 : 16, bold: true))
                            Text(L10n.text("RECORDED SLEEP")).font(WFont.label(8)).foregroundStyle(WColor.muted)
                        }
                    }
                    Text(L10n.text("VIEW SLEEP DETAILS")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                        .frame(maxWidth: .infinity, minHeight: 40).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }.buttonStyle(.plain)
    }

    private func compactAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.text(title)).font(WFont.label(9)).tracking(AppLanguage.isArabic ? 0 : 0.4).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(WColor.elevated.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    private func clockDuration(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
    private var averageHeartRate: Double? {
        guard !day.heartRates.isEmpty else { return nil }
        return day.heartRates.map(\.bpm).reduce(0, +) / Double(day.heartRates.count)
    }
}

struct MiniMetric: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
    var body: some View {
        WCard {
            HStack {
                Text(L10n.text(title)).font(WFont.label(9)).tracking(AppLanguage.isArabic ? 0 : 1).foregroundStyle(WColor.muted)
                Spacer(); Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(L10n.text(value)).font(WFont.number(28, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                Text(L10n.text(unit)).font(WFont.body(11)).foregroundStyle(WColor.muted)
            }.padding(.top, 8)
        }
    }
}

struct MissingInline: View {
    let symbol: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light))
            Text(L10n.text(message)).font(WFont.body(14)).multilineTextAlignment(.center)
        }.foregroundStyle(WColor.muted).frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

struct ActivityRow: View {
    let activity: ActivityRecord
    var body: some View {
        WCard {
            HStack(spacing: 13) {
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 25, weight: .light))
                    .foregroundStyle(WColor.blue).frame(width: 35)
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name).font(WFont.number(19, bold: true))
                    Text("\(utcDateText(activity.start, style: .dateTime.month(.abbreviated).day())) · \(durationText(activity.durationMinutes))")
                        .font(WFont.body(13)).foregroundStyle(WColor.muted)
                }
                Spacer()
                if let score = activity.strain {
                    VStack(spacing: 3) {
                        Text(L10n.text(decimalText(score))).font(WFont.number(24, bold: true)).foregroundStyle(WColor.blue)
                        Text(L10n.text(activity.strainIsEstimate == true ? "LOCAL EST." : "STRAIN")).font(WFont.label(8)).foregroundStyle(WColor.muted)
                    }
                } else { Text(L10n.text("LOGGED")).font(WFont.label(9)).foregroundStyle(WColor.muted) }
            }
        }
    }
}

struct HealthMonitorView: View {
    @EnvironmentObject private var store: AppStore
    let openMetric: (ScoreMetric) -> Void
    let importData: () -> Void
    let openHealthImport: () -> Void
    var showImportActions = true
    private var day: DailySnapshot { store.selectedDay }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "Health monitor", subtitle: "Measurements recorded for this day")
            WCard {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("HEART RATE")).font(WFont.label(9)).tracking(AppLanguage.isArabic ? 0 : 0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(L10n.text(decimalText(day.heartRates.last?.bpm, places: 0))).font(WFont.number(35, bold: true)).foregroundStyle(WColor.blue)
                        Text(L10n.text("BPM · LAST SAMPLE")).font(WFont.label(8)).foregroundStyle(WColor.muted)
                    }
                    if !day.heartRates.isEmpty { HeartRateChart(samples: day.heartRates).frame(height: 95) }
                    else { Text(L10n.text("No heart-rate samples available")).font(WFont.body(13)).foregroundStyle(WColor.muted) }
                }
            }
            HStack(spacing: 10) {
                healthTile("RESPIRATORY RATE", value: decimalText(day.respiratoryRate), unit: "rpm", symbol: "lungs", available: day.respiratoryRate != nil)
                healthTile("BLOOD OXYGEN", value: "—", unit: "%", symbol: "drop", available: false)
            }
            HStack(spacing: 10) {
                healthTile("RHR", value: decimalText(day.restingHeartRate, places: 0), unit: "bpm", symbol: "heart", available: day.restingHeartRate != nil)
                healthTile("HRV", value: decimalText(day.hrv, places: 0), unit: "ms", symbol: "waveform.path.ecg", available: day.hrv != nil)
            }
            HStack(spacing: 10) {
                healthTile("SKIN TEMP", value: "—", unit: "°C", symbol: "thermometer.medium", available: false)
                healthTile("SLEEP", value: day.sleepMinutes > 0 ? durationText(day.sleepMinutes) : "—", unit: "", symbol: "moon", available: day.sleepMinutes > 0)
            }
            if showImportActions {
                Button(L10n.text("IMPORT FROM APPLE HEALTH"), action: openHealthImport).buttonStyle(WButton())
                Button(L10n.text("IMPORT DAY DATA FILE"), action: importData).buttonStyle(WButton(filled: false))
            }
        }
    }
    private func healthTile(_ title: String, value: String, unit: String, symbol: String, available: Bool) -> some View {
        WCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.text(title), systemImage: symbol).font(WFont.label(8)).foregroundStyle(WColor.muted).lineLimit(1).minimumScaleFactor(0.6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(L10n.text(value)).font(WFont.number(27, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(L10n.text(value == "—" ? "" : unit)).font(WFont.body(11)).foregroundStyle(WColor.muted)
                }
                Text(L10n.text(available ? "RECORDED" : "NOT AVAILABLE")).font(WFont.label(7)).tracking(AppLanguage.isArabic ? 0 : 0.6)
                    .foregroundStyle(available ? WColor.sleep : WColor.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HealthMetricRow: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            Text(L10n.text(title)).font(WFont.body(15))
            Spacer(minLength: 6)
            Text(L10n.text(value)).font(WFont.number(23, bold: true))
            Text(L10n.text(value == "—" ? "" : unit)).font(WFont.body(11)).foregroundStyle(WColor.muted).frame(minWidth: 20, alignment: .leading)
        }.padding(.vertical, 14).accessibilityElement(children: .combine)
    }
}

struct HeartRateChart: View {
    let samples: [HeartRateSample]
    private var lower: Double { max(0, (samples.lazy.map(\.bpm).min() ?? 40) - 10) }
    private var upper: Double { max(lower + 20, (samples.lazy.map(\.bpm).max() ?? 100) + 10) }
    // Bounded rendering only: original samples and full-data statistics are untouched.
    // Keep each contiguous bucket's minimum and maximum in chronological order.
    private var plottedSamples: [HeartRateSample] {
        guard samples.count > 800 else { return samples }
        let bucketSize = max(1, Int(ceil(Double(samples.count) / 399.0)))
        var display: [HeartRateSample] = [samples[0]]
        display.reserveCapacity(800)
        for start in stride(from: 0, to: samples.count, by: bucketSize) {
            let end = min(start + bucketSize, samples.count)
            var minimum = start
            var maximum = start
            for index in start..<end {
                if samples[index].bpm < samples[minimum].bpm { minimum = index }
                if samples[index].bpm > samples[maximum].bpm { maximum = index }
            }
            for index in [minimum, maximum].sorted() {
                if display.last?.timestamp != samples[index].timestamp { display.append(samples[index]) }
            }
        }
        if display.last?.timestamp != samples.last?.timestamp, let last = samples.last { display.append(last) }
        return display
    }
    var body: some View {
        let display = plottedSamples
        Chart {
            ForEach(Array(display.enumerated()), id: \.offset) { item in
                AreaMark(x: .value("Time", item.element.timestamp), yStart: .value("Baseline", lower), yEnd: .value("Heart rate", item.element.bpm))
                    .foregroundStyle(LinearGradient(colors: [WColor.blue.opacity(0.22), WColor.blue.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", item.element.timestamp), y: .value("BPM", item.element.bpm))
                    .foregroundStyle(WColor.blue).lineStyle(StrokeStyle(lineWidth: 1.5))
                if samples.count == 1 {
                    PointMark(x: .value("Time", item.element.timestamp), y: .value("BPM", item.element.bpm)).foregroundStyle(WColor.blue)
                }
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: utcDateFormat(.dateTime.hour())).foregroundStyle(WColor.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(WColor.line)
                AxisValueLabel().foregroundStyle(WColor.muted)
            }
        }
        .accessibilityLabel(L10n.text("Heart rate overview from \(samples.count) samples"))
    }
}

struct HealthView: View {
    @EnvironmentObject private var store: AppStore
    let openMetric: (ScoreMetric) -> Void
    let importData: () -> Void
    let openHealthImport: () -> Void
    @State private var showingMonitor = false
    @State private var showingStress = false
    @State private var showingProfile = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HealthAgeCard()
            WCard(padding: 18, surface: Color(red: 0.11, green: 0.19, blue: 0.24)) {
                Label(L10n.text("Your imported scores appear below. Your profile’s WHOOP Age is a personal display setting; the proprietary aging calculation is not supplied by the data import."), systemImage: "info.circle")
                    .font(WFont.body(14)).foregroundStyle(WColor.sleep)
            }
            WCard(padding: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.text("PACE OF AGING")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 1)
                    Text(L10n.text("Not included in your connected data")).font(WFont.body(18))
                    Button(L10n.text("PERSONALIZE YOUR PROFILE")) { showingProfile = true }.buttonStyle(WButton(filled: false))
                }
            }
            Button { showingMonitor = true } label: {
                WCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack { Text(L10n.text("HEALTH MONITOR")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8); Spacer(); Image(systemName: "chevron.right").foregroundStyle(WColor.muted) }
                        HStack(spacing: 0) {
                            healthStatus("RESP", symbol: "lungs", available: store.selectedDay.respiratoryRate != nil)
                            healthStatus("SpO₂", symbol: "drop", available: false)
                            healthStatus("RHR", symbol: "heart", available: store.selectedDay.restingHeartRate != nil)
                            healthStatus("HRV", symbol: "waveform.path.ecg", available: store.selectedDay.hrv != nil)
                            healthStatus("TEMP", symbol: "thermometer.medium", available: false)
                        }
                        Text(L10n.text("Indicators show available measurements, not a medical range assessment.")).font(WFont.body(12)).foregroundStyle(WColor.muted)
                    }
                }
            }.buttonStyle(.plain)
            Button { showingStress = true } label: {
                WCard(padding: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(L10n.text("STRESS MONITOR")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                            Text(L10n.text("Stress measurements are not included in your current data.")).font(WFont.body(17)).foregroundStyle(WColor.muted)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(WColor.muted)
                    }
                }
            }.buttonStyle(.plain)
            Button(L10n.text("IMPORT FROM APPLE HEALTH"), action: openHealthImport).buttonStyle(WButton())
            Button(L10n.text("IMPORT YOUR WHOOP DATA"), action: importData).buttonStyle(WButton(filled: false))
        }.sheet(isPresented: $showingMonitor) {
            SheetScaffold(title: "HEALTH MONITOR") {
                HealthMonitorView(openMetric: openMetric, importData: importData, openHealthImport: openHealthImport, showImportActions: false)
            }
        }.sheet(isPresented: $showingStress) { StressMonitorView() }
            .fullScreenCover(isPresented: $showingProfile) { WHOOPProfileView(fallbackName: "Your Profile", fallbackInitials: "YOU") }
    }
    private func healthStatus(_ label: String, symbol: String, available: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(WColor.muted)
            Text(L10n.text(label)).font(WFont.label(9)).tracking(AppLanguage.isArabic ? 0 : 0.6)
            Image(systemName: available ? "checkmark" : "minus").font(.system(size: 13, weight: .bold))
                .foregroundStyle(available ? PulseColor.mint : WColor.muted).frame(width: 22, height: 22)
                .background((available ? PulseColor.mint : WColor.muted).opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel("\(label), \(available ? "measurement available" : "not available")")
    }
}
