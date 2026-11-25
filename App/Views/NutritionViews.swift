import SwiftUI
import Charts
import WHOOPCore

private enum NutritionRoute: String, Identifiable {
    case calories, protein, deficit, addFood, activity, weight, settings, calendar
    var id: String { rawValue }
}
struct NutritionRootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @EnvironmentObject private var account: AccountModel
    @State private var route: NutritionRoute?
    @State private var reviewTask: Task<Void, Never>?
    @State private var showingMealCamera = false
    @State private var mealPhoto: Data?
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack {
                NHeading(title: "Nutrition", subtitle: "Your day, fueled.")
                Button { mealPhoto = nil; showingMealCamera = true } label: { Image(systemName: "camera").font(.system(size: 21)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("Scan a meal with the camera")).accessibilityIdentifier("nutritionQuickCamera")
                Button { route = .settings } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Nutrition settings"))
            }
            dateStrip
            if model.isLoading && model.calculation == nil { NSkeleton() }
            else if let result = model.calculation { dashboard(result) }
            else if let error = model.error { NError(message: error); Button(L10n.text("OPEN NUTRITION SETTINGS")) { route = .settings }.buttonStyle(NButton()) }
            else { NSkeleton() }
            NNote()
        }.font(NFont.body()).tint(NColor.cyan).foregroundStyle(.white)
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { gesture in
                guard abs(gesture.translation.width) > abs(gesture.translation.height) * 1.5 else { return }
                move(gesture.translation.width < 0 ? 1 : -1)
            })
            .task(id: store.selectedDate) { await model.refresh(store.nutrition, date: store.selectedDate) }
            .onChange(of: store.nutrition) { _, data in Task { await model.refresh(data, date: store.selectedDate) } }
            .sheet(item: $route) { destination in
                switch destination {
                case .calories: NutritionDeepDive(kind: .calories)
                case .protein: NutritionDeepDive(kind: .protein)
                case .deficit: NutritionDeepDive(kind: .deficit)
                case .addFood: NutritionFoodForm(initialPhoto: mealPhoto)
                case .activity: NutritionExerciseForm()
                case .weight: NutritionWeightView()
                case .settings: NutritionSettingsView()
                case .calendar:
                    NPage(title: "Nutrition date") {
                        DatePicker("Day", selection: $store.selectedDate, in: ...DashboardDatePolicy.today(), displayedComponents: .date)
                            .datePickerStyle(.graphical).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).environment(\.calendar, DayCalendar.utc)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingMealCamera, onDismiss: {
                if mealPhoto != nil { route = .addFood }
            }) { NutritionCameraView { data in mealPhoto = data; showingMealCamera = false } }
            .onDisappear { reviewTask?.cancel() }
    }
    private var dateStrip: some View {
        VStack(spacing: 10) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("Previous nutrition day"))
                Spacer()
                Button { route = .calendar } label: { Text(L10n.text(utcDateText(store.selectedDate, style: .dateTime.weekday(.abbreviated).month(.abbreviated).day()))).font(NFont.label(12)).frame(minHeight: 44) }.accessibilityLabel(L10n.text("Choose nutrition date"))
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(DashboardDatePolicy.isToday(store.selectedDate)).accessibilityLabel(L10n.text("Next nutrition day"))
            }
            HStack(spacing: 4) {
                ForEach(-3...3, id: \.self) { offset in
                    if let date = DayCalendar.utc.date(byAdding: .day, value: offset, to: store.selectedDate) {
                        Button { store.selectedDate = date } label: {
                            VStack(spacing: 4) {
                                Text(L10n.text(utcDateText(date, style: .dateTime.weekday(.narrow)))).font(NFont.label(9))
                                Text(L10n.text(utcDateText(date, style: .dateTime.day()))).font(NFont.label(12))
                            }.frame(maxWidth: .infinity, minHeight: 46)
                                .background(offset == 0 ? NColor.cyan.opacity(0.14) : NColor.card, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(offset == 0 ? NColor.cyan : NColor.muted)
                        }.disabled(DayCalendar.start(of: date) > DashboardDatePolicy.today())
                            .accessibilityLabel(utcDateText(date, style: .dateTime.month().day())).accessibilityAddTraits(offset == 0 ? .isSelected : [])
                    }
                }
            }
        }
    }
    @ViewBuilder private func dashboard(_ result: NutritionCalculation) -> some View {
        HStack(spacing: 17) {
            NDial(title: "Calories left", unit: "kcal", dial: result.caloriesDial, tint: NColor.cyan) { route = .calories }
            NDial(title: "Protein", unit: "grams", dial: result.proteinDial, tint: NColor.green) { route = .protein }
            NDial(title: (result.totals.balance ?? 0) < 0 ? "Net surplus" : "Net deficit", unit: "kcal", dial: result.netDial, tint: NColor.status(result.netDial.status)) { route = .deficit }
        }.padding(.horizontal, 4).padding(.vertical, 6)
        if !result.isComplete && result.hasLog { Text(L10n.text("PARTIAL LOG · BALANCE USES RECORDED FOOD ONLY")).font(NFont.label(8)).tracking(AppLanguage.isArabic ? 0 : 0.6).foregroundStyle(NColor.yellow) }
        if result.goals.calories == nil {
            Button { route = .settings } label: { NCard { Label(L10n.text("Set your goals to see targets and estimated burn."), systemImage: "slider.horizontal.3").font(NFont.body(13)).foregroundStyle(NColor.cyan) } }.buttonStyle(.plain)
        }
        VStack(spacing: 10) {
            HStack(spacing: 10) { NStat(label: "Goal", value: result.goals.calories); NStat(label: "Eaten", value: result.totals.eaten) }
            HStack(spacing: 10) { NStat(label: "Burned · estimated", value: result.totals.estimatedBurned); NStat(label: "Energy-equivalent change", value: result.totals.fatChangeKg, unit: "kg · 7,700 kcal ≈ 1 kg", digits: 3) }
        }
        Text(L10n.text("Burn is estimated maintenance plus logged exercise. Avoid logging exercise already included in your activity level. Energy-equivalent change is not a measurement of body fat."))
            .font(NFont.body(11)).foregroundStyle(NColor.muted)
        NCard {
            VStack(spacing: 17) {
                NMacroBar(title: "Protein", dial: result.proteinDial, color: NColor.green)
                NMacroBar(title: "Carbs", dial: result.carbsDial, color: NColor.cyan)
                NMacroBar(title: "Fat", dial: result.fatDial, color: NColor.yellow)
            }
        }
        HStack(spacing: 10) {
            Button(L10n.text("ADD FOOD")) { mealPhoto = nil; route = .addFood }.buttonStyle(NButton())
            Button(L10n.text("ACTIVITY")) { route = .activity }.buttonStyle(NButton(secondary: true))
        }
        meals(result)
        exercises
        NCard {
            Toggle(isOn: Binding(get: { result.isComplete }, set: { complete in
                change { data in
                    data.completedDays.removeAll { $0 == result.day }
                    if complete { data.completedDays.append(result.day) }
                }
            })) { VStack(alignment: .leading, spacing: 4) { Text(L10n.text("Day is fully logged")).font(NFont.label(13)); Text(L10n.text("Only completed days enter weekly balance totals.")).font(NFont.body(11)).foregroundStyle(NColor.muted) } }
                .tint(NColor.green).disabled(model.isSaving)
        }
        NCard {
            VStack(alignment: .leading, spacing: 12) {
                NHeading(title: "Day in Review", subtitle: "AI summary from your logged totals")
                if model.reviewing { ProgressView(L10n.text("Writing your review…")).font(NFont.body(13)).tint(NColor.cyan).frame(minHeight: 60) }
                else if let review = model.review { Text(L10n.text(review)).font(NFont.body(14)).lineSpacing(3) }
                else { Text(L10n.text("Generate a short review when you are ready. This sends your day totals to your configured AI provider.")).font(NFont.body(13)).foregroundStyle(NColor.muted) }
                Button(L10n.text(model.review == nil ? "GENERATE REVIEW" : "REFRESH REVIEW")) { reviewTask = Task { await model.generateReview(account: account) } }
                    .buttonStyle(NButton(secondary: true)).disabled(model.reviewing || !result.hasLog)
            }
        }
        if let error = model.error { NError(message: error) }
        HStack(spacing: 10) {
            Button(L10n.text("WEIGHT LOG")) { route = .weight }.buttonStyle(NButton(secondary: true))
            Button(L10n.text("SETTINGS")) { route = .settings }.buttonStyle(NButton(secondary: true))
        }
    }
    @ViewBuilder private func meals(_ result: NutritionCalculation) -> some View {
        NHeading(title: "Meals", subtitle: "Every entry stays editable before it is saved.")
        let entries = store.nutrition.foods.filter { $0.day == result.day }
        if entries.isEmpty { NEmpty(title: "Your first meal starts here", detail: "Add food manually, describe a meal, or scan a photo.") }
        ForEach(NutritionMeal.allCases) { meal in
            let rows = entries.filter { $0.meal == meal }
            if !rows.isEmpty {
                NCard {
                    VStack(spacing: 12) {
                        HStack {
                            Text(L10n.text(meal.title)).font(NFont.number(17))
                            Spacer()
                            Text(L10n.text("\(nText(result.meals.first { $0.meal == meal }?.kcal)) kcal")).font(NFont.body(12)).foregroundStyle(NColor.muted)
                        }
                        ForEach(rows) { entry in
                            HStack(spacing: 7) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.food.name).font(NFont.label(13)).lineLimit(2)
                                    Text(L10n.text("\(nText(entry.food.kcal)) kcal · P \(nText(entry.food.protein)) · C \(nText(entry.food.carbs)) · F \(nText(entry.food.fat)) g")).font(NFont.body(10)).foregroundStyle(NColor.muted)
                                }
                                Spacer(minLength: 0)
                                Button { change { $0.favorites.append(NutritionFavorite(food: entry.food)) } } label: { Image(systemName: "star").frame(width: 44, height: 44) }.disabled(model.isSaving || store.nutrition.favorites.contains { $0.food == entry.food }).accessibilityLabel(L10n.text("Favorite \(entry.food.name)"))
                                Button(role: .destructive) { change { $0.foods.removeAll { $0.id == entry.id } } } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.disabled(model.isSaving).accessibilityLabel(L10n.text("Delete \(entry.food.name)"))
                            }
                        }
                    }
                }
            }
        }
    }
    private var exercises: some View {
        VStack(alignment: .leading, spacing: 12) {
            NHeading(title: "Exercise", subtitle: "Logged energy estimates for this day")
            let rows = store.nutrition.exercises.filter { $0.day == NutritionDay.key(store.selectedDate) }
            if rows.isEmpty { NEmpty(title: "No exercise logged", detail: "Add an activity or estimate one from a description.", symbol: "figure.run") }
            else {
                NCard {
                    ForEach(rows) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(NFont.label(13))
                                Text(L10n.text(entry.estimated ? "AI estimate · reviewed" : "Manual entry")).font(NFont.body(10)).foregroundStyle(NColor.muted)
                            }
                            Spacer()
                            Text(L10n.text("\(nText(entry.kcal)) kcal")).font(NFont.label(12))
                            Button(role: .destructive) { change { $0.exercises.removeAll { $0.id == entry.id } } } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.disabled(model.isSaving).accessibilityLabel(L10n.text("Delete exercise \(entry.name)"))
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
    }
    private func change(_ edit: @escaping (inout NutritionData) -> Void) {
        Task { do { try await model.commit(store, edit: edit) } catch { model.error = error.localizedDescription } }
    }
    private func move(_ offset: Int) {
        guard let next = DayCalendar.utc.date(byAdding: .day, value: offset, to: store.selectedDate), DayCalendar.start(of: next) <= DashboardDatePolicy.today() else { return }
        store.selectedDate = next
    }
}

struct NutritionDeepDive: View {
    @EnvironmentObject private var model: NutritionViewModel
    let kind: NutritionChartKind
    @State private var days = 7
    private var title: String { kind == .calories ? "Calories" : kind == .protein ? "Protein" : "Net balance" }
    var body: some View {
        NPage(title: title) {
            if model.isLoading && model.calculation == nil { NSkeleton() }
            else if let c = model.calculation {
                NHeading(title: title + " Deep Dive", subtitle: c.day + " · logged data and estimates")
                Picker(L10n.text("Trend range"), selection: $days) { Text(L10n.text("7 days")).tag(7); Text(L10n.text("30 days")).tag(30) }.pickerStyle(.segmented).frame(minHeight: 44)
                NDayChart(points: Array(c.series.suffix(days)), kind: kind, goal: kind == .calories ? c.goals.calories : kind == .protein ? c.goals.protein : nil)
                if kind == .deficit {
                    HStack(spacing: 10) { NStat(label: "Weekly net deficit", value: c.weeklyBalance); NStat(label: "Energy-equivalent change", value: c.weeklyFatChangeKg, unit: "kg · estimated", digits: 3) }
                    HStack(spacing: 10) { NStat(label: "Logging streak", value: Double(c.loggingStreak), unit: "consecutive days"); NStat(label: "Complete days", value: Double(c.completeDays), unit: "last 30 days") }
                    NCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.text("Contributing factors")).font(NFont.number(17))
                            breakdown("Estimated maintenance", c.goals.maintenance)
                            breakdown("Logged exercise", c.totals.exercise)
                            breakdown("Logged food", c.totals.eaten)
                            breakdown("Estimated burn minus food", c.totals.balance)
                            Text(L10n.text("Weekly totals include only days you marked complete. Missing meals and overlapping exercise estimates can change the result. The 7,700 kcal/kg conversion is an energy model, not measured fat loss.")).font(NFont.body(12)).foregroundStyle(NColor.muted)
                        }
                    }
                } else {
                    NStat(label: "Daily average · \(days) days", value: kind == .calories ? c.averages.first { $0.range == days }?.eaten : c.averages.first { $0.range == days }?.protein, unit: kind == .calories ? "kcal · logged days only" : "grams · logged days only")
                    NCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Text(L10n.text("By meal")).font(NFont.number(18))
                            ForEach(c.meals) { meal in breakdown(meal.meal.title, kind == .protein ? meal.protein : meal.kcal, unit: kind == .protein ? "g" : "kcal") }
                        }
                    }
                    Text(L10n.text("The dashed line is your current goal. Gaps indicate missing logs; the calorie average includes logged days only, not blank calendar days.")).font(NFont.body(12)).foregroundStyle(NColor.muted)
                }
            } else { NEmpty(title: "No nutrition calculation", detail: model.error ?? "Open Nutrition and configure your targets first.", symbol: "chart.xyaxis.line") }
        }
    }
    private func breakdown(_ title: String, _ value: Double?, unit: String = "kcal") -> some View {
        HStack { Text(L10n.text(title)).font(NFont.body(13)).foregroundStyle(NColor.muted); Spacer(); Text("\(nText(value)) \(value == nil ? "" : unit)").font(NFont.label(13)) }.frame(minHeight: 28)
    }
}
