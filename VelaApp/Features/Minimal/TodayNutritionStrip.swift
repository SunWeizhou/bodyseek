import SwiftData
import SwiftUI

struct TodayNutritionStrip: View {
    let nutrition: TodayExperienceNutrition
    let onAddClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("营养")
                        .font(.system(.body, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(nutrition.macroText)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Spacer()
                Text(nutrition.calorieText)
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(VelaTheme.rhythmMist)
                    Capsule()
                        .fill(VelaTheme.rhythmDeep)
                        .frame(width: max(8, proxy.size.width * nutrition.calorieProgress))
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                macroBadge("P", value: nutrition.protein, color: VelaTheme.recoveryColor)
                macroBadge("C", value: nutrition.carbs, color: VelaTheme.sleepColor)
                macroBadge("F", value: nutrition.fat, color: VelaTheme.strainColor)
                Spacer()
                Button {
                    onAddClick()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(VelaTheme.rhythmDeep))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }

    private func macroBadge(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
                .background(Circle().fill(color.opacity(0.12)))
            Text("\(value)g")
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(VelaTheme.rhythmCanvas))
    }
}

struct TodayDailyModuleLinks: View {
    let recoveryMetrics: RecoveryMetricSummary
    let nutrition: TodayExperienceNutrition
    let onAddNutrition: () -> Void
    let onJournal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日记录")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)

            NavigationLink {
                VelaVitalsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(VelaTheme.recoveryColor)
                        .frame(width: 36, height: 36)
                        .background(VelaTheme.recoveryColor.opacity(0.1), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("健康监测")
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text(monitorSummary)
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(VelaTheme.caption2().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .padding(14)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }
            .buttonStyle(.cardPress)
            .accessibilityHint("查看心率变异性、静息心率和其他生理指标")

            TodayNutritionStrip(
                nutrition: nutrition,
                onAddClick: onAddNutrition
            )

            NavigationLink {
                VelaNutritionView()
            } label: {
                HStack {
                    Label("查看营养详情与历史", systemImage: "chart.bar.doc.horizontal")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .padding(.horizontal, 14)
                .frame(minHeight: VelaTheme.minimumHitTarget)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }
            .buttonStyle(.cardPress)

            Button(action: onJournal) {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(VelaTheme.sleepColor)
                        .frame(width: 36, height: 36)
                        .background(VelaTheme.sleepColor.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日志")
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("记录体感、习惯和今天发生的事情")
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    Spacer()
                    Image(systemName: "plus")
                        .font(VelaTheme.caption1().weight(.bold))
                        .foregroundStyle(VelaTheme.sleepColor)
                        .frame(width: VelaTheme.minimumHitTarget, height: VelaTheme.minimumHitTarget)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 10)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }
            .buttonStyle(.cardPress)
        }
    }

    private var monitorSummary: String {
        let hrv = recoveryMetrics.hrvMilliseconds.map { "HRV \(Int($0.rounded())) ms" }
        let rhr = recoveryMetrics.restingHeartRate.map { "静息心率 \(Int($0.rounded())) bpm" }
        let values = [hrv, rhr].compactMap { $0 }
        return values.isEmpty ? "等待 Apple 健康同步生理信号" : values.joined(separator: " · ")
    }
}

struct NutritionOverviewModel: Equatable {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fiber: Int
    let score: Int?
    let qualityScore: Int?
    let coverageLabel: String

    static func build(
        records: [FoodLogRecord],
        calorieTarget: Int,
        proteinTarget: Int,
        fiberTarget: Int
    ) -> NutritionOverviewModel {
        let calories = records.reduce(0) { $0 + $1.totalCalories }
        let protein = records.reduce(0) { $0 + $1.proteinGrams }
        let carbs = records.reduce(0) { $0 + $1.carbsGrams }
        let fat = records.reduce(0) { $0 + $1.fatGrams }
        let fiber = records.reduce(0) { $0 + $1.fiberGrams }
        guard !records.isEmpty else {
            return NutritionOverviewModel(
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                fiber: 0,
                score: nil,
                qualityScore: nil,
                coverageLabel: "未记录"
            )
        }

        let calorieRatio = Double(calories) / Double(max(calorieTarget, 1))
        let calorieScore = max(0, 100 - abs(calorieRatio - 0.9) * 110)
        let proteinScore = min(Double(protein) / Double(max(proteinTarget, 1)), 1) * 100
        let fiberScore = min(Double(fiber) / Double(max(fiberTarget, 1)), 1) * 100
        let qualityScores = records.compactMap { record -> Double? in
            switch record.healthScore.uppercased() {
            case "A": 100
            case "B": 85
            case "C": 70
            case "D": 55
            case "E": 40
            default: nil
            }
        }
        let qualityScore = qualityScores.isEmpty ? nil : qualityScores.reduce(0, +) / Double(qualityScores.count)
        var weightedScore = calorieScore * 0.30 + proteinScore * 0.30 + fiberScore * 0.20
        var availableWeight = 0.80
        if let qualityScore {
            weightedScore += qualityScore * 0.20
            availableWeight += 0.20
        }
        let score = Int((weightedScore / availableWeight).rounded().clamped(to: 0...100))
        return NutritionOverviewModel(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            score: score,
            qualityScore: qualityScore.map { Int($0.rounded()) },
            coverageLabel: records.count >= 3 ? "较完整" : "部分记录"
        )
    }
}

struct NutritionRecordEdit: Equatable {
    var mealName: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fiber: Int
    var healthScore: String

    func normalized() -> NutritionRecordEdit {
        NutritionRecordEdit(
            mealName: mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "一餐" : mealName.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: min(10_000, max(0, calories)),
            protein: min(1_000, max(0, protein)),
            carbs: min(1_000, max(0, carbs)),
            fat: min(1_000, max(0, fat)),
            fiber: min(200, max(0, fiber)),
            healthScore: ["A", "B", "C", "D", "E"].contains(healthScore.uppercased()) ? healthScore.uppercased() : ""
        )
    }
}

struct NutritionRecipeIngredient: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: String
}

struct NutritionRecipe: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var servings: Int
    var ingredients: [NutritionRecipeIngredient]
    var createdAt = Date()
}

struct NutritionMealPlanItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var recipeID: UUID
    var scheduledDate: Date
}

struct NutritionFoodCartItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: String
    var sourceRecipeID: UUID?
    var isChecked = false
}

enum NutritionPlanningStore {
    static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        guard let data = raw.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func recipe(from record: FoodLogRecord) -> NutritionRecipe {
        let ingredients: [NutritionRecipeIngredient]
        if record.foods.isEmpty {
            ingredients = [NutritionRecipeIngredient(name: record.mealName, amount: "1 份")]
        } else {
            ingredients = record.foods.map {
                NutritionRecipeIngredient(name: $0.name, amount: $0.portion)
            }
        }
        return NutritionRecipe(
            name: record.mealName,
            servings: 1,
            ingredients: ingredients
        )
    }

    static func cartItems(from recipe: NutritionRecipe) -> [NutritionFoodCartItem] {
        recipe.ingredients.map {
            NutritionFoodCartItem(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: $0.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceRecipeID: recipe.id
            )
        }.filter { !$0.name.isEmpty }
    }
}

enum NutritionRecipeImportParser {
    static func parse(_ text: String) -> NutritionRecipe? {
        let lines = text.components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }
        guard let name = lines.first, lines.count >= 2 else { return nil }
        let ingredients = lines.dropFirst().compactMap { line -> NutritionRecipeIngredient? in
            let parts: [String]
            if line.contains("|") {
                parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            } else if line.contains("\t") {
                parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            } else {
                parts = [line]
            }
            let ingredientName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ingredientName.isEmpty else { return nil }
            let amount = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return NutritionRecipeIngredient(name: ingredientName, amount: amount)
        }
        guard !ingredients.isEmpty else { return nil }
        return NutritionRecipe(name: name, servings: 1, ingredients: ingredients)
    }

    private static func cleanLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
    }
}

struct VelaNutritionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @ObservedObject private var appState = VelaAppState.shared

    @State private var allRecords: [FoodLogRecord] = []

    @AppStorage("vela_daily_calorie_target") private var calorieTarget = 2000
    @AppStorage("vela_daily_protein_target") private var proteinTarget = 120
    @AppStorage("vela_daily_fiber_target") private var fiberTarget = 25
    @AppStorage("vela_nutrition_favorite_record_ids") private var favoriteRecordIDs = ""
    @AppStorage("vela_nutrition_recipes_json") private var recipesJSON = ""
    @AppStorage("vela_nutrition_meal_plan_json") private var mealPlanJSON = ""
    @AppStorage("vela_nutrition_food_cart_json") private var foodCartJSON = ""

    @State private var showGoals = false
    @State private var showPlanning = false
    @State private var selectedRecord: FoodLogRecord?

    private var dayRecords: [FoodLogRecord] {
        allRecords.filter {
            Calendar.current.isDate($0.createdAt, inSameDayAs: dashboardVM.selectedDate)
        }
    }

    private var overview: NutritionOverviewModel {
        .build(
            records: dayRecords,
            calorieTarget: calorieTarget,
            proteinTarget: proteinTarget,
            fiberTarget: fiberTarget
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                nutritionHero
                nutritionActions
                energyAndQualitySection
                macroSection
                micronutrientSection
                nutritionPlanningSection
                mealHistory
                myFoods
                methodology
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, VelaTheme.bottomContentClearance)
        }
        .background(VelaTheme.rhythmCanvas)
        .task { loadFoodLogs() }
        .onChange(of: appState.localDataRevision) { _, _ in
            loadFoodLogs()
        }
        .onChange(of: dashboardVM.selectedDate) { _, _ in
            loadFoodLogs()
        }
        .safeAreaInset(edge: .top) {
            HStack {
                VelaDetailBackButton(tint: VelaTheme.energyColor)
                Spacer()
                VStack(spacing: 2) {
                    Text("营养")
                        .font(VelaTheme.headline())
                    Text(dayTitle)
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }
                Spacer()
                Button {
                    showGoals = true
                } label: {
                    Image(systemName: "target")
                        .frame(width: VelaTheme.minimumHitTarget, height: VelaTheme.minimumHitTarget)
                }
                .buttonStyle(.cardPress)
                .accessibilityLabel("营养目标")
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .sheet(isPresented: $showGoals) {
            NutritionGoalsSheet(
                calorieTarget: $calorieTarget,
                proteinTarget: $proteinTarget,
                fiberTarget: $fiberTarget
            )
            .presentationDetents([.medium])
            .velaSheetSurface()
        }
        .sheet(item: $selectedRecord) { record in
            NutritionRecordDetailSheet(
                record: record,
                isFavorite: favoriteIDs.contains(record.id),
                onToggleFavorite: { toggleFavorite(record) },
                onSaveRecipe: { saveRecipe(from: record) },
                onSave: { save($0, to: record) },
                onDelete: { delete(record) }
            )
            .presentationDetents([.medium, .large])
            .velaSheetSurface()
        }
        .sheet(isPresented: $showPlanning) {
            NutritionPlanningSheet(
                recipesJSON: $recipesJSON,
                mealPlanJSON: $mealPlanJSON,
                foodCartJSON: $foodCartJSON
            )
            .presentationDetents([.medium, .large])
            .velaSheetSurface()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var nutritionHero: some View {
        HStack(spacing: 18) {
            VelaMetricScoreRing(
                score: overview.score.map(Double.init),
                label: "营养",
                domain: .energy,
                size: 104,
                accent: VelaTheme.energyColor,
                direction: "越高越均衡",
                confidence: overview.coverageLabel,
                dataState: overview.coverageLabel
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(overview.score == nil ? "记录今天的饮食" : nutritionHeadline)
                    .font(VelaTheme.title3().weight(.bold))
                    .foregroundStyle(VelaTheme.fg)
                Text("\(overview.calories) / \(calorieTarget) kcal")
                    .font(VelaTheme.cardValue())
                    .foregroundStyle(VelaTheme.fg)
                ProgressView(value: Double(overview.calories), total: Double(max(calorieTarget, 1)))
                    .tint(VelaTheme.energyColor)
                Text("评分来自热量目标、蛋白质、膳食纤维和已记录食物质量。")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .padding(16)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }

    private var nutritionActions: some View {
        HStack(spacing: 10) {
            nutritionAction("搜索", icon: "magnifyingglass") {
                appState.triggerFoodSearch = true
            }
            nutritionAction("拍照", icon: "camera.fill") {
                appState.routeToFoodScanner(type: "camera")
            }
            nutritionAction("条码", icon: "barcode.viewfinder") {
                appState.routeToFoodScanner(type: "barcode")
            }
            nutritionAction("描述", icon: "text.bubble.fill") {
                appState.routeToCoach(
                    question: "请帮我根据描述记录今天吃的食物，并在保存前让我核对份量和营养。",
                    surface: .nutrition
                )
            }
        }
    }

    private func nutritionAction(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(VelaTheme.caption2().weight(.semibold))
            }
            .foregroundStyle(VelaTheme.energyColor)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
        }
        .buttonStyle(.cardPress)
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("宏量与纤维")
                .font(VelaTheme.headline())
            HStack(spacing: 8) {
                macroCard("蛋白质", value: overview.protein, target: proteinTarget, unit: "g", color: VelaTheme.recoveryColor)
                macroCard("碳水", value: overview.carbs, target: nil, unit: "g", color: VelaTheme.sleepColor)
                macroCard("脂肪", value: overview.fat, target: nil, unit: "g", color: VelaTheme.strainColor)
                macroCard("纤维", value: overview.fiber, target: fiberTarget, unit: "g", color: VelaTheme.energyColor)
            }
        }
    }

    private var energyAndQualitySection: some View {
        let activeEnergy = dashboardVM.dashboard.strain.metrics["active_energy_raw"]
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Label("摄入与活动", systemImage: "arrow.left.arrow.right")
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.fg2)
                if let activeEnergy {
                    Text("\(overview.calories - Int(activeEnergy.rounded())) kcal")
                        .font(VelaTheme.cardValue().monospacedDigit())
                    Text("已记录摄入 − Apple 健康活动消耗")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                } else {
                    Text("—")
                        .font(VelaTheme.cardValue())
                    Text("等待 Apple 健康活动消耗")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))

            VStack(alignment: .leading, spacing: 6) {
                Label("食物质量", systemImage: "leaf.fill")
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Text(overview.qualityScore.map(String.init) ?? "—")
                    .font(VelaTheme.cardValue().monospacedDigit())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(overview.qualityScore == nil ? "记录没有质量分级" : "已保存的 A–E 分级")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
        }
    }

    @ViewBuilder
    private var micronutrientSection: some View {
        let values = micronutrientTotals
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("微量营养素")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("包装标签数据")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            if values.isEmpty {
                VelaStateCard(
                    state: .partial,
                    title: "暂无可靠微量数据",
                    message: "扫描包含钠、钾、钙、铁或维生素标签的条码后显示。"
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(values) { nutrient in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(nutrient.label)
                                .font(VelaTheme.caption2().weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            Text(nutrient.formattedValue)
                                .font(VelaTheme.subheadline().weight(.bold).monospacedDigit())
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Text(nutrient.source)
                                .font(.system(.caption2, design: .default))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
                    }
                }
            }
        }
    }

    private var micronutrientTotals: [NutritionMicronutrientAmount] {
        let grouped = Dictionary(grouping: dayRecords.flatMap(\.micronutrients), by: \.key)
        return grouped.compactMap { key, items in
            guard let first = items.first else { return nil }
            return NutritionMicronutrientAmount(
                key: key,
                label: first.label,
                value: items.reduce(0) { $0 + $1.value },
                unit: first.unit,
                source: "\(items.count) 条已保存标签"
            )
        }.sorted { $0.label < $1.label }
    }

    private var nutritionPlanningSection: some View {
        let recipes = NutritionPlanningStore.decode([NutritionRecipe].self, from: recipesJSON) ?? []
        let plans = NutritionPlanningStore.decode([NutritionMealPlanItem].self, from: mealPlanJSON) ?? []
        let cart = NutritionPlanningStore.decode([NutritionFoodCartItem].self, from: foodCartJSON) ?? []
        let uncheckedCount = cart.filter { !$0.isChecked }.count
        return Button {
            showPlanning = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(VelaTheme.energyColor)
                    .frame(width: 38, height: 38)
                    .background(VelaTheme.energyColor.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("餐单与 Food Cart")
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.fg)
                    Text("\(recipes.count) 个配方 · \(plans.count) 项计划 · \(uncheckedCount) 项待采购")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(VelaTheme.caption2().weight(.bold))
                    .foregroundStyle(VelaTheme.muted)
            }
            .padding(13)
            .background(VelaTheme.cardBg, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                    .stroke(VelaTheme.borderSoft, lineWidth: 0.5)
            )
        }
        .buttonStyle(.cardPress)
        .accessibilityHint("管理已确认配方、餐单日期和购物清单")
    }

    private func macroCard(
        _ title: String,
        value: Int,
        target: Int?,
        unit: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(value)\(unit)")
                .font(VelaTheme.subheadline().weight(.bold).monospacedDigit())
                .foregroundStyle(VelaTheme.fg)
            Text(title)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            if let target {
                Text("/ \(target)")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }

    @ViewBuilder
    private var mealHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日餐食")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
            if dayRecords.isEmpty {
                VelaStateCard(
                    state: .empty,
                    title: "今天还没有餐食记录",
                    message: "搜索、拍照、扫描条码或用自然语言描述一餐。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(dayRecords) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sourceIcon(record.source))
                                    .foregroundStyle(VelaTheme.energyColor)
                                    .frame(width: 32, height: 32)
                                    .background(VelaTheme.energyColor.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.mealName)
                                        .font(VelaTheme.subheadline().weight(.semibold))
                                        .foregroundStyle(VelaTheme.rhythmInk)
                                    Text(record.summaryLine)
                                        .font(VelaTheme.caption2())
                                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(record.totalCalories) kcal")
                                    .font(VelaTheme.caption1().weight(.bold).monospacedDigit())
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                Image(systemName: "chevron.right")
                                    .font(VelaTheme.caption2().weight(.bold))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            }
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.cardPress)
                        if record.id != dayRecords.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
            }
        }
    }

    @ViewBuilder
    private var myFoods: some View {
        let unique = uniqueRecentFoods
        if !unique.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("收藏与常用食物")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(unique, id: \.id) { record in
                            Button {
                                duplicate(record)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.foods.first?.name ?? record.mealName)
                                        .font(VelaTheme.caption1().weight(.semibold))
                                        .foregroundStyle(VelaTheme.rhythmInk)
                                        .lineLimit(1)
                                    Text("\(record.totalCalories) kcal")
                                        .font(VelaTheme.caption2().monospacedDigit())
                                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                    Label("再次记录", systemImage: "plus")
                                        .font(.system(.caption2, design: .default, weight: .semibold))
                                        .foregroundStyle(VelaTheme.energyColor)
                                    if favoriteIDs.contains(record.id) {
                                        Label("已收藏", systemImage: "star.fill")
                                            .font(.system(.caption2, design: .default, weight: .semibold))
                                            .foregroundStyle(VelaTheme.rhythmWarm)
                                    }
                                }
                                .padding(12)
                                .frame(width: 132, alignment: .leading)
                                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
                            }
                            .buttonStyle(.cardPress)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func loadFoodLogs() {
        allRecords = (try? FoodLogRepository(modelContext: modelContext).fetchAllSortedByCreatedAt()) ?? []
    }

    private var methodology: some View {
        EmptyView()
    }

    private var uniqueRecentFoods: [FoodLogRecord] {
        var seen = Set<String>()
        return allRecords.sorted { lhs, rhs in
            let lhsFavorite = favoriteIDs.contains(lhs.id)
            let rhsFavorite = favoriteIDs.contains(rhs.id)
            return lhsFavorite == rhsFavorite ? lhs.createdAt > rhs.createdAt : lhsFavorite && !rhsFavorite
        }.filter { record in
            let key = (record.foods.first?.name ?? record.mealName).lowercased()
            return seen.insert(key).inserted
        }
        .prefix(8)
        .map { $0 }
    }

    private var favoriteIDs: Set<UUID> {
        Set(favoriteRecordIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private var dayTitle: String {
        Calendar.current.isDateInToday(dashboardVM.selectedDate)
            ? "今天"
            : dashboardVM.selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var nutritionHeadline: String {
        switch overview.score ?? 0 {
        case 85...: "营养结构均衡"
        case 70..<85: "整体方向不错"
        case 50..<70: "还有优化空间"
        default: "先补齐今天的记录"
        }
    }

    private func sourceIcon(_ source: String) -> String {
        switch FoodLogSource(rawValue: source) {
        case .photoAnalysis: "camera.fill"
        case .barcodeLookup: "barcode.viewfinder"
        case .coachTool: "sparkles"
        case .manual, .none: "fork.knife"
        }
    }

    private func duplicate(_ source: FoodLogRecord) {
        let record = FoodLogRecord(
            mealName: source.mealName,
            foods: source.foods,
            totalCalories: source.totalCalories,
            proteinGrams: source.proteinGrams,
            carbsGrams: source.carbsGrams,
            fatGrams: source.fatGrams,
            fiberGrams: source.fiberGrams,
            healthScore: source.healthScore,
            suggestions: source.suggestions,
            source: .manual
        )
        modelContext.insert(record)
        try? modelContext.save()
        appState.markLocalDataChanged()
    }

    private func delete(_ record: FoodLogRecord) {
        var ids = favoriteIDs
        ids.remove(record.id)
        favoriteRecordIDs = ids.map(\.uuidString).sorted().joined(separator: ",")
        modelContext.delete(record)
        try? modelContext.save()
        selectedRecord = nil
        appState.markLocalDataChanged()
    }

    private func toggleFavorite(_ record: FoodLogRecord) {
        var ids = favoriteIDs
        if !ids.insert(record.id).inserted { ids.remove(record.id) }
        favoriteRecordIDs = ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func save(_ edit: NutritionRecordEdit, to record: FoodLogRecord) {
        let value = edit.normalized()
        record.mealName = value.mealName
        record.totalCalories = value.calories
        record.proteinGrams = value.protein
        record.carbsGrams = value.carbs
        record.fatGrams = value.fat
        record.fiberGrams = value.fiber
        record.healthScore = value.healthScore
        record.updatedAt = Date()
        try? modelContext.save()
        appState.markLocalDataChanged()
    }

    private func saveRecipe(from record: FoodLogRecord) {
        var recipes = NutritionPlanningStore.decode([NutritionRecipe].self, from: recipesJSON) ?? []
        let newRecipe = NutritionPlanningStore.recipe(from: record)
        if let index = recipes.firstIndex(where: { $0.name.caseInsensitiveCompare(newRecipe.name) == .orderedSame }) {
            recipes[index] = newRecipe
        } else {
            recipes.append(newRecipe)
        }
        recipesJSON = NutritionPlanningStore.encode(recipes)
    }
}

private struct NutritionGoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var calorieTarget: Int
    @Binding var proteinTarget: Int
    @Binding var fiberTarget: Int

    var body: some View {
        NavigationStack {
            Form {
                Stepper("热量目标 \(calorieTarget) kcal", value: $calorieTarget, in: 1000...5000, step: 50)
                Stepper("蛋白质目标 \(proteinTarget) g", value: $proteinTarget, in: 30...300, step: 5)
                Stepper("纤维目标 \(fiberTarget) g", value: $fiberTarget, in: 10...60, step: 1)
                Text("目标由你设置。Vela 不会把这些数值作为医疗处方。")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.muted)
            }
            .navigationTitle("营养目标")
            .velaRhythmFormSurface()
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct NutritionRecordDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: FoodLogRecord
    let onToggleFavorite: () -> Void
    let onSaveRecipe: () -> Void
    let onSave: (NutritionRecordEdit) -> Void
    let onDelete: () -> Void
    @State private var edit: NutritionRecordEdit
    @State private var favorite: Bool

    init(
        record: FoodLogRecord,
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void,
        onSaveRecipe: @escaping () -> Void,
        onSave: @escaping (NutritionRecordEdit) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.record = record
        self.onToggleFavorite = onToggleFavorite
        self.onSaveRecipe = onSaveRecipe
        self.onSave = onSave
        self.onDelete = onDelete
        _favorite = State(initialValue: isFavorite)
        _edit = State(initialValue: NutritionRecordEdit(
            mealName: record.mealName,
            calories: record.totalCalories,
            protein: record.proteinGrams,
            carbs: record.carbsGrams,
            fat: record.fatGrams,
            fiber: record.fiberGrams,
            healthScore: record.healthScore
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("餐食") {
                    TextField("餐食名称", text: $edit.mealName)
                    Button {
                        favorite.toggle()
                        onToggleFavorite()
                    } label: {
                        Label(favorite ? "取消收藏" : "收藏到 My Foods", systemImage: favorite ? "star.slash" : "star")
                    }
                    Button {
                        onSaveRecipe()
                    } label: {
                        Label("保存为配方", systemImage: "book.closed")
                    }
                }
                Section("营养（保存前核对）") {
                    nutritionField("热量 kcal", value: $edit.calories)
                    nutritionField("蛋白质 g", value: $edit.protein)
                    nutritionField("碳水 g", value: $edit.carbs)
                    nutritionField("脂肪 g", value: $edit.fat)
                    nutritionField("膳食纤维 g", value: $edit.fiber)
                    Picker("食物质量", selection: $edit.healthScore) {
                        Text("未分级").tag("")
                        ForEach(["A", "B", "C", "D", "E"], id: \.self) { Text($0).tag($0) }
                    }
                }
                if !record.foods.isEmpty {
                    Section("食物") {
                        ForEach(record.foods, id: \.name) { food in
                            LabeledContent(food.name, value: "\(food.portion) · \(food.calories) kcal")
                        }
                    }
                }
                if !record.suggestions.isEmpty {
                    Section("核对与建议") {
                        ForEach(record.suggestions, id: \.self, content: Text.init)
                    }
                }
                Section {
                    Button("删除本条记录", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle(record.mealName)
            .velaRhythmFormSurface()
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(edit)
                        dismiss()
                    }
                }
            }
        }
    }

    private func nutritionField(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}

private struct NutritionPlanningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var recipesJSON: String
    @Binding var mealPlanJSON: String
    @Binding var foodCartJSON: String

    @State private var recipes: [NutritionRecipe]
    @State private var mealPlan: [NutritionMealPlanItem]
    @State private var cart: [NutritionFoodCartItem]
    @State private var manualItemName = ""
    @State private var manualItemAmount = ""
    @State private var showRecipeImport = false

    init(
        recipesJSON: Binding<String>,
        mealPlanJSON: Binding<String>,
        foodCartJSON: Binding<String>
    ) {
        _recipesJSON = recipesJSON
        _mealPlanJSON = mealPlanJSON
        _foodCartJSON = foodCartJSON
        _recipes = State(initialValue: NutritionPlanningStore.decode([NutritionRecipe].self, from: recipesJSON.wrappedValue) ?? [])
        _mealPlan = State(initialValue: NutritionPlanningStore.decode([NutritionMealPlanItem].self, from: mealPlanJSON.wrappedValue) ?? [])
        _cart = State(initialValue: NutritionPlanningStore.decode([NutritionFoodCartItem].self, from: foodCartJSON.wrappedValue) ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showRecipeImport = true
                    } label: {
                        Label("粘贴并导入配方", systemImage: "doc.on.clipboard")
                    }
                    if recipes.isEmpty {
                        Text("从一条已核对的餐食记录中选择“保存为配方”，然后在这里安排日期或加入 Food Cart。")
                            .foregroundStyle(VelaTheme.muted)
                    } else {
                        ForEach(recipes) { recipe in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(recipe.name).font(.headline)
                                Text(recipe.ingredients.map { "\($0.name) \($0.amount)" }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(VelaTheme.muted)
                                    .lineLimit(2)
                                HStack {
                                    Button("安排明天") { scheduleTomorrow(recipe) }
                                    Button("加入 Food Cart") { addToCart(recipe) }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .onDelete(perform: deleteRecipes)
                    }
                } header: {
                    Text("已确认配方")
                } footer: {
                    Text("配方仅复制你已保存并核对的餐食，不自动补全食材或份量。")
                }

                Section("未来餐单") {
                    if futurePlan.isEmpty {
                        Text("尚未安排餐食").foregroundStyle(VelaTheme.muted)
                    } else {
                        ForEach(futurePlan) { item in
                            LabeledContent(recipeName(item.recipeID), value: item.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                        }
                        .onDelete(perform: deletePlans)
                    }
                }

                Section {
                    HStack {
                        TextField("采购项目", text: $manualItemName)
                        TextField("数量", text: $manualItemAmount)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Button("添加") { addManualCartItem() }
                            .disabled(manualItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach($cart) { $item in
                        HStack {
                            Button {
                                item.isChecked.toggle()
                                persist()
                            } label: {
                                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isChecked ? VelaTheme.success : VelaTheme.muted)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading) {
                                Text(item.name).strikethrough(item.isChecked)
                                if !item.amount.isEmpty {
                                    Text(item.amount).font(.caption).foregroundStyle(VelaTheme.muted)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteCartItems)
                    if cart.contains(where: \.isChecked) {
                        Button("清除已完成项目", role: .destructive) {
                            cart.removeAll(where: \.isChecked)
                            persist()
                        }
                    }
                } header: {
                    Text("Food Cart · 采购前复核")
                } footer: {
                    Text("加入和勾选都只保存在本机；Vela 不会自动下单。")
                }
            }
            .navigationTitle("营养计划")
            .velaRhythmFormSurface()
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        persist()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showRecipeImport) {
                NutritionRecipeImportSheet { recipe in
                    if let index = recipes.firstIndex(where: { $0.name.caseInsensitiveCompare(recipe.name) == .orderedSame }) {
                        recipes[index] = recipe
                    } else {
                        recipes.append(recipe)
                    }
                    persist()
                    showRecipeImport = false
                }
                .presentationDetents([.large])
                .velaSheetSurface()
            }
        }
    }

    private var futurePlan: [NutritionMealPlanItem] {
        mealPlan
            .filter { $0.scheduledDate >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private func recipeName(_ id: UUID) -> String {
        recipes.first(where: { $0.id == id })?.name ?? "已删除的配方"
    }

    private func scheduleTomorrow(_ recipe: NutritionRecipe) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        mealPlan.append(NutritionMealPlanItem(recipeID: recipe.id, scheduledDate: tomorrow))
        persist()
    }

    private func addToCart(_ recipe: NutritionRecipe) {
        cart.append(contentsOf: NutritionPlanningStore.cartItems(from: recipe))
        persist()
    }

    private func addManualCartItem() {
        let name = manualItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        cart.append(NutritionFoodCartItem(
            name: name,
            amount: manualItemAmount.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceRecipeID: nil
        ))
        manualItemName = ""
        manualItemAmount = ""
        persist()
    }

    private func deleteRecipes(at offsets: IndexSet) {
        let deletedIDs = Set(offsets.map { recipes[$0].id })
        recipes.remove(atOffsets: offsets)
        mealPlan.removeAll { deletedIDs.contains($0.recipeID) }
        persist()
    }

    private func deletePlans(at offsets: IndexSet) {
        let ids = Set(offsets.map { futurePlan[$0].id })
        mealPlan.removeAll { ids.contains($0.id) }
        persist()
    }

    private func deleteCartItems(at offsets: IndexSet) {
        cart.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        recipesJSON = NutritionPlanningStore.encode(recipes)
        mealPlanJSON = NutritionPlanningStore.encode(mealPlan)
        foodCartJSON = NutritionPlanningStore.encode(cart)
    }
}

private struct NutritionRecipeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (NutritionRecipe) -> Void
    @State private var pastedText = ""
    @State private var draft: NutritionRecipe?
    @State private var parseMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                if draft == nil {
                    Section("粘贴配方") {
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 180)
                            .accessibilityLabel("待导入配方文本")
                        Text("第一行写配方名；其余每行写“食材 | 数量”。数量可以留空，Vela 不会自动猜测。")
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.muted)
                        Button("解析并复核") {
                            if let parsed = NutritionRecipeImportParser.parse(pastedText) {
                                draft = parsed
                                parseMessage = ""
                            } else {
                                parseMessage = "至少需要配方名和一项食材。"
                            }
                        }
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !parseMessage.isEmpty {
                            Text(parseMessage).foregroundStyle(VelaTheme.warn)
                        }
                    }
                } else if let draftBinding = Binding($draft) {
                    Section("确认配方") {
                        TextField("配方名称", text: draftBinding.name)
                        Stepper("份数 \(draftBinding.wrappedValue.servings)", value: draftBinding.servings, in: 1...20)
                    }
                    Section("逐项核对") {
                        ForEach(draftBinding.ingredients) { $ingredient in
                            VStack(alignment: .leading) {
                                TextField("食材", text: $ingredient.name)
                                TextField("数量（可留空）", text: $ingredient.amount)
                                    .foregroundStyle(VelaTheme.muted)
                            }
                        }
                        .onDelete { draftBinding.wrappedValue.ingredients.remove(atOffsets: $0) }
                        Button("添加食材") {
                            draftBinding.wrappedValue.ingredients.append(NutritionRecipeIngredient(name: "", amount: ""))
                        }
                    }
                    Section {
                        Text("只有点击“确认导入”后才会保存；导入不会创建餐食记录、营养数值或购物订单。")
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.muted)
                    }
                }
            }
            .navigationTitle("导入配方")
            .velaRhythmFormSurface()
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if let draft {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认导入") {
                            let cleaned = NutritionRecipe(
                                id: draft.id,
                                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                servings: draft.servings,
                                ingredients: draft.ingredients.map {
                                    NutritionRecipeIngredient(
                                        id: $0.id,
                                        name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        amount: $0.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                                    )
                                }.filter { !$0.name.isEmpty },
                                createdAt: draft.createdAt
                            )
                            onConfirm(cleaned)
                            dismiss()
                        }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.ingredients.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    }
                }
            }
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
