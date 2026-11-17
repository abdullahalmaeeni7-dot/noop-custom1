import SwiftUI
import WHOOPCore
import UIKit

/// Reuses the existing CoreBluetooth adapter. This panel never reads mock measurements.
struct PulseTrackerView: View {
    @EnvironmentObject private var tracker: DeviceModel
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dailyTracker: DailyTrackerRecorder
    @AppStorage(WhoopScoreDisplay.estimatePreferenceKey) private var showLocalEstimates = false
    @AppStorage(DailyTrackerRecorder.restingKey) private var localResting = 55.0
    @AppStorage(DailyTrackerRecorder.maximumKey) private var localMaximum = 190.0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 36, weight: .light)).foregroundStyle(PulseColor.load)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.text(tracker.connectedName ?? "Connect your tracker")).font(PulseFont.body(23).weight(.semibold))
                            Text(L10n.text(tracker.connectedName == nil ? "Bluetooth connection" : "Bluetooth link connected")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                        }
                    }
                    PulseCard {
                        Text(L10n.text(tracker.status)).font(PulseFont.body(14)).fixedSize(horizontal: false, vertical: true).accessibilityLabel(L10n.text("Tracker status: ") + tracker.status)
                    }
                    if tracker.connectedName != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            PulseCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.text("LIVE HEART RATE")).font(PulseFont.label()).tracking(AppLanguage.isArabic ? 0 : 0.8)
                                    if let bpm = tracker.heartRate, let date = tracker.heartRateReceivedAt,
                                       (0...10).contains(timeline.date.timeIntervalSince(date)) {
                                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                                            Text(L10n.text(bpm.formatted(.number.locale(AppLanguage.current.locale).precision(.fractionLength(0))))).font(PulseFont.number(44)).monospacedDigit()
                                            Text(L10n.text("BPM")).font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                                        }.accessibilityElement(children: .combine).accessibilityLabel(L10n.text("Live heart rate, \(Int(bpm)) beats per minute"))
                                        Text(L10n.text("Received from your connected tracker")).font(PulseFont.body(11)).foregroundStyle(PulseColor.mint)
                                    } else {
                                        Text(L10n.text("Waiting for a fresh heart-rate sample")).font(PulseFont.body(17).weight(.semibold))
                                        Text(L10n.text("A Bluetooth link alone does not confirm a live data stream.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if tracker.canStartCustomStream || tracker.startingCustomStream {
                            Button(L10n.text(tracker.startingCustomStream ? "STARTING HEART RATE…" : "START DEVICE HEART RATE")) { tracker.startCustomStream() }
                                .buttonStyle(PulseTrackerButton()).disabled(tracker.startingCustomStream)
                            Text(L10n.text("Experimental WHOOP connection request. Requires a matching device acknowledgement before requesting live heart rate; actual model and firmware compatibility remain unverified."))
                                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                        }
                        Button(L10n.text("DISCONNECT")) { tracker.disconnect() }.buttonStyle(PulseTrackerButton(secondary: true))
                    } else {
                        Button(L10n.text(tracker.isScanning ? "STOP SEARCHING" : "SEARCH FOR DEVICES")) {
                            if tracker.isScanning { tracker.stop() } else { tracker.scan() }
                        }.buttonStyle(PulseTrackerButton()).disabled(tracker.isConnecting)
                        if tracker.isConnecting {
                            Button(L10n.text("CANCEL CONNECTION")) { tracker.disconnect() }.buttonStyle(PulseTrackerButton(secondary: true))
                        }
                        if tracker.isScanning {
                            ProgressView(L10n.text("Searching nearby Bluetooth trackers…")).font(PulseFont.body(12)).tint(PulseColor.load).frame(minHeight: 44)
                        }
                        if !tracker.devices.isEmpty {
                            Text(L10n.text("NEARBY DEVICES")).font(PulseFont.label()).tracking(AppLanguage.isArabic ? 0 : 0.8)
                            ForEach(tracker.devices) { item in
                                Button { tracker.connect(item) } label: {
                                    PulseCard {
                                        HStack(spacing: 10) {
                                            Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(PulseColor.sleep)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name).font(PulseFont.body(15).weight(.semibold))
                                                Text(L10n.text("\(item.rssi) dBm")).font(PulseFont.body(11)).foregroundStyle(PulseColor.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.system(size: 11))
                                        }.frame(minHeight: 44)
                                    }
                                }.buttonStyle(.plain).disabled(tracker.isConnecting).accessibilityLabel(L10n.text("Connect to \(item.name), signal \(item.rssi) dBm"))
                            }
                        } else if !tracker.isScanning {
                            PulseCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.text("Ready when your tracker is")).font(PulseFont.body(17).weight(.semibold))
                                    Text(L10n.text("Keep it nearby and enable heart-rate broadcasting if your device provides it. Bluetooth access is requested when you search.")).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                                }
                            }
                        }
                    }
                    storedHistoryCard
                    automaticTrackingCard
                    PulseCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("WHAT THIS CONNECTION CAN DO")).font(PulseFont.label()).tracking(AppLanguage.isArabic ? 0 : 0.6)
                            Text(L10n.text("Listen for standard Bluetooth heart-rate broadcasts, or try the selected WHOOP service families already implemented. Individual WHOOP 4.0, 5.0 and MG compatibility has not been verified on physical devices.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                            Text(L10n.text("Live heart rate is saved automatically. Stored tracker packets can be downloaded and exported. Optional local estimates are calculations, not WHOOP scores. Official Recovery, Sleep and Strain still require WHOOP account data.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                        }
                    }
                    Text(L10n.text("Only received intervals count. Saved charts retain one actual reading per minute. Bluetooth background delivery depends on iOS; force-quitting the app or losing connection leaves gaps. Stored tracker history is downloaded separately using Download from tracker.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                    Button(L10n.text("OPEN BLUETOOTH PERMISSIONS")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(PulseTrackerButton(secondary: true))
                }.padding(16).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden).background(PulseColor.background)
                .navigationTitle(L10n.text("DEVICE SETTINGS")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.text("Done")) { dismiss() }.frame(minWidth: 44, minHeight: 44) } }
                .toolbarBackground(PulseColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.font(PulseFont.body()).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
            .task { tracker.refreshHistorySummary() }
            .onDisappear { if tracker.isScanning { tracker.stop() } }
    }
    private var storedHistoryCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("STORED TRACKER DATA")).font(PulseFont.label())
                Text(L10n.text(tracker.historyStatus)).font(PulseFont.body(14))
                if let error = tracker.historyPreviewError {
                    Text(L10n.text("The full raw data is saved, but the chart preview could not update.") + " " + error).font(PulseFont.body(12)).foregroundStyle(.orange)
                }
                Text(L10n.text("Archived packets") + ": " + tracker.savedDeviceHistory.packets.formatted()).font(PulseFont.body(14))
                Text(L10n.text("Heart-rate records") + ": " + tracker.savedDeviceHistory.heartRateRecords.formatted()).font(PulseFont.body(14))
                Text(L10n.text("Recorded beat intervals") + ": " + tracker.savedDeviceHistory.rrIntervals.formatted()).font(PulseFont.body(14))
                if let date = tracker.savedDeviceHistory.latestMeasurement {
                    Text(L10n.text("Latest tracker record") + ": " + date.formatted(date: .abbreviated, time: .standard)).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                }
                if tracker.isDownloadingHistory {
                    ProgressView(L10n.text("Downloading tracker records…")).tint(PulseColor.sleep)
                    Button(L10n.text("STOP & DISCONNECT")) { tracker.stopHistoryDownload() }.buttonStyle(PulseTrackerButton(secondary: true))
                } else if tracker.canDownloadHistory {
                    Button(L10n.text("DOWNLOAD FROM TRACKER")) { tracker.downloadDeviceHistory() }.buttonStyle(PulseTrackerButton())
                } else {
                    Text(L10n.text("History needs the full tracker connection, not just a heart-rate broadcast. Connect your tracker and wait for its device check to complete.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                }
                if tracker.savedDeviceHistory.batches > 0 {
                    Button(L10n.text(tracker.isExportingHistory ? "PREPARING ARCHIVE…" : "EXPORT ALL RAW TRACKER DATA")) { tracker.exportDeviceHistory() }
                        .buttonStyle(PulseTrackerButton(secondary: true)).disabled(tracker.isExportingHistory || tracker.isDownloadingHistory)
                    if let url = tracker.historyExportURL {
                        ShareLink(item: url) { Text(L10n.text("SHARE RAW ARCHIVE")).frame(maxWidth: .infinity, minHeight: 44) }
                    }
                }
                Text(L10n.text("The complete packet batch is saved before receipt is confirmed to the band. Charts show one actual heart-rate record per minute. Unknown fields stay raw; they are not converted into invented health measurements.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                Text(L10n.text("Raw tracker history uses this ZIP export and is separate from the app’s JSON backup.")).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
            }
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
                    store.selectedDate = DayCalendar.start(of: Date()); store.tab = .home; dismiss()
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
private struct PulseTrackerButton: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(PulseFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 0.6).frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(PulseColor.text)
            .background(AppGlassSurface(shape: Capsule(), tint: secondary ? .white.opacity(0.03) : PulseColor.sleep.opacity(0.22), solid: PulseColor.card, interactive: true))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
