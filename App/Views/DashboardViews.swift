import SwiftUI
import Charts
import CoreTransferable
import UIKit
import UniformTypeIdentifiers
import WHOOPCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tracker: DeviceModel
    @EnvironmentObject private var automaticRecorder: DailyTrackerRecorder
        let openMetric: (ScoreMetric) -> Void
    let openJournal: () -> Void
    let openActivity: () -> Void
    let openWorkout: () -> Void
    let openHealth: () -> Void
    let openStress: () -> Void
    let openActivities: () -> Void
    let openDevice: () -> Void
    let importData: () -> Void
    let exportData: () -> Void
    private var day: DailySnapshot { store.selectedDay }

    let openLive: () -> Void
    @State private var quickMenu = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            overview.padding(.top, 22).padding(.bottom, 12)
            if tracker.wearState == .offBody {
                trackingNotice("Tracker off body", detail: "Put your strap back on to resume readings.", symbol: "sensor.tag.radiowaves.forward", color: WColor.yellow)
            } else if let active = automaticRecorder.detectedActivity, DashboardDatePolicy.isToday(day.date) {
                trackingNotice("Possible activity in progress", detail: L10n.text("Elevated heart rate") + " · " + Duration.seconds(active.durationMinutes * 60).formatted(.units(allowed: [.minutes], width: .abbreviated)), symbol: "waveform.path.ecg", color: WColor.blue)
            }

            if tracker.connectedName != nil && !DashboardDatePolicy.isToday(day.date) {
                Button(L10n.text("VIEW TODAY’S TRACKING")) { store.selectedDate = DashboardDatePolicy.today() }.buttonStyle(WButton(filled: false))
            }
            if !selectedDayExists(in: store) { setupCard }
            else { dailyHighlight }
            if day.strainIsLocalEstimate {
                Text(L10n.text("LOCAL STRAIN ESTIMATE · RECEIVED HEART RATE ONLY")).font(WFont.label(9)).foregroundStyle(WColor.blue)
            }
            if (day.trackerRecording != nil || !day.heartRates.isEmpty) && day.recovery == nil {
                WCard {
                    Text(L10n.text("Recovery needs overnight data")).font(WFont.body(15).weight(.semibold))
                    Text(L10n.text("Import your recorded measurements to add an available Recovery score.")).font(WFont.body(13)).foregroundStyle(WColor.muted)
                    Button(L10n.text("IMPORT"), action: importData).buttonStyle(WButton(filled: false))
                }
            }
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
    private func trackingNotice(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        Button(action: openDevice) {
            WCard {
                HStack(spacing: 12) {
                    Image(systemName: symbol).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(title)).font(WFont.body(16).weight(.semibold))
                        Text(L10n.text(detail)).font(WFont.body(13)).foregroundStyle(WColor.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward").foregroundStyle(WColor.muted)
                }.frame(minHeight: 44)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("trackerNotice")
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
                    Image(systemName: "chevron.forward").foregroundStyle(WColor.blue)
                }.padding(.horizontal, 15).padding(.vertical, 9).frame(maxWidth: .infinity, minHeight: 44)
                    .background(LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.34), Color(red: 0.12, green: 0.27, blue: 0.31)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)
            tonight
            if day.estimatedSleepMinutes != nil && day.sleepMinutes == 0 && day.confirmedSleep == nil {
                Text(L10n.text("Sleep estimated from tracker heart rate. You can edit it in Sleep."))
                    .font(WFont.body(12)).foregroundStyle(WColor.muted)
            }
            SleepReviewEntry(wakeDay: day.date, compact: true).id(day.date)
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
                        Image(systemName: "chevron.forward").foregroundStyle(WColor.muted)
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
                        Spacer(); Image(systemName: "chevron.forward").foregroundStyle(WColor.muted)
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
            monitor("IMPORT", detail: "Add measurements from your data file.", symbol: "square.and.arrow.down", tint: PulseColor.mint, action: importData)
            monitor("EXPORT", detail: "Save your measurements to Files.", symbol: "square.and.arrow.up", tint: WColor.sleep, action: exportData)
        }
    }

    private var setupCard: some View {
        WCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("Your day starts here")).font(WFont.number(23, bold: true))
                Text(L10n.text("Connect your tracker to save received readings and download stored heart-rate history. Import WHOOP data to add official Recovery, Sleep and Strain scores."))
                    .font(WFont.body(15)).foregroundStyle(WColor.muted)
                Button(L10n.text(tracker.connectedName == nil ? "CONNECT MY TRACKER" : "VIEW MY TRACKER"), action: openDevice).buttonStyle(WButton())
                HStack(spacing: 12) {
                    Button(L10n.text("IMPORT"), action: importData).buttonStyle(WButton(filled: false))
                    Button(L10n.text("EXPORT"), action: exportData).buttonStyle(WButton(filled: false))
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
                    let durationOnly = metric == .sleep && day.sleepPerformance == nil && day.displayedSleepMinutes > 0
                    let durationProgress = day.sleepNeededMinutes > 0 ? Double(day.displayedSleepMinutes) / Double(day.sleepNeededMinutes) : 0
                    PulseRing(value: durationOnly ? clockDuration(day.displayedSleepMinutes) : metric.value(day) == nil ? "NO DATA" : metric.text(day),
                              fraction: durationOnly ? durationProgress : metric.fraction(day),
                              previous: nil,
                              tint: metric == .recovery ? PulseColor.recoveryScore(day.recovery.map(Double.init)) : metric.color,
                              label: durationOnly ? "TIME ASLEEP" : metric.title, action: { openMetric(metric) })
                        .accessibilityIdentifier("scoreRing-" + metric.rawValue)
                }
            }.padding(.horizontal, 15)

            if day.source == .example {
                Text(L10n.text("EXAMPLE DATA · NOT PERSONAL MEASUREMENTS")).font(WFont.label(7)).tracking(AppLanguage.isArabic ? 0 : 0.8).foregroundStyle(WColor.muted)
            }
        }.padding(.bottom, 1)
    }

    private var dailyHighlight: some View {
        Button { openMetric(day.strainIsLocalEstimate ? .strain : .recovery) } label: {
            WCard(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text(highlightTitle)).font(WFont.body(14).weight(.semibold))
                        Text(L10n.text(highlightText)).font(WFont.body(13)).foregroundStyle(WColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 17, weight: .light))
                        Text("1").font(WFont.number(13)).foregroundStyle(WColor.muted)
                    }.foregroundStyle(.white.opacity(0.8)).frame(width: 23, height: 42)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                }.frame(minHeight: 80, alignment: .top)
            }
        }.buttonStyle(.plain)
    }

    private var highlightTitle: String {
        guard let strain = ScoreMetric.strain.value(day) else { return "Your Day In Review" }
        return strain >= 14 ? "Pushing Limits" : strain >= 10 ? "Building Momentum" : "Finding Your Balance"
    }
    private var highlightText: String {
        if day.strainIsLocalEstimate { return "Your connected heart-rate readings are being saved automatically. The local Strain estimate covers received readings only." }
        if let strain = day.strain {
            if strain >= 14 { return "You worked hard today. Your recorded Strain is \(decimalText(strain)). Explore your activities and Recovery to plan what comes next." }
            if strain >= 10 { return "You built up a solid day of activity. Review your Strain and Recovery together as you plan your next session." }
            return "Your day has been lighter so far. Check your Recovery and recent activities before deciding what comes next."
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
            if day.displayedSleepMinutes > 0 {
                Button { openMetric(.sleep) } label: {
                    WCard(padding: 8) {
                        HStack(spacing: 11) {
                            HStack(spacing: 5) {
                                Image(systemName: "moon.fill").font(.system(size: 15))
                                Text(L10n.text(clockDuration(day.displayedSleepMinutes))).font(WFont.number(16, bold: true))
                            }.frame(width: 79, height: 39).background(WColor.sleep, in: RoundedRectangle(cornerRadius: 4))
                            Text(L10n.text(day.usesConfirmedSleep ? "CONFIRMED SLEEP" : "SLEEP")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                            Spacer()
                            Image(systemName: "chevron.forward").font(.system(size: 10)).foregroundStyle(WColor.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
            ForEach(store.dayActivities.sorted { $0.start < $1.start }) { activity in ReferenceActivityRow(activity: activity) }
            if day.displayedSleepMinutes == 0 && store.dayActivities.isEmpty {
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
                        Image(systemName: "chevron.forward").font(.system(size: 9)).foregroundStyle(WColor.muted)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text(day.sleepNeededMinutes > 0 ? clockDuration(day.sleepNeededMinutes) : "NO TARGET")).font(WFont.number(day.sleepNeededMinutes > 0 ? 28 : 16, bold: true)).foregroundStyle(WColor.sleep)
                            Text(L10n.text("SLEEP NEEDED")).font(WFont.label(8)).foregroundStyle(WColor.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(L10n.text(day.displayedSleepMinutes > 0 ? clockDuration(day.displayedSleepMinutes) : "NO DATA")).font(WFont.number(day.displayedSleepMinutes > 0 ? 28 : 16, bold: true))
                            Text(L10n.text(day.usesConfirmedSleep ? "CONFIRMED SLEEP" : "RECORDED SLEEP")).font(WFont.label(8)).foregroundStyle(WColor.muted)
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
    @EnvironmentObject private var device: DeviceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var received: [HeartRateSample] = []
    @State private var showingReview = false

    private var day: DailySnapshot { store.selectedDay }

    private var liveReading: HeartRateSample? {
        guard let bpm = device.heartRate, let date = device.heartRateReceivedAt,
              DayCalendar.utc.isDate(date, inSameDayAs: day.date) else { return nil }
        return HeartRateSample(timestamp: date, bpm: bpm)
    }

    private var metrics: [HealthReading] {
        [
            HealthReading("RESPIRATORY RATE", day.respiratoryRate, "rpm", "lungs", precision: 1),
            HealthReading("BLOOD OXYGEN (SpO₂)", day.oxygenSaturation, "%", "drop"),
            HealthReading("RHR", day.restingHeartRate, "bpm", "heart"),
            HealthReading("HRV", day.hrv, "ms", "waveform.path.ecg"),
            HealthReading("SKIN TEMP", day.skinTemperatureCelsius, "°C", "thermometer.medium", precision: 1)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(L10n.text("HEALTH MONITOR"))
                    .font(WFont.label(13)).tracking(AppLanguage.isArabic ? 0 : 1.2)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward").font(.system(size: 23, weight: .medium))
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.text("Back"))
                    Spacer()
                }
            }.padding(.horizontal, ReferenceSize.pageInset).frame(minHeight: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heartRateHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11),
                                             count: typeSize.isAccessibilitySize ? 1 : 2),
                              alignment: .leading, spacing: 11) {
                        ForEach(metrics) { reading in healthTile(reading) }
                    }.padding(.horizontal, ReferenceSize.pageInset)

                    if let report {
                        VStack(alignment: .leading, spacing: 11) {
                            ShareLink(item: report, preview: SharePreview(L10n.text("Health report"))) {
                                Label(L10n.text("SHARE YOUR HEALTH REPORT"), systemImage: "square.and.arrow.up")
                                    .font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.9)
                                    .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .background(WColor.card, in: RoundedRectangle(cornerRadius: ReferenceSize.cardRadius))
                            }.accessibilityIdentifier("healthReportShare")
                            Text(L10n.text("Share a printable PDF of this day’s recorded measurements."))
                                .font(WFont.body(14)).foregroundStyle(WColor.muted)
                        }.padding(.horizontal, ReferenceSize.pageInset).padding(.top, 18)
                    }
                }.frame(maxWidth: 680).frame(maxWidth: .infinity).padding(.bottom, 88)
            }.scrollIndicators(.hidden)
        }
        .foregroundStyle(.white).buttonStyle(.plain).background(WhoopBackground())
        .overlay(alignment: .bottomTrailing) {
            DayReviewButton(action: { showingReview = true }).padding(.trailing, 12).padding(.bottom, 4)
        }
        .sheet(isPresented: $showingReview) { DayReviewView() }
        .onReceive(device.heartRateSamples) { sample in
            guard DayCalendar.utc.isDate(sample.timestamp, inSameDayAs: day.date) else { return }
            received.append(sample)
            if received.count > 120 { received.removeFirst(received.count - 120) }
        }
        .preferredColorScheme(.dark)
    }

    private var heartRateHeader: some View {
        let live = liveReading
        let saved = Array(day.heartRates.suffix(120))
        let last = live ?? saved.last
        let newSamples = received.filter { sample in
            saved.last.map { sample.timestamp > $0.timestamp } ?? true
        }
        var trace = Array((saved + newSamples).suffix(120))
        if let live, trace.last?.timestamp != live.timestamp { trace.append(live) }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("HEART RATE")).font(WFont.label(13)).tracking(AppLanguage.isArabic ? 0 : 0.9)
                Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(WColor.blue)
                if let last {
                    Text(decimalText(last.bpm, places: 0)).font(WFont.number(34, bold: true))
                    Text(L10n.text("BPM")).font(WFont.label(10)).foregroundStyle(WColor.muted)
                    Text(live == nil ? utcDateText(last.timestamp, style: .dateTime.hour().minute()) : L10n.text("LIVE"))
                        .font(WFont.body(12)).foregroundStyle(WColor.muted)
                } else {
                    Text(L10n.text("No heart-rate samples available")).font(WFont.body(13)).foregroundStyle(WColor.muted)
                }
            }.frame(width: typeSize.isAccessibilitySize ? nil : 95, alignment: .leading)
            if !trace.isEmpty {
                MonitorHeartRateTrace(samples: trace)
                    .accessibilityLabel(L10n.text("Heart rate overview from \(trace.count) samples"))
            } else { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
        .background {
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: CGFloat.zero, to: size.width, by: 14) {
                    grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height))
                }
                for y in stride(from: CGFloat.zero, to: size.height, by: 14) {
                    grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 0.75)
            }.mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom))
        }
    }

    private func healthTile(_ reading: HealthReading) -> some View {
        let available = reading.value != nil
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(L10n.text(reading.title)).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.65)
            } icon: {
                Image(systemName: reading.symbol).font(.system(size: 16, weight: .regular))
            }.foregroundStyle(WColor.muted)
            Spacer(minLength: 6)
            if available {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reading.formatted).font(WFont.number(32, bold: true))
                    Text(L10n.text(reading.unit)).font(WFont.body(14).weight(.semibold))
                }
            }
            Text(L10n.text(available ? "RECORDED" : "NOT AVAILABLE")).font(WFont.label(9))
                .foregroundStyle(WColor.muted).padding(.horizontal, 5).padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 117, alignment: .topLeading)
        .background(WColor.card, in: RoundedRectangle(cornerRadius: ReferenceSize.cardRadius, style: .continuous))
    }

    private var report: HealthDayReport? {
        var rows = metrics.filter { $0.value != nil }.map {
            "\(L10n.text($0.title))   \($0.formatted) \(L10n.text($0.unit))"
        }
        if let last = day.heartRates.last {
            let sampleTime = utcDateText(last.timestamp, style: .dateTime.hour().minute().second())
            rows.insert("\(L10n.text("HEART RATE"))   \(decimalText(last.bpm, places: 0)) \(L10n.text("BPM")) · \(sampleTime) UTC", at: 0)
        }
        guard !rows.isEmpty else { return nil }
        if day.source == .example { rows.insert(L10n.text("EXAMPLE DAY"), at: 0) }
        return HealthDayReport(date: utcDateText(day.date, style: .dateTime.year().month(.wide).day()), rows: rows)
    }
}

private struct HealthReading: Identifiable {
    var id: String { title }
    let title: String
    let value: Double?
    let unit: String
    let symbol: String
    let precision: Int
    var formatted: String { decimalText(value, places: precision) }

    init(_ title: String, _ value: Double?, _ unit: String, _ symbol: String, precision: Int = 0) {
        self.title = title
        self.value = value
        self.unit = unit
        self.symbol = symbol
        self.precision = precision
    }
}

private struct MonitorHeartRateTrace: View {
    let samples: [HeartRateSample]

    var body: some View {
        Canvas { context, size in
            guard let first = samples.first, let last = samples.last,
                  let minimum = samples.map(\.bpm).min(), let maximum = samples.map(\.bpm).max() else { return }
            let duration = max(1, last.timestamp.timeIntervalSince(first.timestamp))
            let height = max(1, size.height - 16)
            func point(_ reading: HeartRateSample) -> CGPoint {
                let x = 4 + (size.width - 8) * (1 - last.timestamp.timeIntervalSince(reading.timestamp) / duration)
                let y = 8 + height * (maximum + 6 - reading.bpm) / (maximum - minimum + 12)
                return CGPoint(x: x, y: y)
            }
            var trace = Path()
            var previous: HeartRateSample?
            for reading in samples {
                let mapped = point(reading)
                if let previous, reading.timestamp.timeIntervalSince(previous.timestamp) <= 90 {
                    trace.addLine(to: mapped)
                } else {
                    trace.move(to: mapped)
                    context.fill(Path(ellipseIn: CGRect(x: mapped.x - 1, y: mapped.y - 1, width: 2, height: 2)), with: .color(WColor.blue))
                }
                previous = reading
            }
            context.stroke(trace, with: .color(WColor.blue), lineWidth: 1.8)
            let end = point(last)
            var marker = Path()
            marker.move(to: .init(x: end.x, y: 4))
            marker.addLine(to: .init(x: end.x, y: size.height - 4))
            context.stroke(marker, with: .color(WColor.muted), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 3.5, y: end.y - 3.5, width: 7, height: 7)), with: .color(.white))
        }.frame(height: 104)
    }
}

private struct HealthDayReport: Transferable {
    let date: String
    let rows: [String]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { (report: HealthDayReport) in
            await MainActor.run { report.pdf() }
        }.suggestedFileName("Health-report.pdf")
    }

    @MainActor private func pdf() -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            let style = NSMutableParagraphStyle()
            style.alignment = AppLanguage.isArabic ? .right : .left
            style.baseWritingDirection = AppLanguage.isArabic ? .rightToLeft : .leftToRight
            func draw(_ text: String, y: CGFloat, font: UIFont) {
                (text as NSString).draw(in: CGRect(x: 44, y: y, width: page.width - 88, height: 52),
                                        withAttributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style])
            }
            draw(L10n.text("Health report"), y: 45, font: .boldSystemFont(ofSize: 26))
            draw(date + " UTC", y: 100, font: .systemFont(ofSize: 16))
            for (index, row) in rows.enumerated() {
                draw(row, y: 162 + 50 * CGFloat(index), font: .systemFont(ofSize: 15))
            }
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
    let openMonitor: () -> Void
    let importData: () -> Void
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
            Button(action: openMonitor) {
                WCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack { Text(L10n.text("HEALTH MONITOR")).font(WFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 0.8); Spacer(); Image(systemName: "chevron.forward").foregroundStyle(WColor.muted) }
                        HStack(spacing: 0) {
                            healthStatus("RESP", symbol: "lungs", available: store.selectedDay.respiratoryRate != nil)
                            healthStatus("SpO₂", symbol: "drop", available: store.selectedDay.oxygenSaturation != nil)
                            healthStatus("RHR", symbol: "heart", available: store.selectedDay.restingHeartRate != nil)
                            healthStatus("HRV", symbol: "waveform.path.ecg", available: store.selectedDay.hrv != nil)
                            healthStatus("TEMP", symbol: "thermometer.medium", available: store.selectedDay.skinTemperatureCelsius != nil)
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
                        Spacer(); Image(systemName: "chevron.forward").foregroundStyle(WColor.muted)
                    }
                }
            }.buttonStyle(.plain)
            Button(L10n.text("IMPORT YOUR WHOOP DATA"), action: importData).buttonStyle(WButton(filled: false))
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
