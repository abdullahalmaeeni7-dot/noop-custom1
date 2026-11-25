import SwiftUI
import AVFoundation
import PhotosUI
import Photos
import ImageIO
import WHOOPCore

/// Full-screen camera composition measured from the supplied Live reference.
struct ReferenceLiveView: View {
    let reference: PulseHomeDay?
    @AppStorage(WhoopScoreDisplay.estimatePreferenceKey) private var showLocalEstimates = false
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var device: DeviceModel
    @EnvironmentObject private var recorder: WorkoutRecorder
    @EnvironmentObject private var liveActivity: LiveActivityDriver
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = LiveCameraModel()
    @AppStorage("whoop.live.layout.v1") private var savedLayout = Data()
    @State private var layout = LiveOverlayLayout()
    @State private var editing = false
    @State private var editingPhoto = false
    @State private var photoDragOrigin: CGSize?
    @State private var photoPinchOrigin: Double?
    @State private var selectedWidget = LiveOverlayWidget.recovery
    @State private var canvasSize = CGSize(width: 393, height: 698)
    @State private var recordedDate = DashboardDatePolicy.today()
    @State private var pickingRecordedDate = false
    @State private var activityID: UUID?
    @State private var graphSamples: [HeartRateSample] = []
    @State private var mode = CameraOverlayMode.overview
    @State private var now = Date()
    @State private var drawer = false
    @State private var microphone = false
    @State private var torch = false
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var mediaURL: URL?
    @State private var busy = false
    @State private var message: String?
    @State private var showTracker = false
    @State private var useHomeExample = true
    @State private var task: Task<Void, Never>?
    @State private var clipStarted: Date?
    @State private var activityName = "Running"
    @State private var resting = 55.0
    @State private var maximum = 190.0
    @State private var confirmDiscard = false
    @State private var showCameraOptions = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, max(1, geometry.size.height - 100) * layout.aspect.ratio)
            let height = width / layout.aspect.ratio
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                canvas(width: width, height: height)
                    .onAppear { canvasSize = CGSize(width: width, height: height) }
                    .onChange(of: CGSize(width: width, height: height)) { _, size in canvasSize = size }
                footer(width: geometry.size.width).frame(height: 100)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        }.ignoresSafeArea().statusBarHidden(true).preferredColorScheme(.dark)
            .task {
                recordedDate = store.selectedDate
                if savedLayout.count <= 65_536, let restored = try? JSONDecoder().decode(LiveOverlayLayout.self, from: savedLayout) { layout = restored }
                if photoData == nil { await openCamera() }
            }
            .onReceive(clock) { date in now = date; camera.engine.update(snapshot()) }
            .onChange(of: mode) { _, _ in
                if !LiveOverlayLayout.widgets(for: mode).contains(selectedWidget) { selectedWidget = LiveOverlayLayout.widgets(for: mode)[0] }
                camera.engine.update(snapshot())
            }
            .onChange(of: layout) { _, _ in mediaURL = nil; camera.engine.update(snapshot()) }
            .onChange(of: recordedDate) { _, _ in useHomeExample = false; activityID = nil; mediaURL = nil; camera.engine.update(snapshot()) }
            .onReceive(device.heartRateSamples) { sample in
                graphSamples.append(sample)
                if graphSamples.count > 120 { graphSamples.removeFirst(graphSamples.count - 120) }
            }
            .onChange(of: showLocalEstimates) { _, value in if !value { activityID = nil } }
            .onChange(of: photo) { _, item in loadPhoto(item) }
            .onChange(of: camera.movie) { _, url in if let url { mediaURL = url; drawer = true } }
            .onChange(of: camera.recording) { _, recording in clipStarted = recording ? Date() : nil }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { camera.close(); torch = false }
                else if photoData == nil { task = Task { await openCamera() } }
            }
            .onDisappear { persistLayout(); task?.cancel(); camera.close() }
            .sheet(isPresented: $drawer) { controls }
            .alert(L10n.text("Live"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(L10n.text("OK"), role: .cancel) { message = nil }
            } message: { Text(L10n.text(message ?? "")) }
    }

    private func canvas(width: CGFloat, height: CGFloat) -> some View {
        let overlay = snapshot()
        return ZStack {
            if let photoImage {
                Image(uiImage: photoImage).resizable().scaledToFill().frame(width: width, height: height)
                    .scaleEffect(layout.boundedPhotoScale).offset(x: layout.photoOffsetX * width, y: layout.photoOffsetY * height)
                    .gesture(photoGesture(width: width, height: height), including: editing && editingPhoto ? .all : .none)
            } else if camera.ready {
                ReferenceCameraPreview(session: camera.engine.session).frame(width: width, height: height)
            } else {
                Color(white: 0.08)
            }
            CachedLiveOverlay(snapshot: overlay, size: CGSize(width: width, height: height))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(overlayReadout(overlay))
                .accessibilityIdentifier("liveMetrics")
            if editing && !editingPhoto { adjustmentTargets(width: width, height: height) }
            VStack {
                HStack {
                    Button {
                        if editing { persistLayout(); editing = false }
                        else if camera.recording { camera.stop(); drawer = true } else { dismiss() }
                    } label: { Image(systemName: "xmark").font(.system(size: 21, weight: .semibold)).frame(width: 44, height: 44) }
                        .accessibilityLabel(camera.recording ? "Stop video and review" : "Close Live").accessibilityIdentifier("closeLive")
                    if photoData == nil, !camera.ready {
                        Button { showCameraOptions = true } label: {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(.system(size: 19)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(L10n.text(camera.status))
                        .accessibilityHint(L10n.text("OPEN CAMERA"))
                        .confirmationDialog(L10n.text(camera.status), isPresented: $showCameraOptions, titleVisibility: .visible) {
                            Button(L10n.text("OPEN CAMERA")) { task = Task { await openCamera() } }
                            Button(L10n.text("IPHONE CAMERA SETTINGS"), action: openCameraSettings)
                            Button(L10n.text("Cancel"), role: .cancel) {}
                        }
                    }
                    Spacer()
                }.padding(.horizontal, width * 0.018).padding(.top, height * 0.017)
                Spacer()
                if camera.recording {
                    Label(L10n.text("RECORDING"), systemImage: "record.circle.fill").font(PulseFont.label(10))
                        .foregroundStyle(.red).padding(8).background(.black.opacity(0.6), in: Capsule())
                }
                if editing {
                    HStack {
                        Text(L10n.text("Zoom and drag to adjust")).font(PulseFont.body(12))
                        Spacer()
                        Button(L10n.text("SAVE CHANGES")) { persistLayout(); editing = false }
                            .font(PulseFont.label(11)).frame(minWidth: 100, minHeight: 44).accessibilityIdentifier("liveSaveChanges")
                    }.padding(.horizontal, 18).background(.black.opacity(0.8))
                }
                captureControls(width: width).padding(.bottom, height * 0.013)
            }.foregroundStyle(.white)
            if busy { ProgressView(L10n.text("Preparing media…")).padding(20).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12)).tint(.white) }
        }.environment(\.layoutDirection, .leftToRight)
            .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 8))
            .simultaneousGesture(DragGesture(minimumDistance: 50).onEnded { drag in
                guard !editing, abs(drag.translation.width) > abs(drag.translation.height) * 1.5, let index = CameraOverlayMode.allCases.firstIndex(of: mode) else { return }
                let next = min(CameraOverlayMode.allCases.count - 1, max(0, index + (drag.translation.width < 0 ? 1 : -1)))
                select(CameraOverlayMode.allCases[next])
            })
            .onTapGesture(count: 2) { if !camera.recording, !camera.starting, !busy { editing.toggle(); persistLayout() } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("Live camera, \(mode.rawValue). \(snapshot().source)"))
    }

    private func overlayReadout(_ overlay: LiveOverlaySnapshot) -> String {
        guard let metrics = overlay.referenceMetrics else { return "" }
        let widgets = LiveOverlayLayout.widgets(for: mode)
        return metrics.enumerated().compactMap { index, metric -> String? in
            guard widgets.indices.contains(index), layout.isVisible(widgets[index], mode: mode),
                  overlay.isAvailable(metric, at: index, now: now) else { return nil }
            return L10n.text(metric.label).replacingOccurrences(of: "\n", with: " ") + ", " + metric.value
        }.joined(separator: ". ")
    }

    private func captureControls(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if mode != .live { photoControl }
            Button { drawer = true } label: { VStack(spacing: 1) {
                Rectangle().frame(height: 4)
                Rectangle().frame(height: 11)
                Rectangle().frame(height: 4)
            }.foregroundStyle(.white).frame(width: 12).frame(maxWidth: .infinity, minHeight: 48) }
                .accessibilityLabel(L10n.text("Overlay and capture settings")).accessibilityIdentifier("liveControls").disabled(camera.recording || camera.starting || busy)
            Button(action: shutter) {
                ZStack {
                    Circle().fill(mode == .live ? Color.red : .white.opacity(0.4)).frame(width: 69, height: 69)
                    Circle().fill(.white).frame(width: 56, height: 56)
                    if camera.recording { RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 22, height: 22) }
                    else { WhoopMonogram().fill(mode == .live ? .red : Color(white: 0.23)).environment(\.layoutDirection, .leftToRight).frame(width: 25, height: 22) }
                }.frame(width: width / (mode == .live ? 3 : 5), height: 76)
            }.accessibilityLabel(camera.recording ? "Stop video" : mode == .live && photoData == nil ? "Record video" : "Capture photo with stats")
                .disabled(editing || busy || camera.starting || (photoData == nil && !camera.ready))
            if mode != .live { lightControl }
            Button { torch = false; camera.engine.flip() } label: {
                Image(systemName: "camera.rotate").font(.system(size: 29, weight: .light)).frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel(L10n.text("Switch front and back cameras")).disabled(camera.recording || camera.starting || busy || photoData != nil)
        }.buttonStyle(PulsePressStyle())
    }

    private var photoControl: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            Group {
                if let photoImage { Image(uiImage: photoImage).resizable().scaledToFill() }
                else { Image(systemName: "photo").font(.system(size: 24, weight: .light)) }
            }.frame(width: 38, height: 38).clipped().background(.black.opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.5), lineWidth: 3))
                .clipShape(RoundedRectangle(cornerRadius: 4)).frame(maxWidth: .infinity, minHeight: 48)
        }.accessibilityLabel(L10n.text("Choose a saved photo")).disabled(camera.recording || busy)
    }

    private func toggleLight() {
        let requested = !torch
        camera.engine.setTorch(requested) { accepted in
            Task { @MainActor in
                if accepted { torch = requested } else { message = "The light is unavailable for this camera." }
            }
        }
    }

    private var lightControl: some View {
        Button(action: toggleLight) {
            Image(systemName: torch ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 23)).frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityLabel(torch ? "Turn camera light off" : "Turn camera light on")
        .disabled(photoData != nil || busy || !camera.ready)
    }

    private func footer(width: CGFloat) -> some View {
        ZStack {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(CameraOverlayMode.allCases, id: \.rawValue) { item in
                            Button { select(item) } label: {
                                Text(L10n.text(item.rawValue.uppercased())).font(PulseFont.label(10)).tracking(AppLanguage.isArabic ? 0 : 2)
                                    .foregroundStyle(mode == item ? .white : .white.opacity(0.45)).frame(width: 108, height: 44)
                            }.id(item.rawValue).accessibilityIdentifier("liveMode-\(item.rawValue)").disabled(camera.recording || camera.starting || busy)
                        }
                    }.padding(.horizontal, max(0, (width - 108) / 2))
                }.scrollIndicators(.hidden)
                    .onAppear { reader.scrollTo(mode.rawValue, anchor: .center) }
                    .onChange(of: mode) { _, value in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { reader.scrollTo(value.rawValue, anchor: .center) } }
            }.frame(height: 48).position(x: width / 2, y: 30)
            Button { drawer = true } label: { Image(systemName: "arrowtriangle.up.fill").font(.system(size: 12)).frame(width: 60, height: 44) }
                .foregroundStyle(.white).accessibilityLabel(L10n.text("Open Live controls")).position(x: width / 2, y: 68)
        }.background(.black)
    }
    private func select(_ selection: CameraOverlayMode) {
        guard !camera.recording, !camera.starting, !busy else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { mode = selection }
    }

    private var day: DailySnapshot {
        guard useHomeExample, store.isExampleMode, let reference, let date = NutritionDay.date(reference.id) else {
            return store.days.first { DayCalendar.start(of: $0.date) == DayCalendar.start(of: recordedDate) } ?? DailySnapshot.empty(on: recordedDate)
        }
        var day = DailySnapshot.empty(on: date, source: .example)
        day.strain = reference.load; day.recovery = reference.readiness; day.sleepPerformance = reference.sleep
        let components = reference.sleepDuration.split(separator: ":").compactMap { Int($0) }
        day.sleepMinutes = components.count == 2 ? components[0] * 60 + components[1] : 0
        if let energy = reference.statistics.first(where: { $0.id == "energy" }) {
            day.energyKcal = Double(energy.value.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        // Home fixtures remain illustrative and are never written into AppStore.
        return day
    }
    private func snapshot() -> LiveOverlaySnapshot {
        let day = day
        let useRecorder = !recorder.isPaused && (recorder.latestSampleDate ?? .distantPast) > (device.heartRateReceivedAt ?? .distantPast)
        let historical = photoData != nil
        let average = day.heartRates.isEmpty ? nil : day.heartRates.map(\.bpm).reduce(0, +) / Double(day.heartRates.count)
        let hr = historical ? average : (useRecorder ? recorder.latestHeartRate : device.heartRate)
        let received = photoData == nil ? (useRecorder ? recorder.latestSampleDate : device.heartRateReceivedAt) : nil
        let elapsed = clipStarted.map { max(0, Int(Date().timeIntervalSince($0))) } ?? recorder.elapsedSeconds
        let metrics = CameraOverlayData.metrics(mode: mode, day: day, liveHeartRate: hr, sampleDate: received, now: now, elapsedSeconds: elapsed, allowLocalEstimates: showLocalEstimates,
                                                activity: store.activities.first { $0.id == activityID }, historical: historical)
        let exists = store.days.contains { DayCalendar.utc.isDate($0.date, inSameDayAs: day.date) }
        let label = day.source == .example ? "EXAMPLE" : exists ? "RECORDED DAY" : "NO SAVED DATA"
        return LiveOverlaySnapshot(title: "WHOOP Live", source: label,
                                   values: metrics.map(\.value), labels: metrics.map(\.label), heartRateIndex: mode == .live && !historical ? 0 : nil,
                                   sampleDate: received, referenceMode: mode, referenceMetrics: metrics,
                                   layout: layout, graphSamples: historical ? Array(day.heartRates.suffix(120)) : graphSamples,
                                   historicalGraph: historical)
    }
    private func openCameraSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func openCamera() async {
        guard scenePhase == .active, !camera.recording, !camera.starting, !Task.isCancelled else { return }
        await camera.open(microphone: microphone)
        if !Task.isCancelled { camera.engine.update(snapshot()) }
    }
    private func shutter() {
        guard !busy else { return }
        camera.engine.update(snapshot())
        if photoData != nil { renderSelectedPhoto(); return }
        if mode == .live {
            if camera.recording { camera.stop() } else { mediaURL = nil; camera.start() }
        } else {
            busy = true; mediaURL = nil
            camera.engine.capturePhoto(state: snapshot()) { result in Task { @MainActor in
                busy = false
                switch result { case .success(let url): mediaURL = url; drawer = true
                case .failure(let error): message = error.localizedDescription }
            } }
        }
    }
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item, !camera.recording else { return }
        camera.close(); torch = false; busy = true
        task?.cancel()
        task = Task { @MainActor in
            defer { busy = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 30 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else { throw LiveCameraError.photo }
                try Task.checkCancellation(); layout.resetPhoto(); photoData = data; photoImage = UIImage(cgImage: image); mediaURL = nil
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    private func renderSelectedPhoto() {
        guard let photoData else { return }
        busy = true
        let state = snapshot()
        task = Task { @MainActor in
            defer { busy = false }
            let worker = Task.detached(priority: .userInitiated) { () throws -> URL in
                let image = try LiveOverlayRenderer.photo(photoData, snapshot: state)
                guard let data = image.pngData() else { throw LiveCameraError.photo }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-photo-\(UUID().uuidString).png")
                try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
            }
            do {
                let url = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); mediaURL = url; drawer = true
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }

    private var controls: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    layoutControls
                    PulseCard {
                        Text(L10n.text("\(day.source == .example ? "Example" : "Saved") day stats")).font(PulseFont.body(20).weight(.semibold))
                        Button { pickingRecordedDate = true } label: {
                            HStack { Text(utcDateText(recordedDate, style: .dateTime.month(.wide).day().year())); Spacer(); Image(systemName: "calendar") }
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("liveRecordedDay")
                        if !DashboardDatePolicy.isToday(recordedDate) {
                            Button(L10n.text("USE TODAY")) { recordedDate = DashboardDatePolicy.today() }.frame(minHeight: 44)
                        }
                        let activities = store.activities.filter { DayCalendar.start(of: $0.start) == DayCalendar.start(of: recordedDate) && $0.strain != nil && ($0.strainIsEstimate != true || showLocalEstimates) }
                        if !activities.isEmpty {
                            Picker(L10n.text("Strain source"), selection: $activityID) {
                                Text(L10n.text("Day Strain")).tag(Optional<UUID>.none)
                                ForEach(activities) { activity in Text(activity.name).tag(Optional(activity.id)) }
                            }.frame(minHeight: 44)
                        }
                        Text(L10n.text("Overview shows day Strain, Recovery and hours asleep. Live shows received heart rate and day totals; calories are not a workout estimate."))
                            .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        if store.isExampleMode, reference != nil {
                            Toggle(L10n.text("Use Home reference example"), isOn: $useHomeExample).frame(minHeight: 44)
                        }
                        Button(L10n.text("CONNECT TRACKER")) { showTracker = true }.font(PulseFont.label(12)).frame(minHeight: 44)
                    }
                    PulseCard {
                        Text(L10n.text("CAPTURE")).font(PulseFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 1)
                        Text(L10n.text(camera.status)).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        if !camera.ready && photoData == nil {
                            Button(L10n.text("OPEN CAMERA")) { task = Task { await openCamera() } }
                                .frame(minHeight: 44)
                            Button(L10n.text("IPHONE CAMERA SETTINGS"), action: openCameraSettings)
                                .frame(minHeight: 44)
                        }
                        if mode == .live {
                            PhotosPicker(selection: $photo, matching: .images) {
                                Label(L10n.text("Choose a saved photo"), systemImage: "photo")
                                    .frame(minHeight: 44)
                            }
                            Button(action: toggleLight) {
                                Label(L10n.text(torch ? "Turn camera light off" : "Turn camera light on"), systemImage: torch ? "bolt.fill" : "bolt.slash.fill")
                                    .frame(minHeight: 44)
                            }.disabled(photoData != nil || !camera.ready)
                        }
                        Text(L10n.text("Use Live for video, or the other modes for a photo. Video clips stop after five minutes or when the app leaves the foreground."))
                            .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        Toggle(L10n.text("Microphone audio"), isOn: $microphone).frame(minHeight: 44)
                            .onChange(of: microphone) { _, _ in if photoData == nil { task = Task { await openCamera() } } }
                        if photoData != nil {
                            Button(L10n.text("RETURN TO CAMERA")) {
                                photoData = nil; photoImage = nil; photo = nil; drawer = false
                                task = Task { await openCamera() }
                            }.font(PulseFont.label(12)).frame(minHeight: 44)
                        }
                    }.disabled(camera.recording || busy)
                    if let mediaURL {
                        PulseCard {
                            Text(L10n.text("Media ready")).font(PulseFont.body(20).weight(.semibold))
                            ShareLink(item: mediaURL) {
                                Label(L10n.text("SHARE OR SAVE TO FILES"), systemImage: "square.and.arrow.up").frame(minHeight: 48)
                            }.font(PulseFont.label(12))
                            Button(L10n.text("SAVE TO PHOTOS")) { saveToPhotos(mediaURL) }.font(PulseFont.label(12)).frame(minHeight: 48).disabled(busy)
                        }
                    }
                    PulseCard {
                        Button(L10n.text("EXPORT TRANSPARENT STATS PNG")) { exportTransparent() }.font(PulseFont.label(12)).frame(minHeight: 48).disabled(busy || camera.recording)
                        Toggle(L10n.text("Lock Screen Live Activities"), isOn: $liveActivity.enabled).frame(minHeight: 44)
                        Text(L10n.text(liveActivity.status)).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                    }
                    workoutControls
                }.padding(20)
            }.background(PulseColor.background).navigationTitle(L10n.text("Live Controls")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.text("Done")) { drawer = false }.frame(minWidth: 44, minHeight: 44) } }
        }.font(PulseFont.body(15)).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
            .environment(\.calendar, DayCalendar.utc).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .sheet(isPresented: $showTracker) { PulseTrackerView().environmentObject(device) }
            .sheet(isPresented: $pickingRecordedDate) { RecoveryCalendarSheet(selection: $recordedDate, days: store.days) }
            .confirmationDialog(L10n.text("Discard this workout?"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(L10n.text("Discard workout"), role: .destructive) { recorder.discard() }
            }
    }
    private var layoutControls: some View {
        PulseCard {
            Text(L10n.text("ADJUST")).font(PulseFont.label(12)).tracking(AppLanguage.isArabic ? 0 : 1)
            Picker(L10n.text("Frame"), selection: $layout.aspect) {
                Text(L10n.text("Full")).tag(LiveCanvasAspect.full)
                Text(L10n.text("Condensed")).tag(LiveCanvasAspect.condensed)
            }.pickerStyle(.segmented).accessibilityIdentifier("liveAspect")
            Picker(L10n.text("Stat"), selection: $selectedWidget) {
                ForEach(LiveOverlayLayout.widgets(for: mode), id: \.rawValue) { kind in Text(L10n.text(kind.title)).tag(kind) }
            }.frame(minHeight: 44)
            HStack {
                Text(L10n.text("Size")).font(PulseFont.body(15))
                Slider(value: scaleBinding, in: 0.35...1.65, step: 0.05,
                       onEditingChanged: { active in if !active { persistLayout() } }) { Text(L10n.text("Overlay size")) }
                    .accessibilityIdentifier("liveLayoutSize")
                Text("\(Int(scaleBinding.wrappedValue * 100))%").font(PulseFont.number(16)).monospacedDigit().frame(width: 50)
            }
            Button(L10n.text("ZOOM AND DRAG TO ADJUST")) {
                layout.setVisible(true, widget: selectedWidget, mode: mode); editingPhoto = false; editing = true; drawer = false
            }.buttonStyle(WButton()).accessibilityIdentifier("liveAdjust")
            ForEach(LiveOverlayLayout.widgets(for: mode), id: \.rawValue) { kind in
                Toggle(L10n.text(kind.title), isOn: Binding(get: { layout.isVisible(kind, mode: mode) }, set: {
                    layout.setVisible($0, widget: kind, mode: mode); persistLayout()
                })).frame(minHeight: 44).accessibilityIdentifier("liveWidget-\(kind.rawValue)")
            }
            if photoData != nil {
                Button(L10n.text("ADJUST PHOTO")) { editingPhoto = true; editing = true; drawer = false }.frame(minHeight: 44)
                Button(L10n.text("RESET PHOTO")) { layout.resetPhoto(); persistLayout() }.frame(minHeight: 44)
            }
            Button(L10n.text("RESET LAYOUT")) { layout.reset(mode: mode); persistLayout() }.frame(minHeight: 44).accessibilityIdentifier("liveResetLayout")
        }.disabled(camera.recording || camera.starting || busy)
    }
    private var scaleBinding: Binding<Double> {
        Binding(get: { min(1.65, max(0.35, layout.placement(selectedWidget, mode: mode).scale)) }, set: { scale in
            var p = layout.placement(selectedWidget, mode: mode); p.scale = scale
            layout.setPlacement(p, widget: selectedWidget, mode: mode, width: canvasSize.width, height: canvasSize.height)
        })
    }
    private func photoGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture().onChanged { value in
            if photoDragOrigin == nil { photoDragOrigin = CGSize(width: layout.photoOffsetX, height: layout.photoOffsetY) }
            layout.photoOffsetX = (photoDragOrigin?.width ?? 0) + value.translation.width / width
            layout.photoOffsetY = (photoDragOrigin?.height ?? 0) + value.translation.height / height
        }.onEnded { _ in photoDragOrigin = nil; persistLayout() }
            .simultaneously(with: MagnificationGesture().onChanged { value in
                if photoPinchOrigin == nil { photoPinchOrigin = layout.boundedPhotoScale }
                layout.photoScale = min(8, max(0.6, (photoPinchOrigin ?? 1) * value))
            }.onEnded { _ in photoPinchOrigin = nil; persistLayout() })
    }
    private func persistLayout() { if let data = try? JSONEncoder().encode(layout) { savedLayout = data } }
    private func adjustmentTargets(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(LiveOverlayLayout.widgets(for: mode).filter { layout.isVisible($0, mode: mode) }, id: \.rawValue) { kind in
                let rect = layout.frame(kind, mode: mode, width: width, height: height)
                LiveOverlayAdjustmentTarget(kind: kind, mode: mode, layout: $layout, selected: $selectedWidget,
                                            canvasSize: CGSize(width: width, height: height), saved: persistLayout)
                    .frame(width: max(44, rect.width), height: max(44, rect.height)).position(x: rect.midX, y: rect.midY)
            }
        }.environment(\.layoutDirection, .leftToRight)
    }

    private var workoutControls: some View {
        PulseCard {
            Text(L10n.text("WORKOUT")).font(PulseFont.label(11)).tracking(AppLanguage.isArabic ? 0 : 1)
            if recorder.isRecording {
                Text(L10n.text("\(recorder.name) · \(recorder.elapsedSeconds / 60) min · \(recorder.samples) samples")).font(PulseFont.body(16))
                Text(L10n.text(recorder.status)).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                Button(L10n.text(recorder.isPaused ? "RESUME WORKOUT" : "PAUSE WORKOUT")) { recorder.togglePause() }
                    .font(PulseFont.label(12)).frame(minHeight: 44).disabled(camera.recording)
                Button(L10n.text("FINISH AND SAVE WORKOUT")) {
                    do { try recorder.save(to: store) } catch { message = error.localizedDescription }
                }.font(PulseFont.label(12)).frame(minHeight: 44).disabled(camera.recording)
                Button(L10n.text("Discard workout"), role: .destructive) { confirmDiscard = true }.frame(minHeight: 44).disabled(camera.recording)
            } else {
                TextField(L10n.text("Activity name"), text: $activityName).frame(minHeight: 44)
                Stepper("Resting HR: \(Int(resting))", value: $resting, in: 30...110).frame(minHeight: 44)
                Stepper("Maximum HR: \(Int(maximum))", value: $maximum, in: 120...230).frame(minHeight: 44)
                Text(L10n.text("Use your known heart-rate limits. Starting a workout saves received samples when you finish; the local Strain estimate is separate from the saved day Strain shown in the overlay."))
                    .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                Button(L10n.text("START WORKOUT")) {
                    do { try recorder.start(name: activityName, resting: resting, maximum: maximum) }
                    catch { message = error.localizedDescription }
                }.font(PulseFont.label(12)).frame(minHeight: 44).disabled(activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(busy || camera.starting)
    }
    private func exportTransparent() {
        do {
            let image = LiveOverlayRenderer.image(snapshot: snapshot(), size: CGSize(width: 1080, height: 1080 / layout.aspect.ratio), transparent: true)
            guard let data = image.pngData() else { throw LiveCameraError.photo }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-overlay-\(UUID().uuidString).png")
            try data.write(to: url, options: [.atomic, .completeFileProtection]); mediaURL = url
        } catch { message = error.localizedDescription }
    }
    private func saveToPhotos(_ url: URL) {
        busy = true
        task = Task { @MainActor in
            defer { busy = false }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else { message = "Allow Photos access in iPhone Settings, or use Share to save to Files."; return }
            do {
                let video = url.pathExtension.lowercased() == "mp4"
                let image = video ? nil : UIImage(contentsOfFile: url.path)
                guard video || image != nil else { throw LiveCameraError.photo }
                try await PHPhotoLibrary.shared().performChanges {
                    if video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                    else if let image { PHAssetChangeRequest.creationRequestForAsset(from: image) }
                }
                message = "Saved to Photos."
            } catch { message = error.localizedDescription }
        }
    }
}

struct ReferenceCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill; return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}

private struct CachedLiveOverlay: View {
    let snapshot: LiveOverlaySnapshot
    let size: CGSize
    @State private var rendered: UIImage?
    var body: some View {
        Group {
            if let rendered { Image(uiImage: rendered).resizable() }
            else { Color.clear }
        }.frame(width: size.width, height: size.height)
            .onAppear(perform: render)
            .onChange(of: snapshot) { _, _ in render() }
            .onChange(of: size) { _, _ in render() }
    }
    private func render() {
        rendered = LiveOverlayRenderer.image(snapshot: snapshot, size: CGSize(width: size.width * 2, height: size.height * 2), transparent: true)
    }
}


private struct LiveOverlayAdjustmentTarget: View {
    let kind: LiveOverlayWidget
    let mode: CameraOverlayMode
    @Binding var layout: LiveOverlayLayout
    @Binding var selected: LiveOverlayWidget
    let canvasSize: CGSize
    var saved: () -> Void
    @State private var dragOrigin: LiveOverlayPlacement?
    @State private var pinchOrigin: Double?
    var body: some View {
        RoundedRectangle(cornerRadius: 10).stroke(selected == kind ? Color.white : Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .background(.white.opacity(0.001)).contentShape(Rectangle())
            .onTapGesture { selected = kind }
            .gesture(DragGesture().onChanged { value in
                selected = kind
                if dragOrigin == nil { dragOrigin = layout.placement(kind, mode: mode) }
                var p = layout.placement(kind, mode: mode)
                p.offsetX = (dragOrigin?.offsetX ?? 0) + value.translation.width / canvasSize.width
                p.offsetY = (dragOrigin?.offsetY ?? 0) + value.translation.height / canvasSize.height
                update(p)
            }.onEnded { _ in dragOrigin = nil; saved() })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                selected = kind
                if pinchOrigin == nil { pinchOrigin = layout.placement(kind, mode: mode).scale }
                var p = layout.placement(kind, mode: mode); p.scale = (pinchOrigin ?? 1) * value; update(p)
            }.onEnded { _ in pinchOrigin = nil; saved() })
            .accessibilityLabel(L10n.text(kind.title) + ", " + L10n.text("Overlay size"))
            .accessibilityIdentifier("liveOverlay-\(kind.rawValue)")
            .accessibilityAdjustableAction { direction in
                var p = layout.placement(kind, mode: mode)
                p.scale += direction == .increment ? 0.05 : -0.05; update(p); saved()
            }
    }
    private func update(_ p: LiveOverlayPlacement) {
        layout.setPlacement(p, widget: kind, mode: mode, width: canvasSize.width, height: canvasSize.height)
    }
}
