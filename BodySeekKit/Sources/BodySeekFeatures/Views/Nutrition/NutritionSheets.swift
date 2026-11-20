import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct NutritionMealLoggerSheet: View {
    @Bindable var store: StoreOf<NutritionFeature>

    @State private var mealType: MealType = .lunch
    @State private var selectedFood: FoodLibraryItem?
    @State private var customFoodName: String = ""
    @State private var portionText: String = "150"
    @State private var customKcalText: String = ""
    @State private var customCarbsText: String = ""
    @State private var customProteinText: String = ""
    @State private var customFatText: String = ""
    @State private var customWaterText: String = ""
    @State private var isPartial: Bool = false
    @State private var noteText: String = ""

    public init(store: StoreOf<NutritionFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        NutritionMealAssistantView(store: store)
                    } label: {
                        Label("用 AI 记饮食", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("nutrition-ai-entry")
                }

                Section("餐次与日期（\(store.selectedDayKey.isoString)）") {
                    Picker("餐次", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("从营养库检索（MEXT / 已建档食物）") {
                    TextField(
                        "搜索食物（如：白米饭 / 鸡蛋 / 鸡胸 / 牛奶）",
                        text: Binding(
                            get: { store.foodSearchQuery },
                            set: { store.send(.foodSearchChanged($0)) }
                        )
                    )
                    .accessibilityIdentifier("nutrition-meal-search")

                    ForEach(store.foodLibrary.prefix(12)) { item in
                        Button {
                            selectedFood = item
                            customFoodName = item.name
                            if mealType == .water { mealType = .lunch }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(BevelTheme.ink)
                                    Text("\(item.category) · 每100\(item.basisUnit) \(item.energyKcalPer100.map { "\(Int($0)) kcal" } ?? "--") · 蛋白 \(item.proteinGPer100.map { String(format: "%.1fg", $0) } ?? "--")")
                                        .font(.caption2)
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                                Spacer()
                                if selectedFood?.foodID == item.foodID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(BevelTheme.brand)
                                }
                            }
                        }
                        .accessibilityIdentifier("nutrition-food-pick-\(item.foodID)")
                    }
                }

                Section("份量与营养预览") {
                    if let selectedFood {
                        let amount = max(1, Double(portionText) ?? 100)
                        let scaled = selectedFood.makeMealEntry(
                            dayKey: store.selectedDayKey,
                            mealType: mealType,
                            portionAmount: amount
                        )
                        HStack {
                            Text("摄入克数/毫升")
                            Spacer()
                            TextField("150", text: $portionText)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("nutrition-portion-input")
                            Text(selectedFood.basisUnit)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                        LabeledContent("换算热量", value: scaled.kcal.map { "\(Int($0.rounded())) kcal" } ?? "--")
                        LabeledContent("换算碳水/蛋白/脂肪", value: "\(scaled.carbsG.map { String(format: "%.1f", $0) } ?? "--")g / \(scaled.proteinG.map { String(format: "%.1f", $0) } ?? "--")g / \(scaled.fatG.map { String(format: "%.1f", $0) } ?? "--")g")
                    } else if mealType == .water {
                        TextField("饮水量（mL，例如 350）", text: $customWaterText)
                        TextField("饮品备注（默认 温白开）", text: $customFoodName)
                    } else {
                        TextField("自定义食物名称", text: $customFoodName)
                            .accessibilityIdentifier("nutrition-custom-food-name")
                        TextField("份量（g/mL）", text: $portionText)
                        TextField("热量（kcal，选填）", text: $customKcalText)
                        TextField("碳水（g，选填）", text: $customCarbsText)
                        TextField("蛋白（g，选填）", text: $customProteinText)
                        TextField("脂肪（g，选填）", text: $customFatText)
                    }

                    Toggle("本餐含未拆清估算项（标为 partial）", isOn: $isPartial)
                    TextField("备注（如：少油、含壳核重，选填）", text: $noteText)
                }
            }
            .navigationTitle("记录一餐")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button("取消") {
                        store.send(.mealLoggerPresented(false))
                    }
                }
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("保存") {
                        submitMeal()
                    }
                    .disabled(store.isSaving || (!canSubmit))
                    .accessibilityIdentifier("nutrition-meal-save-button")
                }
            }
        }
    }

    private var canSubmit: Bool {
        if selectedFood != nil { return true }
        if mealType == .water { return (Double(customWaterText) ?? 0) > 0 }
        return !customFoodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitMeal() {
        let amount = max(1, Double(portionText) ?? 100)
        if let food = selectedFood {
            let scaled = food.makeMealEntry(
                dayKey: store.selectedDayKey,
                mealType: mealType,
                portionAmount: amount
            )
            store.send(.logMealSubmitted(
                mealType: mealType,
                foodName: food.name,
                foodID: food.foodID,
                portionAmount: amount,
                portionUnit: food.basisUnit,
                kcal: scaled.kcal,
                carbsG: scaled.carbsG,
                proteinG: scaled.proteinG,
                fatG: scaled.fatG,
                fiberG: scaled.fiberG,
                waterMl: nil,
                vitamins: scaled.vitamins,
                minerals: scaled.minerals,
                isEstimated: false,
                isPartial: isPartial,
                note: noteText.isEmpty ? nil : noteText
            ))
        } else if mealType == .water {
            let ml = Double(customWaterText) ?? 300
            let title = customFoodName.trimmingCharacters(in: .whitespacesAndNewlines)
            store.send(.logMealSubmitted(
                mealType: .water,
                foodName: title.isEmpty ? "饮水" : title,
                foodID: nil,
                portionAmount: ml,
                portionUnit: "mL",
                kcal: nil,
                carbsG: nil,
                proteinG: nil,
                fatG: nil,
                fiberG: nil,
                waterMl: ml,
                vitamins: [:],
                minerals: [:],
                isEstimated: false,
                isPartial: isPartial,
                note: noteText.isEmpty ? nil : noteText
            ))
        } else {
            store.send(.logMealSubmitted(
                mealType: mealType,
                foodName: customFoodName.trimmingCharacters(in: .whitespacesAndNewlines),
                foodID: nil,
                portionAmount: amount,
                portionUnit: "g",
                kcal: Double(customKcalText),
                carbsG: Double(customCarbsText),
                proteinG: Double(customProteinText),
                fatG: Double(customFatText),
                fiberG: nil,
                waterMl: nil,
                vitamins: [:],
                minerals: [:],
                isEstimated: true,
                isPartial: isPartial,
                note: noteText.isEmpty ? nil : noteText
            ))
        }
    }
}

public struct NutritionLibrarySheet: View {
    @Bindable var store: StoreOf<NutritionFeature>

    @State private var showAddForm = false
    @State private var newName = ""
    @State private var newCategory = "谷薯"
    @State private var newBasisUnit = "g"
    @State private var newKcal = ""
    @State private var newCarbs = ""
    @State private var newProtein = ""
    @State private var newFat = ""
    @State private var newSource = "营养成分表 / 包装标签"

    public init(store: StoreOf<NutritionFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                if showAddForm {
                    Section("新增可溯源食物（每 100g / 100mL）") {
                        TextField("食物名称", text: $newName)
                        TextField("分类（谷薯 / 蛋奶 / 肉禽 / 蔬菜）", text: $newCategory)
                        Picker("基准单位", selection: $newBasisUnit) {
                            Text("g").tag("g")
                            Text("mL").tag("mL")
                        }
                        .pickerStyle(.segmented)
                        TextField("热量 kcal / 100", text: $newKcal)
                        TextField("碳水 g / 100", text: $newCarbs)
                        TextField("蛋白 g / 100", text: $newProtein)
                        TextField("脂肪 g / 100", text: $newFat)
                        TextField("依据来源（必写出处）", text: $newSource)
                        Button("保存到营养库") {
                            saveNewFood()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .foregroundStyle(BevelTheme.brand)
                    }
                }

                Section("已建档食物条目（\(store.foodLibrary.count)）") {
                    ForEach(store.foodLibrary) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                Text(item.category)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(BevelTheme.surfaceElevated, in: Capsule())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Text("每100\(item.basisUnit)：\(item.energyKcalPer100.map { "\(Int($0)) kcal" } ?? "--") · 碳 \(item.carbsGPer100.map { String(format: "%.1f", $0) } ?? "--")g · 蛋 \(item.proteinGPer100.map { String(format: "%.1f", $0) } ?? "--")g · 脂 \(item.fatGPer100.map { String(format: "%.1f", $0) } ?? "--")g")
                                .font(.caption2.monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.inkSecondary)
                            Text("出处：\(item.sourceName)")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.deviationInk)
                        }
                    }
                }
            }
            .searchable(
                text: Binding(
                    get: { store.foodSearchQuery },
                    set: { store.send(.foodSearchChanged($0)) }
                ),
                prompt: "搜索食物名或别名"
            )
            .navigationTitle("营养库")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button(showAddForm ? "收起" : "新增") {
                        showAddForm.toggle()
                    }
                }
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("关闭") {
                        store.send(.libraryPresented(false))
                    }
                }
            }
        }
    }

    private func saveNewFood() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "custom_\(UUID().uuidString.prefix(8))"
        let item = FoodLibraryItem(
            foodID: id,
            name: trimmed,
            category: newCategory,
            stateDescription: "用户建档",
            basisAmount: 100,
            basisUnit: newBasisUnit,
            dataKind: "用户补充",
            usable: true,
            energyKcalPer100: Double(newKcal),
            carbsGPer100: Double(newCarbs),
            proteinGPer100: Double(newProtein),
            fatGPer100: Double(newFat),
            sourceName: newSource,
            verifiedOn: store.todayKey
        )
        store.send(.addFoodItemTapped(item))
        showAddForm = false
        newName = ""
        newKcal = ""
        newCarbs = ""
        newProtein = ""
        newFat = ""
    }
}

public struct NutritionProfileTargetSheet: View {
    @Bindable var store: StoreOf<NutritionFeature>

    @State private var sex: String = "男"
    @State private var ageText: String = "28"
    @State private var heightText: String = "175"
    @State private var weightText: String = "68"
    @State private var goal: String = "维持体能与体脂管理"
    @State private var bmrText: String = ""
    @State private var activateDRIs: Bool = true
    @State private var initialized = false

    public init(store: StoreOf<NutritionFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("个人基础档案（驱动个体 DRIs 推荐）") {
                    Picker("参考生理性别", selection: $sex) {
                        Text("男").tag("男")
                        Text("女").tag("女")
                    }
                    .pickerStyle(.segmented)

                    TextField("年龄（岁）", text: $ageText)
                    TextField("身高（cm）", text: $heightText)
                    HStack {
                        TextField("体重（kg）", text: $weightText)
                        if let hkMass = store.snapshot.today.raw.bodyMassKg {
                            Button("引用健康体重 \(String(format: "%.1f", hkMass))kg") {
                                weightText = String(format: "%.1f", hkMass)
                            }
                            .font(.caption)
                            .foregroundStyle(BevelTheme.brand)
                        }
                    }
                    TextField("主要目标（如：减脂 / 增肌 / 维持体能）", text: $goal)

                    HStack {
                        TextField("BMR 参考（kcal/日）", text: $bmrText)
                        Button("公式估算") {
                            if let est = NutritionPlanFactory.estimateBMR(
                                sex: sex,
                                weightKg: Double(weightText),
                                heightCm: Double(heightText),
                                age: Int(ageText)
                            ) {
                                bmrText = "\(Int(est.rounded()))"
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(BevelTheme.brand)
                    }
                }

                Section {
                    Toggle("保存时同步生成并生效 DRIs 2023 目标", isOn: $activateDRIs)
                    if let plan = store.targetPlan {
                        Text("当前版本 \(plan.targetVersion) · 已采用 \(store.periodSummary.validatedPlan.validAdoptedItems.count) 项")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                } footer: {
                    Text("仅经过架构与化学形态校验的已采用目标会参与四态着色；未采纳项保持暂不判断。")
                }
            }
            .navigationTitle("个人档案与目标")
            .bodyseekNavigationBarInline()
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if let p = store.profile {
                    sex = p.referenceSex ?? "男"
                    ageText = p.age.map { "\($0)" } ?? "28"
                    heightText = p.heightCm.map { "\(Int($0.rounded()))" } ?? "175"
                    weightText = p.referenceWeightKg.map { String(format: "%.1f", $0) } ?? "68.0"
                    goal = p.primaryGoal ?? "维持体能与体脂管理"
                    bmrText = p.bmrKcalReference.map { "\(Int($0.rounded()))" } ?? ""
                } else if let hkMass = store.snapshot.today.raw.bodyMassKg {
                    weightText = String(format: "%.1f", hkMass)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button("取消") {
                        store.send(.profileTargetPresented(false))
                    }
                }
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("保存") {
                        let ageVal = Int(ageText)
                        let heightVal = Double(heightText)
                        let weightVal = Double(weightText)
                        let bmrVal = Double(bmrText) ?? NutritionPlanFactory.estimateBMR(
                            sex: sex,
                            weightKg: weightVal,
                            heightCm: heightVal,
                            age: ageVal
                        )
                        let prof = NutritionProfile(
                            id: store.profile?.id ?? UUID(),
                            age: ageVal,
                            referenceSex: sex,
                            heightCm: heightVal,
                            referenceWeightKg: weightVal,
                            primaryGoal: goal,
                            bmrKcalReference: bmrVal,
                            updatedAt: Date()
                        )
                        store.send(.saveProfileTapped(prof, generateAndActivateDRIs: activateDRIs))
                    }
                    .accessibilityIdentifier("nutrition-profile-save-button")
                }
            }
        }
    }
}

public struct NutritionMarkdownSheet: View {
    public let markdown: String
    public let onDismiss: () -> Void

    public init(markdown: String, onDismiss: @escaping () -> Void) {
        self.markdown = markdown
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Text(markdown)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(BevelTheme.canvas.ignoresSafeArea())
            .navigationTitle("Obsidian Markdown 导出")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    ShareLink(item: markdown) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("关闭", action: onDismiss)
                }
            }
        }
    }
}
