import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import BodySeekHealth
import ComposableArchitecture
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct NutritionMealAssistantView: View {
    let store: StoreOf<NutritionFeature>
    @Dependency(\.coachAIClient) private var coach
    @Dependency(\.bodySeekStoreClient) private var foodStore
    @FocusState private var editingText: Bool

    @State private var day: DayKey
    @State private var mealType: MealType = .lunch
    @State private var input = ""
    @State private var photo: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var rows: [DraftRow] = []
    @State private var analysis: Task<Void, Never>?
    @State private var loadingPhoto = false
    @State private var errorMessage: String?
    @State private var showCamera = false

    init(store: StoreOf<NutritionFeature>) {
        self.store = store
        // A draft belongs to the day selected when the sheet opened.
        _day = State(initialValue: store.selectedDayKey)
    }

    var body: some View {
        Form {
            Section {
                TextField("例如：早上两个水煮蛋，午饭鸡腿和薯条，下午喝了咖啡", text: $input, axis: .vertical)
                    .lineLimit(4...9)
                    .focused($editingText)
                    .accessibilityLabel("这一天吃喝了什么")
                    .accessibilityIdentifier("nutrition-ai-input")
                if jpeg != nil && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Picker("照片餐次", selection: $mealType) {
                        ForEach(Self.meals, id: \.self) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                }
            } header: {
                Text("记录 \(day.isoString)")
            } footer: {
                let config = coach.loadConfig()
                let host = URL(string: config.endpointURL)?.host ?? "你配置的服务"
                Text("可一次写下全天餐食。分析会把本次文字或照片发送给 \(host) 的 \(config.modelName)。")
            }
            .disabled(analysis != nil || store.isSaving)

            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("选择照片", systemImage: "photo")
                }
                #if os(iOS)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照", systemImage: "camera") { showCamera = true }
                }
                #endif
                if loadingPhoto {
                    ProgressView("正在读取照片…")
                } else if jpeg != nil {
                    Button("移除已选照片", systemImage: "xmark.circle") {
                        jpeg = nil
                        photo = nil
                        rows = []
                    }
                }
                if !rows.isEmpty {
                    Button("重新分析", systemImage: "sparkles") { analyze() }
                    if analysis != nil { ProgressView("正在识别餐食…") }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(BevelTheme.dangerColor)
                    }
                }
            }
            .disabled(analysis != nil || store.isSaving)

            if !rows.isEmpty {
                Section("饮食草稿") {
                    draftSubtotal(rows.map { $0.entry(day: day) })
                }
            }

            ForEach(Self.meals, id: \.self) { meal in
                let mealRows = rows.filter { $0.meal == meal }
                if !mealRows.isEmpty {
                    Section {
                        ForEach(mealRows) { item in
                            if let row = $rows.first(where: { $0.wrappedValue.id == item.id }) {
                                draftRow(row)
                            }
                        }
                    } header: {
                        Text(meal.title)
                            .accessibilityIdentifier("nutrition-ai-meal-\(meal.rawValue)")
                    } footer: {
                        draftSubtotal(mealRows.map { $0.entry(day: day) })
                    }
                }
            }

            if !rows.isEmpty {
                Section {
                    if let error = store.lastError {
                        Text(error).foregroundStyle(BevelTheme.dangerColor)
                    }
                    Button("确认并保存") {
                        let entries = rows.map { $0.entry(day: day) }
                        store.send(.mealDraftConfirmed(entries, fromPhoto: jpeg != nil))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(analysis != nil || store.isSaving || rows.contains(where: \.hasInvalidValues))
                    .accessibilityIdentifier("nutrition-ai-confirm")
                } footer: {
                    Text("可直接保存 AI 粗估，也可修改份量或手动补充营养。缺乏估算依据的值会留空。")
                }
            }
        }
        .navigationTitle("AI 记饮食")
        .bodyseekNavigationBarInline()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if rows.isEmpty {
                analysisBar
            }
        }
        .task(id: photo) {
            guard let photo else { return }
            loadingPhoto = true
            rows = []
            jpeg = nil
            defer { loadingPhoto = false }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let prepared = Self.prepareJPEG(data) else { throw MealDraftAnalysisError.imageTooLarge }
                try Task.checkCancellation()
                jpeg = prepared
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "读取照片失败，可以重新选择或改用文字。"
            }
        }
        .onChange(of: input) { _, _ in
            rows = []
        }
        .onChange(of: mealType) { _, meal in
            for index in rows.indices { rows[index].meal = meal }
        }
        .onDisappear { analysis?.cancel() }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            MealCamera { captured in
                showCamera = false
                if let captured {
                    photo = nil
                    rows = []
                    jpeg = Self.prepareJPEG(captured)
                    errorMessage = jpeg == nil ? "照片无法处理，请重新拍摄。" : nil
                }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private static let meals = MealType.allCases.filter { $0 != .water }

    private var analysisBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.dangerColor)
            }
            Button {
                analyze()
            } label: {
                Group {
                    if analysis != nil {
                        ProgressView("正在识别餐食…")
                    } else {
                        Label("分析饮食", systemImage: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(analysis != nil || loadingPhoto || store.isSaving
                || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && jpeg == nil))
            .accessibilityIdentifier("nutrition-ai-analyze")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func draftSubtotal(_ entries: [MealEntry]) -> some View {
        var log = DailyNutritionLog(dayKey: day, entries: entries)
        log.recalculateTotals()
        return VStack(alignment: .leading, spacing: 5) {
            Text("营养小计").font(.subheadline.weight(.semibold))
            if let kcal = log.dietKcal {
                if let range = MealEnergySummary(entries: entries).displayRange {
                    Text("粗估 \(range) kcal").font(.title3.monospacedDigit())
                } else {
                    Text("约 \(kcal.formatted(.number.precision(.fractionLength(0)))) kcal")
                        .font(.title3.monospacedDigit())
                }
                let macros = [
                    log.dietProteinG.map { "蛋白质 \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
                    log.dietCarbsG.map { "碳水 \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
                    log.dietFatG.map { "脂肪 \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
                ].compactMap { $0 }
                if !macros.isEmpty {
                    Text(macros.joined(separator: " · ")).font(.subheadline)
                }
            } else {
                Text("暂无可计算的营养值").foregroundStyle(.secondary)
            }
            let missing = entries.filter { $0.kcal == nil || $0.proteinG == nil || $0.carbsG == nil || $0.fatG == nil }.count
            if missing > 0 {
                Text("\(missing) 项营养数据待补").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func draftRow(_ row: Binding<DraftRow>) -> some View {
        let item = row.wrappedValue
        let entry = item.entry(day: day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name).font(.headline)
                Spacer()
                Button("移除", systemImage: "minus.circle") {
                    rows.removeAll { $0.id == item.id }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            if let reported = item.reportedPortion {
                Text(reported)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Picker("餐次", selection: row.meal) {
                ForEach(Self.meals, id: \.self) { meal in
                    Text(meal.title).tag(meal)
                }
            }
            if !item.matches.isEmpty {
                Picker("食物库匹配", selection: row.foodID) {
                    Text("暂不匹配").tag(String?.none)
                    ForEach(item.matches) { food in
                        Text(food.name).tag(Optional(food.foodID))
                    }
                }
            }
            HStack {
                TextField(item.isEstimatedPortion ? "估算可食份量" : "可食份量（可留空）", text: row.portion)
                    .accessibilityIdentifier("nutrition-ai-portion")
                Text(item.unit).foregroundStyle(.secondary)
            }
            if let estimate = entry.energyEstimate {
                Text("粗估 \(estimate.displayRange)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                Text(estimate.assumptions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let kcal = entry.kcal {
                Text("约 \(kcal.formatted(.number.precision(.fractionLength(0)))) kcal")
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
            let macros = [
                entry.proteinG.map { "蛋白质 \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
                entry.carbsG.map { "碳水 \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
                entry.fatG.map { "脂肪 \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
            ].compactMap { $0 }
            if !macros.isEmpty {
                Text(macros.joined(separator: " · "))
                    .font(.subheadline)
            }
            let additional = DraftNutrient.additional.filter { entry[keyPath: $0.keyPath] != nil }
            if !additional.isEmpty {
                DisclosureGroup("更多营养（\(additional.count) 项）") {
                    ForEach(additional, id: \.self) { nutrient in
                        if let value = entry[keyPath: nutrient.keyPath] {
                            LabeledContent(nutrient.title, value: (entry.aiEstimatedNutrientIDs?.contains(nutrient.metricID) == true ? "约 " : "")
                                + value.formatted(.number.precision(.significantDigits(1...3))))
                        }
                    }
                }
            }
            DisclosureGroup("手动补充营养") {
                ForEach(DraftNutrient.basic, id: \.self) { nutrient in
                    nutrientField(nutrient, row: row)
                }
                DisclosureGroup("更多指标") {
                    ForEach(DraftNutrient.additional, id: \.self) { nutrient in
                        nutrientField(nutrient, row: row)
                    }
                }
            }
            if !item.overrides.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text("已填写的值优先保存。").font(.footnote).foregroundStyle(.secondary)
            } else if item.food != nil, item.amount != nil, let note = entry.estimationNote {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            } else if entry.energyEstimate == nil && !macros.isEmpty {
                Text("宏量营养素为 AI 粗估。").font(.footnote).foregroundStyle(.secondary)
            } else if item.food == nil && entry.energyEstimate == nil {
                Text(item.matches.isEmpty ? "食物库暂无匹配" : "选用食物库参考项后可换算营养")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if item.amount == nil && entry.energyEstimate == nil {
                Text("补充可食份量后可换算营养")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: item.foodID) { old, new in
            let previousUnit = item.matches.first { $0.foodID == old }?.basisUnit ?? item.suggestedUnit
            let newUnit = item.matches.first { $0.foodID == new }?.basisUnit ?? item.suggestedUnit
            if previousUnit.lowercased() != newUnit.lowercased() {
                row.portion.wrappedValue = ""
            }
        }
        .disabled(analysis != nil || store.isSaving)
    }

    private func nutrientField(_ nutrient: DraftNutrient, row: Binding<DraftRow>) -> some View {
        LabeledContent(nutrient.title) {
            TextField("沿用估算或食物库", text: Binding(
                get: { row.wrappedValue.overrides[nutrient] ?? "" },
                set: { row.wrappedValue.overrides[nutrient] = $0 }
            ))
            .multilineTextAlignment(.trailing)
        }
    }

    private func analyze() {
        guard analysis == nil else { return }
        editingText = false
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 3_000 else {
            errorMessage = "一次最多分析 3,000 字，可以分段记录。"
            return
        }
        errorMessage = nil
        let image = jpeg
        let selectedPhotoMeal = image != nil && text.isEmpty ? mealType : nil
        analysis = Task {
            defer { analysis = nil }
            do {
                let candidates = try await coach.analyzeMeal(text, image)
                var drafts: [DraftRow] = []
                for candidate in candidates {
                    var results = try await foodStore.searchFoodLibrary(candidate.name)
                    if let lookup = candidate.catalogSearchName, lookup != candidate.name {
                        let known = Set(results.map(\.foodID))
                        results += try await foodStore.searchFoodLibrary(lookup).filter { !known.contains($0.foodID) }
                    }
                    drafts.append(DraftRow(candidate: candidate, matches: Array(results.filter(\.usable).prefix(8)),
                                           meal: selectedPhotoMeal ?? candidate.meal ?? .snack))
                }
                try Task.checkCancellation()
                rows = drafts
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? MealDraftAnalysisError)?.localizedDescription
                    ?? "暂时无法分析这一餐。你仍可以手动记录。"
            }
        }
    }

    private static func prepareJPEG(_ input: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(input as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_200,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

private enum DraftNutrient: Hashable {
    case kcal, protein, carbs, fat
    case additional(String)

    static let basic: [Self] = [.kcal, .protein, .carbs, .fat]
    static let additional = MealEntry.additionalNutrientIDs.map(Self.additional)

    var metricID: String {
        switch self {
        case .kcal: "diet_kcal"
        case .protein: "diet_protein_g"
        case .carbs: "diet_carbs_g"
        case .fat: "diet_fat_g"
        case let .additional(id): id
        }
    }

    var title: String {
        guard let descriptor = NutritionCatalog.allKnownDescriptors[metricID] else { return metricID }
        return "\(descriptor.component ?? descriptor.name)（\(descriptor.rawUnit ?? descriptor.unit)）"
    }

    var keyPath: WritableKeyPath<MealEntry, Double?> {
        switch self {
        case .kcal: return \MealEntry.kcal
        case .protein: return \MealEntry.proteinG
        case .carbs: return \MealEntry.carbsG
        case .fat: return \MealEntry.fatG
        case let .additional(id):
            guard let keyPath = MealEntry.additionalNutrientKeyPath(id) else {
                preconditionFailure("Unmapped meal nutrient: \(id)")
            }
            return keyPath
        }
    }
}

private struct DraftRow: Identifiable {
    let id = UUID()
    let recordedAt = Date()
    let name: String
    let matches: [FoodLibraryItem]
    let suggestedUnit: String
    let reportedPortion: String?
    let isEstimatedPortion: Bool
    let suggestedEnergyEstimate: MealEnergyEstimate?
    let suggestedMacros: MealMacroEstimate?
    let additionalEstimates: [String: Double]
    let originalAmount: Double?
    var meal: MealType
    var foodID: String?
    var portion: String
    var overrides: [DraftNutrient: String] = [:]

    init(candidate: MealDraftCandidate, matches: [FoodLibraryItem], meal: MealType) {
        name = candidate.name
        self.matches = matches
        let unit = candidate.unit?.lowercased()
        suggestedUnit = unit == "ml" ? "mL" : "g"
        reportedPortion = candidate.reportedPortion
        isEstimatedPortion = candidate.isEstimatedPortion == true
        self.meal = meal
        suggestedEnergyEstimate = candidate.energyEstimate
        suggestedMacros = candidate.macroEstimate
        additionalEstimates = candidate.additionalEstimates ?? [:]
        originalAmount = candidate.amount
        let exact = matches.filter { $0.name == candidate.name || $0.aliases.contains(candidate.name) }
        let match = exact.count == 1 ? exact.first : nil
        foodID = match?.foodID
        if let amount = candidate.amount, match == nil || match?.basisUnit.lowercased() == unit {
            portion = String(amount)
        } else {
            portion = ""
        }
    }

    var food: FoodLibraryItem? { matches.first { $0.foodID == foodID } }
    var unit: String { food?.basisUnit ?? suggestedUnit }
    private var trimmedPortion: String { portion.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasInvalidValues: Bool {
        (!trimmedPortion.isEmpty && amount == nil) || overrides.values.contains {
            let input = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !input.isEmpty && Self.nutrientValue(input) == nil
        }
    }

    private static func nutrientValue(_ input: String) -> Double? {
        guard let value = Double(input), value.isFinite, (0...10_000).contains(value) else { return nil }
        return value
    }

    var amount: Double? {
        guard let value = Double(trimmedPortion), value.isFinite, value > 0, value <= 10_000 else { return nil }
        return value
    }

    func entry(day: DayKey) -> MealEntry {
        var entry = estimatedEntry(day: day)
        var supplied: [String] = []
        var estimatedIDs: Set<String> = []
        if let factor = estimateScale {
            for nutrient in DraftNutrient.additional where entry[keyPath: nutrient.keyPath] == nil {
                guard let estimate = additionalEstimates[nutrient.metricID] else { continue }
                entry[keyPath: nutrient.keyPath] = estimate * factor
                estimatedIDs.insert(nutrient.metricID)
            }
        }
        for nutrient in DraftNutrient.basic + DraftNutrient.additional {
            guard let input = overrides[nutrient]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Self.nutrientValue(input) else { continue }
            entry[keyPath: nutrient.keyPath] = value
            estimatedIDs.remove(nutrient.metricID)
            if nutrient == .kcal { entry.energyEstimate = nil }
            supplied.append(nutrient.title)
        }
        if !supplied.isEmpty {
            entry.estimationNote = "手动填写：\(supplied.joined(separator: "、"))。其余已有营养值沿用估算或食物库。"
        }
        if !estimatedIDs.isEmpty {
            entry.aiEstimatedNutrientIDs = estimatedIDs
            let detail = "部分额外营养指标为 AI 粗估。"
            entry.estimationNote = entry.estimationNote.map { $0 + " " + detail } ?? detail
        }
        return entry
    }

    private var estimateScale: Double? {
        guard unit.caseInsensitiveCompare(suggestedUnit) == .orderedSame else { return nil }
        if amount == originalAmount { return 1 }
        guard let amount, let originalAmount, (0.25...4).contains(amount / originalAmount) else { return nil }
        return amount / originalAmount
    }

    private func estimatedEntry(day: DayKey) -> MealEntry {
        let description = amount.map {
            let value = $0.formatted(.number.precision(.fractionLength(0...1)))
            return "\(isEstimatedPortion && amount == originalAmount ? "约 " : "")\(value) \(unit)"
        }
        let portionText = [reportedPortion, description].compactMap { $0 }.joined(separator: " · ")
        let scale = estimateScale
        let estimate = scale.flatMap { factor in
            suggestedEnergyEstimate.map {
                MealEnergyEstimate(lowerKcal: $0.lowerKcal * factor, upperKcal: $0.upperKcal * factor,
                                   assumptions: factor == 1 ? $0.assumptions : $0.assumptions + "。已按修改后的份量等比例换算。")
            }
        }
        let macros = scale == nil ? nil : suggestedMacros
        let factor = scale ?? 1
        if let food, let amount {
            var entry = food.makeMealEntry(dayKey: day, mealType: meal, portionAmount: amount,
                                           portionDescription: portionText, isEstimated: true, recordedAt: recordedAt, id: id)
            entry.foodName = name
            entry.estimationNote = "可匹配的数据由 \(food.sourceName) 换算。"
            var usedFallback = false
            if entry.kcal == nil, let estimate {
                entry.kcal = estimate.midpointKcal
                entry.energyEstimate = estimate
                usedFallback = true
            }
            let macroValues: [(WritableKeyPath<MealEntry, Double?>, Double?)] = [
                (\.proteinG, macros?.proteinG), (\.carbsG, macros?.carbsG), (\.fatG, macros?.fatG)
            ]
            for (field, value) in macroValues where entry[keyPath: field] == nil {
                guard let value else { continue }
                entry[keyPath: field] = value * factor
                usedFallback = true
            }
            if usedFallback { entry.estimationNote = (entry.estimationNote ?? "") + "食物库缺项由 AI 粗估补充。" }
            return entry
        }
        var entry = MealEntry(
            id: id, dayKey: day, mealType: meal, foodID: food?.foodID, foodName: name,
            portionAmount: amount, portionUnit: unit, portionDescription: portionText.isEmpty ? nil : portionText,
            kcal: estimate?.midpointKcal,
            carbsG: macros?.carbsG.map { $0 * factor },
            proteinG: macros?.proteinG.map { $0 * factor },
            fatG: macros?.fatG.map { $0 * factor },
            isEstimated: true,
            estimationNote: estimate.map { "AI 粗估。\($0.assumptions)" }
                ?? (macros == nil ? "份量或营养资料待补。" : "宏量营养素为 AI 粗估。"),
            recordedAt: recordedAt
        )
        entry.energyEstimate = estimate
        return entry
    }
}

#if os(iOS)
private struct MealCamera: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.85))
        }
    }
}
#endif
