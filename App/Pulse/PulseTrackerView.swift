import SwiftUI
import WHOOPCore
import UIKit

/// Pairing and sync use the same components in setup and Device Settings.
/// No demonstration measurements or simulated connection successes are used here.
struct PulseTrackerView: View {
    @EnvironmentObject private var tracker: DeviceModel
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dailyTracker: DailyTrackerRecorder
    @AppStorage(WhoopScoreDisplay.estimatePreferenceKey) private var showLocalEstimates = false
    @AppStorage(DailyTrackerRecorder.restingKey) private var localResting = 55.0
    @AppStorage(DailyTrackerRecorder.maximumKey) private var localMaximum = 190.0
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false
    @State private var sleepSettings = false
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 30) {
                        sectionTab("STATUS", selected: !advanced) { advanced = false }
                        sectionTab("ADVANCED", selected: advanced) { advanced = true }
                        Spacer()
                    }
                    if advanced {
                        automaticTrackingCard
                        diagnostics
                        Button(L10n.text("OPEN BLUETOOTH PERMISSIONS")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(WButton(filled: false))
                        if tracker.connectedName != nil {
                            Button(L10n.text("DISCONNECT")) { tracker.disconnect() }.buttonStyle(WButton(filled: false))
                        }
                    } else {
                        TrackerConnectionPanel()
                        TrackerSyncPanel()
                        Button { sleepSettings = true } label: {
                            Label(L10n.text("AUTOMATIC SLEEP"), systemImage: "moon.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(WButton(filled: false))
                        Button { exporting = true } label: {
                            Label(L10n.text("EXPORT DATA"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(WButton(filled: false)).accessibilityIdentifier("trackerExportData")
                    }
                }.padding(ReferenceSize.pageInset).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
                .background(LinearGradient(colors: [PulseColor.top, PulseColor.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                .navigationTitle(L10n.text("DEVICE SETTINGS")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Done"))
                } }
                .toolbarBackground(PulseColor.top, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.font(PulseFont.body(15)).foregroundStyle(PulseColor.text).tint(.white).preferredColorScheme(.dark)
            .sheet(isPresented: $sleepSettings) { HealthImportView() }
            .sheet(isPresented: $exporting) { MeasurementExportView() }
            .onDisappear { tracker.stop() }
    }

    private func sectionTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(L10n.text(title)).font(PulseFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 1)
                Rectangle().fill(selected ? PulseColor.text : .clear).frame(height: 2)
            }.fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(selected ? PulseColor.text : PulseColor.muted)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var diagnostics: some View {
        PulseCard {
            Text(L10n.text("CONNECTION DETAILS")).font(PulseFont.label(11))
            Text(L10n.text(tracker.status)).font(PulseFont.body(14))
            Text(L10n.text("Archived packets") + ": " + tracker.savedDeviceHistory.packets.formatted())
            Text(L10n.text("Recorded beat intervals") + ": " + tracker.savedDeviceHistory.rrIntervals.formatted())
            Text(L10n.text("Listen for standard Bluetooth heart-rate broadcasts, or try the selected WHOOP service families already implemented. Individual WHOOP 4.0, 5.0 and MG compatibility has not been verified on physical devices."))
                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            Text(L10n.text("Live heart rate is saved automatically. Stored tracker packets can be downloaded and exported. Optional local estimates are calculations, not WHOOP scores. Official Recovery, Sleep and Strain still require WHOOP account data."))
                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            Text(L10n.text("Only received intervals count. Saved charts retain one actual reading per minute. Bluetooth background delivery depends on iOS; force-quitting the app or losing connection leaves gaps. Stored tracker history is downloaded separately using Download from tracker."))
                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            Text(L10n.text("The complete packet batch is saved before receipt is confirmed to the band. Charts show one actual heart-rate record per minute. Unknown fields stay raw; they are not converted into invented health measurements."))
                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
        }
    }

    private var automaticTrackingCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("RECEIVED LIVE READINGS")).font(PulseFont.label())
                if let recording = store.days.first(where: { $0.date == DayCalendar.start(of: Date()) })?.trackerRecording {
                    Text(L10n.text("Received readings") + ": " + recording.sampleCount.formatted()).font(PulseFont.body(15))
                    Text(L10n.text("Counted minutes") + ": " + (recording.observedSeconds / 60).formatted(.number.precision(.fractionLength(1)))).font(PulseFont.body(13))
                    Text(L10n.text("Last saved") + ": " + recording.lastSampleAt.formatted(date: .omitted, time: .standard)).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                    if showLocalEstimates {
                        Text(L10n.text("LOCAL STRAIN ESTIMATE") + ": " + decimalText(recording.strainEstimate)).font(PulseFont.body(15))
                    }
                } else {
                    Text(L10n.text("Automatic recording starts with the first received heart-rate reading. The local estimate needs at least 32 fresh readings.")).font(PulseFont.body(13))
                }
                if let error = dailyTracker.error {
                    Text(L10n.text("Automatic recording could not be saved.") + " " + error).font(PulseFont.body(13)).foregroundStyle(.orange)
                    Button(L10n.text("RETRY SAVE")) { dailyTracker.flush() }.frame(minHeight: 44)
                }
                Button(L10n.text("VIEW TODAY’S TRACKING")) {
                    store.selectedDate = DashboardDatePolicy.today(); store.tab = .home; dismiss()
                }.frame(minHeight: 44)
                Toggle(L10n.text("Show local Strain estimates"), isOn: $showLocalEstimates).frame(minHeight: 44)
                if showLocalEstimates {
                    Stepper(value: $localResting, in: 30...110) { Text(L10n.text("Resting HR") + ": " + Int(localResting).formatted()) }
                    Stepper(value: $localMaximum, in: 120...230) { Text(L10n.text("Maximum HR") + ": " + Int(localMaximum).formatted()) }
                    Text(L10n.text("Set your known heart-rate limits. Defaults are 55 and 190 BPM; they are assumptions, not measured baselines. Changes apply to new readings.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                }
            }
        }
    }

}

/// A single, small pairing surface shared by first launch and device settings.
struct TrackerConnectionPanel: View {
    @EnvironmentObject private var tracker: DeviceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let name = tracker.connectedName {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("CONNECTED TO")).font(PulseFont.label(10)).foregroundStyle(PulseColor.mint).tracking(AppLanguage.isArabic ? 0 : 1)
                    Text(name).font(PulseFont.label(20))
                }.accessibilityIdentifier("trackerConnectedName")
            }
            TrackerBandArtwork().frame(height: tracker.connectedName == nil ? 220 : 200).accessibilityHidden(true)
            if tracker.connectedName != nil {
                connectionCheck
                if tracker.canStartCustomStream || tracker.startingCustomStream {
                    Button(L10n.text(tracker.startingCustomStream ? "STARTING HEART RATE…" : "ENABLE LIVE HEART RATE")) { tracker.startCustomStream() }
                        .buttonStyle(WButton(filled: false)).disabled(tracker.startingCustomStream)
                }
            } else {
                Text(L10n.text("Wear your tracker and keep it near your iPhone."))
                    .font(PulseFont.body(16)).foregroundStyle(PulseColor.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if tracker.isScanning || tracker.isConnecting {
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(L10n.text(tracker.isConnecting ? "Connecting to your tracker…" : "Searching for your tracker…"))
                    }.font(PulseFont.body(15)).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("trackerSearchProgress")
                }
                if !tracker.devices.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(tracker.devices) { item in
                            Button { tracker.connect(item) } label: {
                                PulseCard {
                                    HStack(spacing: 12) {
                                        Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(PulseColor.sleep)
                                        Text(item.name).font(PulseFont.body(17).weight(.semibold))
                                        Spacer()
                                        Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold))
                                    }.frame(minHeight: 44)
                                }
                            }.buttonStyle(.plain).disabled(tracker.isConnecting).accessibilityLabel(L10n.text("Connect to \(item.name)"))
                        }
                    }
                }
                if tracker.isConnecting {
                    Button(L10n.text("CANCEL CONNECTION")) { tracker.disconnect() }.buttonStyle(WButton(filled: false))
                } else {
                    Button(L10n.text(tracker.isScanning ? "STOP SEARCHING" : "SEARCH FOR MY TRACKER")) {
                        if tracker.isScanning { tracker.stop() } else { tracker.scan() }
                    }.buttonStyle(WButton()).accessibilityIdentifier("setupSearchTracker")
                }
                if !tracker.isScanning && !tracker.isConnecting {
                    Text(L10n.text(tracker.status)).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).accessibilityIdentifier("setupTrackerStatus")
                }
            }
        }
    }

    private var connectionCheck: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let evidence = TrackerConnectionEvidence(connected: tracker.connectedName != nil, connecting: tracker.isConnecting,
                                                     heartRate: tracker.heartRate, receivedAt: tracker.heartRateReceivedAt, now: timeline.date)
            let offBody = tracker.wearState == .offBody
            PulseCard {
                HStack(spacing: 16) {
                    Image(systemName: evidence.state == .receiving ? "heart.fill" : "waveform.path.ecg")
                        .font(.system(size: 26)).foregroundStyle(evidence.state == .receiving ? PulseColor.load : PulseColor.muted)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text(offBody ? "Tracker off body" : evidence.state == .receiving ? "RECEIVING DATA" : "WAITING FOR LIVE DATA"))
                            .font(PulseFont.label(11)).foregroundStyle(evidence.state == .receiving ? PulseColor.mint : PulseColor.muted)
                        if let bpm = evidence.liveHeartRate {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(decimalText(bpm, places: 0)).font(PulseFont.number(40)).monospacedDigit().contentTransition(.numericText())
                                Text(L10n.text("BPM")).font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                            }
                        } else {
                            Text(L10n.text(offBody ? "Put your strap back on to resume readings." : "Keep your tracker on your wrist.")).font(PulseFont.body(15))
                        }
                    }
                    Spacer(minLength: 0)
                    if evidence.state == .receiving { Image(systemName: "checkmark.circle.fill").foregroundStyle(PulseColor.mint) }
                    else if offBody { Image(systemName: "exclamationmark.circle").foregroundStyle(WColor.yellow) }
                    else { ProgressView().tint(.white) }
                }.frame(minHeight: 62).accessibilityElement(children: .combine).accessibilityIdentifier("trackerLiveCheck")
                if evidence.state != .receiving {
                    DisclosureGroup(L10n.text("HAVING TROUBLE?")) {
                        Text(L10n.text(tracker.status)).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted).padding(.top, 8)
                    }.font(PulseFont.label(10)).tint(PulseColor.muted)
                }
            }
        }
    }
}

/// Download and export are part of the same flow, never competing setup routes.
struct TrackerSyncPanel: View {
    @EnvironmentObject private var tracker: DeviceModel
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dailyTracker: DailyTrackerRecorder
    var body: some View {
        PulseCard {
            HStack {
                Text(L10n.text("YOUR TRACKER DATA")).font(PulseFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 1)
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(PulseColor.sleep)
            }
            if let recording = store.days.first(where: { $0.date == DayCalendar.start(of: Date()) })?.trackerRecording {
                HStack {
                    Text(L10n.text("Readings saved today (UTC)")).font(PulseFont.body(15))
                    Spacer()
                    Text(recording.sampleCount.formatted()).font(PulseFont.number(24))
                }
                Text(L10n.text("Last saved") + ": " + recording.lastSampleAt.formatted(date: .omitted, time: .shortened))
                    .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            }
            if let error = dailyTracker.error {
                Text(L10n.text("Automatic recording could not be saved.") + " " + error).font(PulseFont.body(13)).foregroundStyle(.orange)
                Button(L10n.text("RETRY SAVE")) { dailyTracker.flush() }.frame(minHeight: 44)
            }
            Text(L10n.text(tracker.historyStatus)).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
            if let error = tracker.historyPreviewError {
                Text(L10n.text("The full raw data is saved, but the chart preview could not update.") + " " + error).font(PulseFont.body(12)).foregroundStyle(.orange)
            }
            if tracker.canDownloadHistory || tracker.isDownloadingHistory {
                Toggle(L10n.text("Automatically sync stored readings"), isOn: Binding(
                    get: { tracker.automaticHistoryEnabled }, set: tracker.setAutomaticHistory
                )).tint(PulseColor.mint)
                Text(L10n.text("This iPhone saves each batch before confirming receipt to the strap. Stored readings can fill gaps after reconnection."))
                    .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            }
            if tracker.isDownloadingHistory {
                ProgressView(L10n.text("Downloading tracker records…")).tint(PulseColor.sleep).frame(minHeight: 44)
                Button(L10n.text("STOP & DISCONNECT")) { tracker.stopHistoryDownload() }.buttonStyle(WButton(filled: false))
            } else if tracker.canDownloadHistory {
                Button(L10n.text("SYNC TRACKER")) { tracker.downloadDeviceHistory() }
                    .buttonStyle(WButton()).accessibilityIdentifier("trackerSync")
            } else {
                Text(L10n.text(tracker.connectedName == nil ? "Connect your tracker to sync its stored readings." : "Full tracker sync is not available on this connection."))
                    .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            }
            if tracker.savedDeviceHistory.batches > 0 {
                Label(L10n.text("Saved on this iPhone") + ": " + tracker.savedDeviceHistory.heartRateRecords.formatted(), systemImage: "checkmark.circle.fill")
                    .font(PulseFont.body(14)).foregroundStyle(PulseColor.mint)
                Button(L10n.text(tracker.isExportingHistory ? "PREPARING ARCHIVE…" : "EXPORT TRACKER ARCHIVE")) { tracker.exportDeviceHistory() }
                    .buttonStyle(WButton(filled: false)).disabled(tracker.isExportingHistory || tracker.isDownloadingHistory)
                if let url = tracker.historyExportURL {
                    ShareLink(item: url) { Label(L10n.text("SAVE OR SHARE ARCHIVE"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                }
                Text(L10n.text("Raw tracker history uses this ZIP export and is separate from the app’s JSON backup."))
                    .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            }
        }.task { tracker.refreshHistorySummary() }
    }
}

/// Lightweight shared vector artwork; it never implies a measured battery level.
struct TrackerBandArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 78).stroke(Color(white: 0.06), lineWidth: 55).frame(width: 126, height: 230)
                RoundedRectangle(cornerRadius: 78).stroke(Color(white: 0.19), style: StrokeStyle(lineWidth: 49, dash: [1, 3])).frame(width: 126, height: 230)
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12), Color(white: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 153, height: 87)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14), lineWidth: 1))
                    .overlay(WhoopWordmark().frame(width: 85, height: 17).opacity(0.55)).offset(y: -59)
            }.rotationEffect(.degrees(-24)).scaleEffect(min(geometry.size.width / 275, geometry.size.height / 310))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
