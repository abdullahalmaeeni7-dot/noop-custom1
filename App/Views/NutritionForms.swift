import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import WHOOPCore

private struct FoodDraft: Identifiable { let id = UUID(); var food: NutritionFood }
private enum FoodInputMode: String, CaseIterable, Identifiable { case manual = "Manual", text = "AI text", photo = "AI photo"; var id: String { rawValue } }
struct NutritionFoodForm: View {
    private let initialPhoto: Data?
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @EnvironmentObject private var account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = FoodInputMode.manual
    @State private var meal = NutritionMeal.breakfast
    @State private var drafts = [FoodDraft(food: NutritionFood())]
    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageDataURL: String?
    @State private var imagePreview: UIImage?
    @State private var showingCamera = false
    @State private var showingConnection = false
    @State private var busy = false
    @State private var error: String?
    @State private var favoritesOnly = false
    @State private var task: Task<Void, Never>?
    @State private var loadedInitialPhoto = false
    init(initialPhoto: Data? = nil) { self.initialPhoto = initialPhoto }
    var body: some View {
        NPage(title: "Add food") {
            Picker(L10n.text("Meal type"), selection: $meal) { ForEach(NutritionMeal.allCases) { Text(L10n.text($0.title)).tag($0) } }.pickerStyle(.segmented).frame(minHeight: 44).disabled(busy)
            Picker(L10n.text("Entry method"), selection: $mode) { ForEach(FoodInputMode.allCases) { Text(L10n.text($0.rawValue)).tag($0) } }.pickerStyle(.segmented).frame(minHeight: 44).disabled(busy)
            if mode == .text { textEntry }
            if mode == .photo { photoEntry }
            if busy { NLoadingCard(); ProgressView(L10n.text("Preparing editable estimates…")).tint(NColor.cyan).frame(maxWidth: .infinity, minHeight: 44); Button(L10n.text("CANCEL")) { task?.cancel() }.buttonStyle(NButton(secondary: true)) }
            if let error {
                NError(message: error)
                if mode != .manual {
                    Button(L10n.text("CONNECTION SETTINGS")) { showingConnection = true }.buttonStyle(NButton(secondary: true))
                    Button(L10n.text("ENTER FOOD MANUALLY")) { mode = .manual; self.error = nil }.buttonStyle(NButton(secondary: true))
                }
            }
            NHeading(title: mode == .manual ? "Your food" : "Review before saving", subtitle: "Check each portion, calorie value and macro. Nothing saves automatically.")
            ForEach($drafts) { $draft in
                NCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField(L10n.text("Food name"), text: $draft.food.name).font(NFont.label(15)).frame(minHeight: 44).accessibilityLabel(L10n.text("Food name"))
                            Button(role: .destructive) { drafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "xmark.circle").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Remove food draft"))
                        }
                        optionalNumber("Portion (grams)", value: $draft.food.grams)
                        NNumberField(title: "Calories (kcal)", value: $draft.food.kcal)
                        NNumberField(title: "Protein (g)", value: $draft.food.protein)
                        NNumberField(title: "Carbs (g)", value: $draft.food.carbs)
                        NNumberField(title: "Fat (g)", value: $draft.food.fat)
                        if let confidence = draft.food.confidence { Text(L10n.text("AI confidence: \(confidence.formatted(.percent.locale(AppLanguage.current.locale).precision(.fractionLength(0)))) · editable estimate")).font(NFont.body(10)).foregroundStyle(NColor.muted).padding(.top, 7) }
                    }
                }.disabled(busy || model.isSaving)
            }
            Button(L10n.text("+ ANOTHER FOOD")) { drafts.append(FoodDraft(food: NutritionFood())) }.buttonStyle(NButton(secondary: true)).disabled(busy || drafts.count >= 30)
            Button(L10n.text(model.isSaving ? "SAVING…" : "SAVE FOOD")) { save() }.buttonStyle(NButton()).disabled(busy || model.isSaving || drafts.isEmpty || drafts.contains { $0.food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            library
        }.onAppear {
            #if targetEnvironment(simulator)
            if let route = GalleryLaunch.route {
                mode = route == "food-ai-text" ? .text : route == "food-ai-photo" ? .photo : .manual
                if route == "food-favorites-bottom" { favoritesOnly = true }
                if route == "food-manual" { drafts = [FoodDraft(food: NutritionFood(name: "Eggs and toast", grams: 160, kcal: 310, protein: 19, carbs: 28, fat: 14))] }
            }
            #endif
        }.onDisappear { task?.cancel() }
            .task {
                if let initialPhoto, !loadedInitialPhoto { loadedInitialPhoto = true; mode = .photo; preparePhoto(initialPhoto) }
            }
            .sheet(isPresented: $showingConnection) { NutritionServiceView().preferredColorScheme(.dark) }
            .fullScreenCover(isPresented: $showingCamera) {
                NutritionCameraView { data in showingCamera = false; preparePhoto(data) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                busy = true; error = nil
                task = Task { @MainActor in
                    defer { busy = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw NutritionError.invalid("The selected photo could not be opened.") }
                        try Task.checkCancellation()
                        try setPhoto(data)
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
            }
    }
    private var textEntry: some View {
        NCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("Describe what you ate")).font(NFont.label(14))
                TextField(L10n.text("2 eggs and a slice of toast"), text: $description, axis: .vertical).lineLimit(3...6).font(NFont.body(15)).accessibilityLabel(L10n.text("Meal description"))
                    .onChange(of: description) { _, value in if value.count > 2_000 { description = String(value.prefix(2_000)) } }
                Text(L10n.text("Only this description is sent to the AI provider configured on your server.")).font(NFont.body(11)).foregroundStyle(NColor.muted)
                connectionHelp
                Button(L10n.text("ESTIMATE FOODS")) { analyze() }.buttonStyle(NButton()).disabled(busy || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private var photoEntry: some View {
        NCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("Scan a meal photo")).font(NFont.label(14))
                HStack(spacing: 12) {
                    Button { error = nil; showingCamera = true } label: { Label(L10n.text("TAKE PHOTO"), systemImage: "camera").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(NButton()).disabled(busy).accessibilityIdentifier("nutritionTakePhoto")
                    PhotosPicker(selection: $photoItem, matching: .images) { Label(L10n.text("LIBRARY"), systemImage: "photo").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(NButton(secondary: true)).disabled(busy)
                }
                if let imagePreview {
                    Image(uiImage: imagePreview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel(L10n.text("Meal photo ready to analyze"))
                }
                if imageDataURL != nil { Label(L10n.text("Photo compressed and ready"), systemImage: "checkmark.circle").font(NFont.body(13)).foregroundStyle(NColor.green) }
                Text(L10n.text("Photos are resized and re-encoded on this iPhone before upload. Tap Analyze to send the meal photo to your configured provider. Photos are not saved in your nutrition log.")).font(NFont.body(11)).foregroundStyle(NColor.muted)
                connectionHelp
                Button(L10n.text("ANALYZE PHOTO")) { analyze() }.buttonStyle(NButton()).disabled(busy || imageDataURL == nil)
            }
        }
    }
    @ViewBuilder private var connectionHelp: some View {
        if let issue = account.nutritionConnectionIssue {
            Text(L10n.text(issue)).font(NFont.body(12)).foregroundStyle(NColor.muted)
            Button(L10n.text("CONNECT NUTRITION SERVICE")) { showingConnection = true }.buttonStyle(NButton(secondary: true))
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            NHeading(title: "Your foods")
            Picker(L10n.text("Food library"), selection: $favoritesOnly) { Text(L10n.text("Recent")).tag(false); Text(L10n.text("Favorites")).tag(true) }.pickerStyle(.segmented).frame(minHeight: 44)
            if favoritesOnly {
                if store.nutrition.favorites.isEmpty { NEmpty(title: "No favorites yet", detail: "Tap the star beside a saved meal to keep it here.", symbol: "star") }
                ForEach(store.nutrition.favorites) { favorite in
                    foodLibraryRow(favorite.food) {
                        task = Task { do { try await model.commit(store) { $0.favorites.removeAll { $0.id == favorite.id } } } catch { self.error = error.localizedDescription } }
                    }
                }
            } else {
                if recent.isEmpty { NEmpty(title: "No recent foods", detail: "Saved foods will appear here for quick reuse.", symbol: "clock") }
                ForEach(Array(recent.enumerated()), id: \.offset) { row in foodLibraryRow(row.element, remove: nil) }
            }
        }
    }
    private var recent: [NutritionFood] {
        var seen = Set<String>()
        return store.nutrition.foods.sorted { $0.createdAt > $1.createdAt }.compactMap { entry in
            seen.insert(entry.food.name.lowercased()).inserted ? entry.food : nil
        }.prefix(12).map { $0 }
    }
    private func foodLibraryRow(_ food: NutritionFood, remove: (() -> Void)?) -> some View {
        NCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(food.name).font(NFont.label(13)); Text(L10n.text("\(nText(food.kcal)) kcal")).font(NFont.body(11)).foregroundStyle(NColor.muted) }
                Spacer()
                Button {
                    if drafts.count == 1 && drafts[0].food.name.isEmpty { drafts = [FoodDraft(food: food)] }
                    else if drafts.count < 30 { drafts.append(FoodDraft(food: food)) }
                } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }.disabled(busy || drafts.count >= 30).accessibilityLabel(L10n.text("Add \(food.name) to review"))
                if let remove { Button(role: .destructive, action: remove) { Image(systemName: "trash").frame(width: 44, height: 44) }.disabled(model.isSaving).accessibilityLabel(L10n.text("Remove favorite \(food.name)")) }
            }
        }
    }
    private func optionalNumber(_ title: String, value: Binding<Double?>) -> some View {
        HStack { Text(L10n.text(title)).font(NFont.body(13)); Spacer(); TextField(L10n.text(title), value: value, format: AppNumberStyle()).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110, minHeight: 44).font(NFont.body(15)).accessibilityLabel(L10n.text(title)) }
    }
    private func setPhoto(_ data: Data) throws {
        let encoded = try NutritionPhoto.compress(data)
        imageDataURL = encoded
        if let body = encoded.split(separator: ",", maxSplits: 1).last, let bytes = Data(base64Encoded: String(body)) { imagePreview = UIImage(data: bytes) }
    }
    private func preparePhoto(_ data: Data) {
        error = nil; busy = true
        task = Task { @MainActor in
            defer { busy = false }
            do { try Task.checkCancellation(); try setPhoto(data) }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func analyze() {
        busy = true; error = nil
        task = Task { @MainActor in
            defer { busy = false }
            struct TextRequest: Encodable { let text: String }
            struct ImageRequest: Encodable { let image: String }
            struct Response: Decodable { let items: [NutritionFood] }
            do {
                let result: Response
                if mode == .photo {
                    guard let imageDataURL else { throw NutritionError.invalid("Choose a meal photo first.") }
                    result = try await account.nutritionPost(path: "analyze-meal", input: ImageRequest(image: imageDataURL))
                } else { result = try await account.nutritionPost(path: "parse-food", input: TextRequest(text: description)) }
                try Task.checkCancellation()
                guard !result.items.isEmpty, result.items.count <= 30 else { throw NutritionError.invalid("No usable food estimates were returned.") }
                drafts = result.items.map { FoodDraft(food: $0) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        error = nil
        let foods = drafts.map(\.food), selectedMeal = meal, day = NutritionDay.key(store.selectedDate)
        task = Task { @MainActor in
            do { try await model.commit(store) { data in data.foods.append(contentsOf: foods.map { NutritionFoodEntry(day: day, meal: selectedMeal, food: $0) }) }; dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct NutritionCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var camera = LiveCameraModel()
    @State private var capturing = false
    @State private var error: String?
    let captured: (Data) -> Void
    private var accessDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.ready { ReferenceCameraPreview(session: camera.engine.session).ignoresSafeArea() }
            VStack(spacing: 24) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 48, height: 48) }
                        .accessibilityLabel(L10n.text("Close meal camera"))
                    Spacer(); Text(L10n.text("MEAL CAMERA")).font(NFont.label(13)).tracking(AppLanguage.isArabic ? 0 : 1.4); Spacer(); Color.clear.frame(width: 48, height: 48)
                }.padding(.horizontal, 16)
                Spacer()
                if camera.ready {
                    RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [20, 180]))
                        .frame(maxWidth: 330).frame(height: 280).padding(.horizontal, 30).accessibilityHidden(true)
                    Text(L10n.text("Fit your meal in the frame")).font(NFont.body(16)).padding(12).background(.black.opacity(0.45), in: Capsule())
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: accessDenied ? "camera.badge.exclamationmark" : "camera").font(.system(size: 38, weight: .light))
                        Text(L10n.text(accessDenied ? "Allow camera access in iPhone Settings to photograph a meal." : camera.status))
                            .font(NFont.body(16)).multilineTextAlignment(.center)
                        if accessDenied {
                            Button(L10n.text("OPEN IPHONE SETTINGS")) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(NButton())
                        } else {
                            Button(L10n.text("OPEN CAMERA")) { Task { await camera.open(microphone: false) } }.buttonStyle(NButton())
                        }
                    }.padding(28)
                }
                if let error { Text(L10n.text(error)).font(NFont.body(14)).multilineTextAlignment(.center).padding(14).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16)) }
                Spacer()
                HStack {
                    Color.clear.frame(width: 48, height: 48)
                    Spacer()
                    Button(action: capture) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(.white).frame(width: 64, height: 64)
                            if capturing { ProgressView().tint(.black) }
                        }.frame(width: 90, height: 90)
                    }.disabled(!camera.ready || capturing).accessibilityLabel(L10n.text("Photograph meal")).accessibilityIdentifier("nutritionCameraShutter")
                    Spacer()
                    Button { camera.engine.flip() } label: { Image(systemName: "camera.rotate").font(.system(size: 25)).frame(width: 48, height: 48) }
                        .disabled(!camera.ready || capturing).accessibilityLabel(L10n.text("Switch meal camera"))
                }.padding(.horizontal, 28).padding(.bottom, 18)
                Text(L10n.text("Review the photo before sending it for estimates.")).font(NFont.body(12)).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 12)
            }.foregroundStyle(.white)
        }.preferredColorScheme(.dark).statusBarHidden(true)
            .task { await camera.open(microphone: false) }
            .onChange(of: phase) { _, value in
                if value == .active { Task { await camera.open(microphone: false) } }
                else { camera.close() }
            }
            .onDisappear { camera.close() }
    }
    private func capture() {
        guard camera.ready, !capturing else { return }
        capturing = true; error = nil
        camera.engine.capturePhoto(state: nil) { result in
            Task { @MainActor in
                capturing = false
                do {
                    let url = try result.get()
                    defer { try? FileManager.default.removeItem(at: url) }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 20 * 1024 * 1024 else { throw NutritionError.invalid("The photo is too large. Move closer to the meal and try again.") }
                    captured(data); dismiss()
                } catch { self.error = "The photo could not be captured. Try again, or choose a photo from your library." }
            }
        }
    }
}

struct NutritionExerciseForm: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @EnvironmentObject private var account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 30.0
    @State private var kcal = 0.0
    @State private var description = ""
    @State private var estimated = false
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NPage(title: "Activity") {
            NHeading(title: "Log exercise", subtitle: "Manual values or an editable AI estimate")
            NCard {
                VStack(spacing: 5) {
                    TextField(L10n.text("Activity name"), text: $name).frame(minHeight: 44).accessibilityLabel(L10n.text("Activity name"))
                    NNumberField(title: "Duration (minutes)", value: $minutes)
                    NNumberField(title: "Calories burned (kcal)", value: $kcal)
                }
            }
            NCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("Estimate from a description")).font(NFont.label(14))
                    TextField(L10n.text("30 min jogging"), text: $description, axis: .vertical).lineLimit(2...4).frame(minHeight: 44).accessibilityLabel(L10n.text("Exercise description"))
                    Text(L10n.text("Uses your latest recorded/profile weight: \(nText(model.calculation?.goals.weightKg, digits: 1)) kg. Set weight in Nutrition Settings first. The description and weight are sent only when you tap Estimate.")).font(NFont.body(11)).foregroundStyle(NColor.muted)
                    if busy { NLoadingCard(); ProgressView(L10n.text("Estimating…")).tint(NColor.cyan) }
                    Button(L10n.text("ESTIMATE CALORIES")) { estimate() }.buttonStyle(NButton(secondary: true)).disabled(busy || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if estimated { Text(L10n.text("AI estimate. Review and edit the calorie value before saving.")).font(NFont.body(12)).foregroundStyle(NColor.yellow) }
            if let error { NError(message: error) }
            Button(L10n.text("SAVE EXERCISE")) { save() }.buttonStyle(NButton()).disabled(busy || model.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.onDisappear { task?.cancel() }
    }
    private func estimate() {
        guard let weightKg = model.calculation?.goals.weightKg else { error = "Add your weight in Nutrition Settings before estimating exercise."; return }
        error = nil; busy = true
        task = Task { @MainActor in
            defer { busy = false }
            struct Request: Encodable { let text: String; let weightKg: Double }
            struct Response: Decodable { let kcal: Double }
            do {
                let response: Response = try await account.nutritionPost(path: "estimate-exercise", input: Request(text: description, weightKg: weightKg))
                try Task.checkCancellation(); kcal = response.kcal; estimated = true
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = String(description.prefix(120)) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        let entry = NutritionExercise(day: NutritionDay.key(store.selectedDate), name: name, kcal: kcal, minutes: minutes, estimated: estimated)
        task = Task { @MainActor in
            do { try await model.commit(store) { $0.exercises.append(entry) }; dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
