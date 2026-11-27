import SwiftUI
import Charts
import Combine
import WHOOPCore

struct MetricDetailView: View {
    @EnvironmentObject private var store: AppStore
        @Environment(\.dismiss) private var dismiss
    let metric: ScoreMetric
    var embedded = false
    @State private var showingInformation = false
    @State private var showingCoach = false
    @State private var trendDays = 7
    @State private var trendSelection: Date?
    private var day: DailySnapshot { store.selectedDay }
    private var previous: DailySnapshot? { precedingDay(in: store) }
    private var trend: [DailySnapshot] {
        store.days.filter { $0.source == day.source && $0.date <= day.date && $0.date >= trendStart && metric.value($0) != nil }.sorted { $0.date < $1.date }
    }
    private var trendStart: Date { DayCalendar.utc.date(byAdding: .day, value: -(trendDays - 1), to: day.date)! }
    var body: some View {
        VStack(spacing: 0) {
            if !embedded { header }
            if embedded { content } else { ScrollView { content }.scrollIndicators(.hidden) }
        }.background { WhoopBackground() }
            .alert(L10n.text("About this score"), isPresented: $showingInformation) {
                Button(L10n.text("Done"), role: .cancel) { }
            } message: { Text(L10n.text(metric.description + " A comparison marker shows the previous recorded UTC day when available. Missing fields are not inferred from summary scores.")) }
            .alert(L10n.text("WHOOP Coach"), isPresented: $showingCoach) {
                Button(L10n.text("Done"), role: .cancel) { }
            } message: { Text(L10n.text("WHOOP Coach is not connected in this edition. You can view your recorded measurements and activities here; personalized Coach responses are unavailable.")) }
    }
    private var content: some View {
                VStack(spacing: 23) {
                    ScoreRing(metric: metric, day: day, large: true,
                              comparisonFraction: previous.flatMap { metric.value($0) == nil ? nil : metric.fraction($0) })
                        .padding(.top, 13).padding(.bottom, 5)
                    Text(L10n.text(day.source == .example ? "EXAMPLE DATA · NOT PERSONAL MEASUREMENTS" : metric == .strain && day.strainIsLocalEstimate ? "LOCAL STRAIN ESTIMATE" : metric == .sleep && day.estimatedSleepMinutes != nil && day.sleepMinutes == 0 && day.confirmedSleep == nil ? "ESTIMATED SLEEP" : "SAVED MEASUREMENTS"))
                        .font(WFont.label(7)).tracking(AppLanguage.isArabic ? 0 : 0.9).foregroundStyle(WColor.muted)
                    if metric == .strain, let recording = day.trackerRecording {
                        WCard {
                            Text(L10n.text("Received readings") + ": " + recording.sampleCount.formatted()).font(WFont.body(14))
                            Text(L10n.text("Counted minutes") + ": " + (recording.observedSeconds / 60).formatted(.number.precision(.fractionLength(1)))).font(WFont.body(14))
                            Text(L10n.text("Only received heart-rate intervals contribute to the local estimate. Disconnected time and intervals still waiting for smoothing are excluded. Official WHOOP scores take priority when imported.")).font(WFont.body(12)).foregroundStyle(WColor.muted)
                        }
                    }
                    if metric == .sleep, day.source != .example, day.sleepMinutes == 0 || day.confirmedSleep != nil {
                        SleepReviewEntry(wakeDay: day.date, compact: false).id(day.date)
                    }
                    if metric == .sleep, let breakdown = day.sleepBreakdown { sleepStages(breakdown) }
                    WCard(padding: 16) { statistics }
                        .overlay(alignment: .top) {
                            StatisticsPointer().fill(WColor.card).frame(width: 18, height: 9).offset(y: -8)
                        }.padding(.top, 5)
                    DetailInsight(text: insight, actionTitle: "LEARN MORE WITH COACH") { showingCoach = true }
                    if metric == .strain {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.text("Today’s Activities")).font(WFont.number(24, bold: true))
                            ForEach(store.dayActivities) { activity in ReferenceActivityRow(activity: activity) }
                            if store.dayActivities.isEmpty {
                                Text(L10n.text("No activities recorded for this day.")).font(WFont.body(14)).foregroundStyle(WColor.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    trendCard
                    if !day.heartRates.isEmpty {
                        SectionHeading(title: "Heart rate")
                        WCard { HeartRateChart(samples: day.heartRates).frame(height: 160) }
                    }
                    Text(L10n.text(day.source == .example ? "These are illustrative measurements, not readings from your body." : "Unavailable measurements are shown as a dash. Supplied scores are preserved as recorded."))
                        .font(WFont.body(12)).foregroundStyle(WColor.muted).multilineTextAlignment(.center)
                }.padding(.horizontal, 17).padding(.bottom, 30).frame(maxWidth: 600).frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 25, weight: .light)).frame(width: 42, height: 44)
            }.accessibilityLabel(L10n.text("Back"))
            Spacer()
            DaySelector(compact: true).frame(width: ReferenceSize.dayStripWidth)
            Spacer()
            Button { showingInformation = true } label: {
                Image(systemName: "info.circle").font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(WColor.muted).frame(width: 42, height: 44)
            }.accessibilityLabel(L10n.text("About this score"))
        }.foregroundStyle(.white).padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 10)
    }

    @ViewBuilder private var statistics: some View {
        VStack(spacing: 0) {
            if metric == .recovery {
                ReferenceMetricRow(title: "Heart rate variability", value: decimalText(day.hrv, places: 0), symbol: "waveform.path.ecg", unit: "ms", difference: delta(day.hrv, previous?.hrv))
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Resting heart rate", value: decimalText(day.restingHeartRate, places: 0), symbol: "heart", difference: delta(day.restingHeartRate, previous?.restingHeartRate))
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Respiratory rate", value: decimalText(day.respiratoryRate), symbol: "lungs", difference: delta(day.respiratoryRate, previous?.respiratoryRate))
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep performance", value: day.sleepPerformance.map { "\($0)%" } ?? "—", symbol: "moon")
            } else if metric == .sleep {
                ReferenceMetricRow(title: "Hours vs. needed", value: sleepRatio, symbol: "clock")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep consistency", value: day.sleepBreakdown?.consistencyPercent.map { decimalText($0, places: 0) + "%" } ?? "—", symbol: "bed.double")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep efficiency", value: day.sleepBreakdown?.efficiencyPercent.map { decimalText($0, places: 0) + "%" } ?? "—", symbol: "bed.double")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Sleep debt", value: day.sleepBreakdown?.debtMinutes.map { clockDuration(Int($0.rounded())) } ?? "—", symbol: "clock.arrow.circlepath")
                HStack(spacing: 12) {
                    legend("Poor", color: WColor.yellow)
                    legend("Sufficient", color: WColor.muted)
                    legend("Optimal", color: .mint)
                }.padding(.top, 10).padding(.bottom, 3)
            } else {
                ReferenceMetricRow(title: "Heart rate zones 1–3", value: "—", symbol: "heart.text.square")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Heart rate zones 4–5", value: "—", symbol: "heart.text.square")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Strength training time", value: strengthMinutes.map { clockDuration($0) } ?? "—", symbol: "dumbbell")
                Divider().overlay(WColor.line)
                ReferenceMetricRow(title: "Average heart rate", value: decimalText(averageHeartRate, places: 0), symbol: "heart")
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.text("Trends")).font(WFont.number(22, bold: true))
            Picker(L10n.text("Trend period"), selection: $trendDays) {
                Text(L10n.text("7 DAYS")).tag(7); Text(L10n.text("30 DAYS")).tag(30); Text(L10n.text("90 DAYS")).tag(90)
            }.pickerStyle(.segmented).accessibilityIdentifier("metricTrendPeriod")
            WCard {
                if trend.isEmpty {
                    Text(L10n.text("No recorded scores in this period.")).font(WFont.body(14)).foregroundStyle(WColor.muted).frame(height: 145)
                } else {
                    Chart {
                        ForEach(trend) { item in
                            if let value = metric.value(item) {
                                BarMark(x: .value("Day", item.date, unit: .day), y: .value(metric.title, value))
                                    .foregroundStyle(metric == .recovery ? PulseColor.recoveryScore(Double(item.recovery ?? 0)) : metric.color)
                                    .cornerRadius(3)
                            }
                        }
                        if let trendSelection {
                            RuleMark(x: .value("Selected day", trendSelection)).foregroundStyle(.white.opacity(0.5))
                        }
                    }.frame(height: 145).chartYScale(domain: metric == .strain ? 0.0...21.0 : 0.0...100.0)
                        .chartXScale(domain: trendStart...DayCalendar.utc.date(byAdding: .day, value: 1, to: day.date)!)
                        .chartXSelection(value: $trendSelection)
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: trendDays == 7 ? 7 : 4)) { _ in AxisValueLabel(format: utcDateFormat(.dateTime.month(.abbreviated).day())).foregroundStyle(WColor.muted) } }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(WColor.line); AxisValueLabel().foregroundStyle(WColor.muted) } }
                        .accessibilityLabel(L10n.text(metric.title) + ", " + L10n.text("\(trend.count) recorded days"))
                    if let date = trendSelection, let selected = trend.first(where: { DayCalendar.start(of: $0.date) == DayCalendar.start(of: date) }) {
                        Text(utcDateText(selected.date, style: .dateTime.month(.abbreviated).day()) + " · " + metric.text(selected)).font(WFont.body(14))
                    }
                    let average = trend.compactMap { metric.value($0) }.reduce(0, +) / Double(trend.count)
                    HStack {
                        Text(L10n.text("Daily average")).font(WFont.body(13)).foregroundStyle(WColor.muted)
                        Spacer()
                        Text(decimalText(average, places: metric == .strain ? 1 : 0) + (metric == .strain ? "" : "%")).font(WFont.number(20, bold: true))
                    }
                }
            }
        }.onChange(of: trendDays) { _, _ in trendSelection = nil }
    }
    private func sleepStages(_ details: SleepBreakdown) -> some View {
        let stages: [(String, Double?, Color)] = [("Awake", details.awakeMinutes, WColor.muted), ("Light", details.lightMinutes, WColor.sleep),
                                                   ("Deep (SWS)", details.deepMinutes, Color.purple), ("REM", details.remMinutes, Color.cyan)]
        let total = stages.compactMap { $0.1 }.reduce(0, +)
        return WCard {
            Text(L10n.text("SLEEP STAGES")).font(WFont.label(12))
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(stages, id: \.0) { item in
                            if let value = item.1, value > 0 { Rectangle().fill(item.2).frame(width: geometry.size.width * value / total) }
                        }
                    }
                }.frame(height: 10).clipShape(Capsule()).accessibilityHidden(true)
            }
            ForEach(stages, id: \.0) { item in
                HStack {
                    Circle().fill(item.2).frame(width: 8, height: 8)
                    Text(L10n.text(item.0)).font(WFont.body(15))
                    Spacer()
                    Text(item.1.map { clockDuration(Int($0.rounded())) } ?? "—").font(WFont.number(19, bold: true))
                }.accessibilityElement(children: .combine)
            }
        }
    }
    private var insight: String {
        if metric == .strain, day.strainIsLocalEstimate { return "This local Strain estimate uses received heart-rate intervals and your configured heart-rate limits. It is not an official WHOOP score and does not cover gaps in recording." }
        guard metric.value(day) != nil else { return "Your score will appear here when it is included in your recorded data. Heart-rate samples alone do not supply this score." }
        if metric == .strain, let strain = day.strain {
            if strain >= 14 && strain < 18 { return "Strain between 14 and 17.9 is considered strenuous, meaning your cardiovascular system has been working hard." }
            return "Your recorded Day Strain is \(decimalText(strain)) on a 0–21 scale. Review your activities and measurements to see the context of your day."
        }
        if metric == .sleep {
            guard day.sleepMinutes > 0, day.sleepNeededMinutes > 0 else { return "Your Sleep Performance score is shown as supplied. Sleep duration or sleep need is unavailable for this day." }
            return "You recorded \(durationText(day.sleepMinutes)) of sleep against \(durationText(day.sleepNeededMinutes)) of sleep need. Your Sleep Performance score is preserved as supplied."
        }
        return "View your recorded HRV, resting heart rate, respiratory rate and Sleep Performance alongside your Recovery score. Missing measurements are left blank."
    }
    private var sleepRatio: String {
        guard day.sleepMinutes > 0, day.sleepNeededMinutes > 0 else { return "—" }
        return "\(clockDuration(day.sleepMinutes)) / \(clockDuration(day.sleepNeededMinutes))"
    }
    private var strengthMinutes: Int? {
        let rows = store.dayActivities.filter { $0.name.localizedCaseInsensitiveContains("strength") }
        return rows.isEmpty ? nil : rows.reduce(0) { $0 + $1.durationMinutes }
    }
    private var averageHeartRate: Double? {
        guard !day.heartRates.isEmpty else { return nil }
        return day.heartRates.map(\.bpm).reduce(0, +) / Double(day.heartRates.count)
    }
    private func delta(_ value: Double?, _ previous: Double?) -> Double? {
        guard let value, let previous else { return nil }; return value - previous
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 11, height: 3)
            Text(L10n.text(title)).font(WFont.body(10)).foregroundStyle(WColor.muted)
        }
    }
}

private struct StatisticsPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath()
        return path
    }
}

struct DetailValueRow: View {
    let title: String
    let value: String
    var color: Color = .white
    var body: some View {
        HStack {
            Text(L10n.text(title)).font(WFont.body(15)).foregroundStyle(WColor.muted)
            Spacer(); Text(L10n.text(value)).font(WFont.number(27, bold: true)).foregroundStyle(color)
        }
    }
}

struct JournalEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var caffeine = false
    @State private var alcohol = false
    @State private var lateMeal = false
    @State private var note = ""
    @State private var confirmDelete = false
    var body: some View {
        SheetScaffold(title: "DAILY JOURNAL") {
            VStack(alignment: .leading, spacing: 22) {
                Text(L10n.text(utcDateText(store.selectedDate, style: Date.FormatStyle(date: .complete, time: .omitted)))).font(WFont.body(14)).foregroundStyle(WColor.muted)
                Text(L10n.text("WHAT SHAPED\nYOUR DAY?")).font(WFont.number(35, bold: true))
                Text(L10n.text("Build a record of your habits. Your answers stay on this iPhone.")).font(WFont.body(16)).foregroundStyle(WColor.muted)
                WCard {
                    Toggle(L10n.text("Consumed caffeine"), isOn: $caffeine).padding(.vertical, 8)
                    Divider().padding(.vertical, 10)
                    Toggle(L10n.text("Consumed alcohol"), isOn: $alcohol).padding(.vertical, 8)
                    Divider().padding(.vertical, 10)
                    Toggle(L10n.text("Ate close to bedtime"), isOn: $lateMeal).padding(.vertical, 8)
                }.tint(WColor.green)
                SectionHeading(title: "Anything else?")
                TextEditor(text: $note).font(WFont.body(16)).scrollContentBackground(.hidden)
                    .frame(minHeight: 140).padding(12).background(WColor.card, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(L10n.text("Journal notes"))
                    .onChange(of: note) { _, value in if value.count > LocalBackupCodec.maximumNoteCharacters { note = String(value.prefix(LocalBackupCodec.maximumNoteCharacters)) } }
                Text(L10n.text("\(note.count)/\(LocalBackupCodec.maximumNoteCharacters) characters")).font(WFont.body(12)).foregroundStyle(WColor.muted)
                Button(L10n.text("SAVE JOURNAL")) {
                    store.saveJournal(JournalEntry(date: store.selectedDate, caffeine: caffeine, alcohol: alcohol, lateMeal: lateMeal, note: note))
                    dismiss()
                }.buttonStyle(WButton())
                Button(L10n.text("Delete this journal entry"), role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity)
            }
        }.confirmationDialog(L10n.text("Delete this day's journal entry?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.text("Delete entry"), role: .destructive) { store.deleteJournal(); dismiss() }
        }.onAppear {
            let entry = store.currentJournal
            caffeine = entry.caffeine; alcohol = entry.alcohol; lateMeal = entry.lateMeal; note = entry.note
        }
    }
}

struct ActivityEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var activity = "Running"
    @State private var customName = ""
    @State private var minutes = 30
    private let types = ["Running", "Strength training", "Cycling", "Walking", "Swimming", "Yoga", "Other"]
    private var name: String { activity == "Other" ? customName.trimmingCharacters(in: .whitespacesAndNewlines) : activity }
    var body: some View {
        SheetScaffold(title: "LOG ACTIVITY") {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.text("MAKE YOUR\nMOVEMENT COUNT.")).font(WFont.number(35, bold: true))
                Text(L10n.text(utcDateText(store.selectedDate, style: Date.FormatStyle(date: .complete, time: .omitted)))).font(WFont.body(15)).foregroundStyle(WColor.muted)
                WCard {
                    HStack {
                        Text(L10n.text("Activity")).font(WFont.body(16)); Spacer()
                        Picker(L10n.text("Activity"), selection: $activity) { ForEach(types, id: \.self) { Text(L10n.text($0)).tag($0) } }.tint(WColor.blue)
                    }
                    if activity == "Other" {
                        Divider().padding(.vertical, 10)
                        TextField(L10n.text("Activity name"), text: $customName).textInputAutocapitalization(.words).font(WFont.body(16))
                    }
                    Divider().padding(.vertical, 14)
                    Stepper(value: $minutes, in: 1...600, step: 1) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("Duration")).font(WFont.body(15)).foregroundStyle(WColor.muted)
                            Text(L10n.text(durationText(minutes))).font(WFont.number(27, bold: true))
                        }
                    }.tint(.white)
                }
                Text(L10n.text("This records an activity and its duration. It does not add an estimated strain or calorie score."))
                    .font(WFont.body(14)).foregroundStyle(WColor.muted)
                Button(L10n.text("SAVE ACTIVITY")) { store.logActivity(name: name, minutes: minutes); dismiss() }
                    .buttonStyle(WButton()).disabled(name.isEmpty)
            }
        }
    }
}

struct DeviceSheetView: View {
    @EnvironmentObject private var device: DeviceModel
    var body: some View {
        SheetScaffold(title: "DEVICE CONNECTION") {
            VStack(spacing: 22) {
                Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(WColor.blue).padding(.vertical, 16)
                SectionHeading(title: device.connectedName ?? "Connect a device", subtitle: device.status)
                if let name = device.connectedName {
                    WCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(name).font(WFont.number(23, bold: true))
                                Text(L10n.text("CONNECTED")).font(WFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 0.8).foregroundStyle(WColor.green)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(L10n.text(decimalText(device.heartRate, places: 0))).font(WFont.number(39, bold: true))
                                Text(L10n.text("LIVE BPM")).font(WFont.label(9)).foregroundStyle(WColor.muted)
                            }
                        }
                    }
                    if device.canStartCustomStream || device.startingCustomStream {
                        Button(L10n.text(device.startingCustomStream ? "STARTING LIVE HEART RATE…" : "START DEVICE HEART RATE")) {
                            device.startCustomStream()
                        }.buttonStyle(WButton()).disabled(device.startingCustomStream)
                        Text(L10n.text("This optional request uses a recovered device protocol and still needs physical-strap testing. It does not sync history or validate the full device initialization sequence."))
                            .font(WFont.body(13)).foregroundStyle(WColor.muted)
                    }
                    Button(L10n.text("DISCONNECT")) { device.disconnect() }.buttonStyle(WButton(filled: false))
                } else {
                    Button(L10n.text(device.isScanning ? "STOP SEARCHING" : "SEARCH FOR DEVICES")) {
                        if device.isScanning { device.stop() } else { device.scan() }
                    }.buttonStyle(WButton())
                }
                if device.isScanning { ProgressView().tint(WColor.blue).accessibilityLabel(L10n.text("Searching nearby Bluetooth devices")) }
                if !device.devices.isEmpty {
                    SectionHeading(title: "Nearby devices")
                    ForEach(device.devices) { item in
                        Button { device.connect(item) } label: {
                            WCard {
                                HStack(spacing: 12) {
                                    Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(WColor.blue)
                                    Text(item.name).font(WFont.body(16))
                                    Spacer(); Text(L10n.text("\(item.rssi) dBm")).font(WFont.body(11)).foregroundStyle(WColor.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 10))
                                }
                            }
                        }.buttonStyle(.plain).disabled(device.connectedName != nil)
                    }
                } else if !device.isScanning && device.connectedName == nil {
                    EmptyCard(symbol: "dot.radiowaves.left.and.right", title: "Find your heart-rate source", detail: "Keep your device nearby and turn on heart-rate broadcasting, if available.")
                }
                if let history = device.lastHistoryRecord {
                    WCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("HISTORICAL NOTIFICATIONS")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                            Text(L10n.text("\(device.historicalFrames) received · revision \(history.rawRevision)"))
                                .font(WFont.body(14)).foregroundStyle(WColor.muted)
                            if let counter = history.packetCounter { Text(L10n.text("Packet counter \(counter)")).font(WFont.body(13)) }
                            if let time = history.deviceTime,
                               let date = time.validatedDate(in: Date(timeIntervalSince1970: 946_684_800)...Date().addingTimeInterval(86_400)) {
                                Text(L10n.text("Device time: \(utcDateText(date, style: .dateTime.year().month().day().hour().minute().second())) UTC"))
                                    .font(WFont.body(13))
                            }
                            Text(L10n.text("Only the common packet header is decoded. No historical heart rate is inferred, and no transfer acknowledgement or erase command is sent."))
                                .font(WFont.body(13)).foregroundStyle(WColor.muted)
                            ShareLink(item: history.rawFrame.base64EncodedString()) {
                                Label(L10n.text("Share latest raw frame text"), systemImage: "square.and.arrow.up")
                            }.font(WFont.body(14))
                        }
                    }
                }
                WCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.text("ABOUT THIS CONNECTION")).font(WFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.8)
                        Text(L10n.text("Live heart rate can use standard Bluetooth broadcasts or validated WHOOP notifications when the device streams them. A connection does not sync history or generate daily Recovery and sleep scores."))
                            .font(WFont.body(14)).foregroundStyle(WColor.muted)
                    }
                }
            }
        }
    }
}

struct SleepReviewEntry: View {
    @EnvironmentObject private var store: AppStore
    let wakeDay: Date
    let compact: Bool
    @State private var suggestion: DateInterval?
    @State private var editing = false
    private var day: DailySnapshot { store.selectedDay }

    var body: some View {
        Group {
            if day.source != .example && (!compact || (day.sleepMinutes == 0 && (suggestion != nil || day.confirmedSleep != nil))) {
                Button { editing = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bed.double").foregroundStyle(WColor.sleep)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text(day.confirmedSleep != nil ? "Your confirmed sleep" : suggestion != nil ? "Review overnight rest" : "Log sleep"))
                                .font(WFont.body(16).weight(.semibold))
                            if let saved = day.confirmedSleep {
                                Text(clockDuration(saved.minutes)).font(WFont.number(20, bold: true))
                            } else if let suggestion {
                                Text(suggestion.start.formatted(date: .omitted, time: .shortened) + " – " + suggestion.end.formatted(date: .omitted, time: .shortened))
                                    .font(WFont.body(14)).foregroundStyle(WColor.muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").foregroundStyle(WColor.muted)
                    }.padding(16).background(WColor.card, in: RoundedRectangle(cornerRadius: ReferenceSize.cardRadius))
                }.buttonStyle(.plain).accessibilityIdentifier("sleepReviewEntry")
            }
        }
        .task(id: wakeDay) {
            let key = DayCalendar.start(of: wakeDay)
            for await (days, activities) in store.$days.combineLatest(store.$activities).values {
                guard !Task.isCancelled else { return }
                let selected = days.first { $0.date == key }
                guard selected?.source != .example, selected?.confirmedSleep == nil,
                      (selected?.sleepMinutes ?? 0) == 0 else {
                    suggestion = nil
                    continue
                }
                let next = await Task.detached(priority: .utility) {
                    OvernightRest.candidate(wakeDay: key, days: days, activities: activities)
                }.value
                guard !Task.isCancelled else { return }
                suggestion = next
            }
        }
        .sheet(isPresented: $editing) {
            SleepLogEditor(wakeDay: wakeDay, saved: day.confirmedSleep, suggestion: suggestion)
        }
    }
}

private struct SleepLogEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let wakeDay: Date
    let saved: ConfirmedSleep?
    let suggestion: DateInterval?
    let timeZone: TimeZone
    @State private var start: Date
    @State private var end: Date
    @State private var message: String?
    @State private var confirmDelete = false

    init(wakeDay: Date, saved: ConfirmedSleep?, suggestion: DateInterval?) {
        self.wakeDay = wakeDay
        self.saved = saved
        self.suggestion = suggestion
        let zone = saved.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .autoupdatingCurrent
        timeZone = zone
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        var parts = DayCalendar.utc.dateComponents([.year, .month, .day], from: wakeDay)
        parts.hour = 7
        let proposedWake = min(local.date(from: parts) ?? Date(), Date())
        _end = State(initialValue: saved?.end ?? suggestion?.end ?? proposedWake)
        _start = State(initialValue: saved?.start ?? suggestion?.start ?? proposedWake.addingTimeInterval(-8 * 3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                if suggestion != nil, saved == nil {
                    Text(L10n.text("Your tracker recorded a resting period. Adjust the times and confirm only the time you were asleep."))
                }
                DatePicker(L10n.text("Fell asleep"), selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                DatePicker(L10n.text("Woke up"), selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                let entry = ConfirmedSleep(start: start, end: end, timeZone: timeZone)
                let valid = (try? entry.validate(on: wakeDay, now: Date())) != nil
                if valid { LabeledContent(L10n.text("Confirmed duration"), value: clockDuration(entry.minutes)) }
                else { Text(L10n.text("Choose a sleep interval of 1 minute to 24 hours that ends on the selected day and has already finished.")) }
                Button(L10n.text("I was asleep · Save")) { save(entry) }.disabled(!valid)
                if saved != nil {
                    Button(L10n.text("Remove confirmed sleep"), role: .destructive) { confirmDelete = true }
                }
                if let message { Text(L10n.text(message)).foregroundStyle(.orange) }
            }
            .navigationTitle(L10n.text("Sleep log")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } } }
            .confirmationDialog(L10n.text("Remove confirmed sleep"), isPresented: $confirmDelete) {
                Button(L10n.text("Delete"), role: .destructive) { save(nil) }
            }
        }
        .environment(\.timeZone, timeZone)
    }

    private func save(_ value: ConfirmedSleep?) {
        do { try store.setConfirmedSleep(value, on: wakeDay); dismiss() }
        catch { message = error.localizedDescription }
    }
}
