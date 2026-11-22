import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct NutritionBoardView: View {
    @Bindable var store: StoreOf<NutritionFeature>

    public init(store: StoreOf<NutritionFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = store.lastError {
                    bannerCard(error, isError: true)
                } else if let status = store.statusMessage {
                    bannerCard(status, isError: false)
                }

                selectedDayMealsCard

                nutritionCoachAdviceCard

                periodHeaderControls

                energyBalanceCard

                macroCircleMatrixCard

                microAccordionCard(
                    groupKey: "vitamins",
                    title: "维生素追踪（14 项）",
                    systemImage: "pills.fill",
                    ids: NutritionCatalog.vitaminOrder.map { "diet_vitamins::\($0)" }
                )

                microAccordionCard(
                    groupKey: "minerals",
                    title: "矿物质追踪（15 项）",
                    systemImage: "atom",
                    ids: NutritionCatalog.mineralOrder.map { "diet_minerals::\($0)" }
                )

                quickActionsBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("营养")
        .bodyseekNavigationBarInline()
        .toolbar {
            ToolbarItem(placement: .bodyseekLeading) {
                Menu {
                    Button {
                        store.send(.mealLoggerPresented(true))
                    } label: {
                        Label("记一餐", systemImage: "plus.circle")
                    }
                    Button {
                        store.send(.libraryPresented(true))
                    } label: {
                        Label("食物营养库", systemImage: "books.vertical")
                    }
                    Button {
                        store.send(.profileTargetPresented(true))
                    } label: {
                        Label("个人档案与营养目标", systemImage: "person.text.rectangle")
                    }
                    Divider()
                    Button {
                        store.send(.exportDailyMarkdownTapped)
                    } label: {
                        Label("导出当天记录", systemImage: "doc.plaintext")
                    }
                    Button {
                        store.send(.exportTargetsMarkdownTapped)
                    } label: {
                        Label("导出营养目标", systemImage: "doc.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("nutrition-more-menu")
            }

        }
        .onAppear {
            store.send(.onAppear)
        }
        .sheet(item: Binding(
            get: { store.mealLogger },
            set: { if $0 == nil { store.send(.mealLoggerPresented(false)) } }
        )) { logger in
            switch logger {
            case .manual:
                NutritionMealLoggerSheet(store: store)
            case let .edit(entry):
                NutritionMealLoggerSheet(store: store, original: entry)
            case .assistant:
                NavigationStack {
                    NutritionMealAssistantView(store: store)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { store.send(.mealLoggerPresented(false)) }
                                    .disabled(store.isSaving)
                            }
                        }
                }
                .interactiveDismissDisabled(store.isSaving)
            }
        }
        .sheet(isPresented: Binding(
            get: { store.showLibrarySheet },
            set: { store.send(.libraryPresented($0)) }
        )) {
            NutritionLibrarySheet(store: store)
        }
        .sheet(isPresented: Binding(
            get: { store.showProfileTargetSheet },
            set: { store.send(.profileTargetPresented($0)) }
        )) {
            NutritionProfileTargetSheet(store: store)
        }
        .sheet(isPresented: Binding(
            get: { store.exportedMarkdown != nil },
            set: { if !$0 { store.send(.markdownSheetDismissed) } }
        )) {
            if let md = store.exportedMarkdown {
                NutritionMarkdownSheet(markdown: md) {
                    store.send(.markdownSheetDismissed)
                }
            }
        }
    }

    private func bannerCard(_ text: String, isError: Bool) -> some View {
        BevelCard(padding: 12) {
            HStack(spacing: 8) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? BevelTheme.dangerColor : BevelTheme.recoveryColor)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.ink)
            }
        }
    }

    private var periodHeaderControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("周期切换", selection: Binding(
                get: { store.periodMode },
                set: { store.send(.periodModeChanged($0)) }
            )) {
                ForEach(NutritionFeature.PeriodMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("nutrition-period-picker")

            HStack {
                Button {
                    store.send(.stepPeriod(-1))
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(store.periodSummary.startDayKey.isoString) – \(store.periodSummary.endDayKey.isoString)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(BevelTheme.ink)

                Spacer()

                Button {
                    store.send(.stepPeriod(1))
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(store.anchorDayKey >= store.todayKey ? BevelTheme.hairline : BevelTheme.inkSecondary)
                }
                .buttonStyle(.plain)
                .disabled(store.anchorDayKey >= store.todayKey)
            }
        }
    }

    private var energyBalanceCard: some View {
        let log = store.selectedDayLog
        let isClosed = log?.dietDayComplete == true
        let intake = log?.dietKcal
        let energy = log.map { MealEnergySummary(entries: $0.entries) }
        let expenditure: Double? = {
            if let bmr = log?.bmrKcalUsed ?? store.profile?.bmrKcalReference, bmr > 0,
               let active = log?.sportKcal ?? store.selectedHealthDay?.raw.activeEnergyKcal, active >= 0 {
                return bmr + active
            }
            return nil
        }()
        let surplus = isClosed ? log?.calorieSurplusKcal.map {
            let kcal = Int($0.rounded())
            return kcal > 0 ? "+\(kcal)" : "\(kcal)"
        } : nil

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("能量平衡")
                        .font(.headline)
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    Button {
                        store.send(.profileTargetPresented(true))
                    } label: {
                        Text("目标")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BevelTheme.brandSoft, in: Capsule())
                            .foregroundStyle(BevelTheme.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nutrition-targets-button")
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    energyMetricTile(
                        label: energy?.displayRange != nil || (energy?.missingEntryCount ?? 0) > 0 ? "已记录摄入" : "饮食摄入",
                        value: energy?.displayRange ?? intake.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "kcal",
                        tint: BevelTheme.brand
                    )
                    energyMetricTile(
                        label: "消耗估算",
                        value: expenditure.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "kcal",
                        tint: BevelTheme.strainColor
                    )
                    energyMetricTile(
                        label: "能量差",
                        value: surplus ?? (isClosed ? "数据不足" : "未完成"),
                        unit: surplus == nil ? "" : "kcal",
                        tint: BevelTheme.nutritionInkColor(for: isClosed ? .met : .unknown)
                    )
                    energyMetricTile(
                        label: "7 天平均缺口",
                        value: store.periodSummary.rollingDeficit7dKcal.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "kcal",
                        tint: BevelTheme.ink
                    )
                }

                if let energy {
                    if energy.displayRange != nil, let known = energy.knownKcalSubtotal {
                        Text("已有数值小计 \(known.formatted(.number.precision(.fractionLength(0)))) kcal")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    if energy.missingEntryCount > 0 {
                        Text("\(energy.missingEntryCount) 项热量待补")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }

                if !isClosed {
                    Button {
                        store.send(.closeSelectedDayTapped(reviewSummary: nil))
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("完成当天记录")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("nutrition-close-day-button")

                    if let partial = log?.dietPartialFields, !partial.isEmpty {
                        Text("还有 \(partial.count) 餐缺少热量或宏量营养素；结账后仍不会判定达标，补齐后才会参与四态评价。")
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-energy-balance-card")
    }

    private func energyMetricTile(label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(tint)
                .lineLimit(1)
            if !unit.isEmpty {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var macroCircleMatrixCard: some View {
        let dayKeys = store.periodDayKeys
        let displayDays = store.periodMode == .week ? dayKeys : Array(dayKeys.suffix(14))
        let macroIDs = Set(NutritionCatalog.macroDescriptors.map(\.id))
        let macroAverages = store.periodSummary.metricAverages.filter { macroIDs.contains($0.metricID) }

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("营养摄入")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                }

                // Four-state honest color legend
                HStack(spacing: 12) {
                    legendDot(color: BevelTheme.nutritionMet, label: "达标")
                    legendDot(color: BevelTheme.nutritionLow, label: "偏低")
                    legendDot(color: BevelTheme.nutritionOver, label: "偏高或超上限")
                    legendDot(color: BevelTheme.nutritionUnknown, label: "记录未完成")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Day headers
                        HStack(spacing: 3) {
                            Text("营养指标")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .frame(width: 68, alignment: .leading)

                            ForEach(displayDays, id: \.self) { dk in
                                let isSelected = dk == store.selectedDayKey
                                Button {
                                    store.send(.daySelected(dk))
                                } label: {
                                    Text(String(format: "%d", dk.day))
                                        .font(.caption2.weight(isSelected ? .bold : .medium).monospacedDigit())
                                        .fontDesign(.rounded)
                                        .frame(width: 20, height: 22)
                                        .background(isSelected ? BevelTheme.brandSoft : Color.clear, in: Capsule())
                                        .foregroundStyle(isSelected ? BevelTheme.brand : BevelTheme.inkSecondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Text("均值")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .frame(width: 80, alignment: .trailing)
                        }

                        ForEach(macroAverages, id: \.metricID) { avg in
                            HStack(spacing: 3) {
                                Text(avg.metricName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(BevelTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .frame(width: 68, alignment: .leading)

                                ForEach(displayDays, id: \.self) { dk in
                                    let log = store.periodSummary.dayLogsByKey[dk]
                                    let eval = NutritionTargetEvaluator.evaluate(
                                        metricID: avg.metricID,
                                        log: log,
                                        validatedPlan: store.periodSummary.validatedPlan
                                    )
                                    Button {
                                        store.send(.daySelected(dk))
                                    } label: {
                                        Circle()
                                            .fill(BevelTheme.nutritionColor(for: eval.status))
                                            .frame(width: 13, height: 13)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        dk == store.selectedDayKey ? BevelTheme.ink : Color.clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 20)
                                    .accessibilityLabel("\(avg.metricName) \(dk.isoString) \(eval.status.label)")
                                }

                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(BevelTheme.nutritionColor(for: avg.status))
                                        .frame(width: 7, height: 7)
                                    Text(avg.averageValue.map { "\(formatMetric($0))\(avg.unit)" } ?? "--")
                                        .font(.caption2.weight(.medium).monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                }
                                .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-macro-matrix")
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
        }
    }

    private var selectedDayMealsCard: some View {
        let log = store.selectedDayLog
        let entries = log?.entries ?? []
        let byMeal = Dictionary(grouping: entries, by: \.mealType)
        let day = store.selectedDayKey
        let dateLabel = day.year == store.todayKey.year
            ? "\(day.month) 月 \(day.day) 日"
            : day.isoString
        let status: String = {
            guard log?.dietDayComplete == true else { return "记录未完成" }
            let partial = log?.dietPartialFields ?? []
            return partial.isEmpty ? "已完成记录" : "已结账 · \(partial.count) 餐有缺项"
        }()

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("饮食记录")
                            .font(.headline)
                            .foregroundStyle(BevelTheme.ink)
                        Text(entries.isEmpty ? dateLabel : "\(dateLabel) · \(status)")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    Spacer()
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { mealRecordingActions }
                    VStack(alignment: .leading, spacing: 8) { mealRecordingActions }
                }

                if entries.isEmpty {
                    Text("这一天还没有饮食记录。")
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.inkSecondary)
                } else {
                    ForEach(MealType.allCases, id: \.self) { meal in
                        if let mealEntries = byMeal[meal] {
                            Divider()
                            mealGroup(meal, entries: mealEntries)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-selected-day-card")
    }

    @ViewBuilder
    private var mealRecordingActions: some View {
        Button {
            store.send(.mealAssistantTapped)
        } label: {
            Label("AI 记饮食（文字 / 拍照）", systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("nutrition-ai-entry")

        Button {
            store.send(.mealLoggerPresented(true))
        } label: {
            Label("手动记录", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("nutrition-log-meal-button")
    }

    private var nutritionCoachAdviceCard: some View {
        let coachBody: String
        let coachEngine: String?
        let isLoading: Bool
        switch store.coachAdviceStatus {
        case .loading:
            coachBody = store.deterministicAdviceSummary
            coachEngine = "正在生成 AI 配餐建议…"
            isLoading = true
        case let .generated(text, engine):
            coachBody = text
            coachEngine = "由 \(engine) 生成 · 含 AI 估算仅供方向参考"
            isLoading = false
        case .idle, .unconfigured:
            coachBody = store.deterministicAdviceSummary
            coachEngine = nil
            isLoading = false
        }

        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Coach 饮食建议", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("AI 解读") {
                            store.send(.generateNutritionAdviceTapped)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .foregroundStyle(BevelTheme.brand)
                    }
                }

                Text(coachBody)
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let coachEngine {
                    Text(coachEngine)
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                Button {
                    store.send(.askCoachTapped("结合我这几天的营养摄入与维生素矿物质估算情况，帮我搭配下一顿，指出优先补充什么。"))
                } label: {
                    HStack {
                        Text("让 Coach 结合缺口配下一顿")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.brand)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nutrition-ask-coach-button")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-coach-advice-card")
    }

    private func mealGroup(_ meal: MealType, entries: [MealEntry]) -> some View {
        let values = entries.compactMap { meal == .water ? $0.waterMl : $0.kcal }
        let unit = meal == .water ? "mL" : "kcal"
        let total = values.count == entries.count ? "\(Int(values.reduce(0, +).rounded())) \(unit)" : nil
        let hasEstimates = entries.contains(where: \.isEstimated)

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in
                    mealEntryRow(entry)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(entries.count) 项")
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.inkSecondary)
                Spacer()
                if let total {
                    Text(hasEstimates ? "约 \(total)" : total)
                        .font(.subheadline.monospacedDigit())
                }
            }
            .foregroundStyle(BevelTheme.ink)
        }
        .accessibilityIdentifier("nutrition-meal-\(meal.rawValue)")
    }

    private func mealEntryRow(_ entry: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.foodName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let estimate = entry.energyEstimate {
                    Text("粗估 \(estimate.displayRange)")
                        .font(.footnote.monospacedDigit())
                } else if let amount = entry.kcal.map({ "\(Int($0.rounded())) kcal" })
                    ?? entry.waterMl.map({ "\(Int($0.rounded())) mL" }) {
                    Text(entry.isEstimated ? "约 \(amount)" : amount)
                        .font(.footnote.monospacedDigit())
                }
                Button {
                    store.send(.mealEditTapped(entry))
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("编辑 \(entry.foodName)")
                .accessibilityIdentifier("nutrition-entry-edit-\(entry.id)")
                .disabled(store.isSaving)
            }
            .foregroundStyle(BevelTheme.ink)
            Text(entry.portionDescription)
                .font(.footnote)
                .foregroundStyle(BevelTheme.inkSecondary)

            let nutrients = [
                entry.carbsG.map { "碳水 \(formatMetric($0)) g" },
                entry.proteinG.map { "蛋白质 \(formatMetric($0)) g" },
                entry.fatG.map { "脂肪 \(formatMetric($0)) g" }
            ].compactMap(\.self)
            if !nutrients.isEmpty {
                Text(nutrients.joined(separator: " · "))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
            let extraIDs = MealEntry.additionalNutrientIDs.filter { id in
                MealEntry.additionalNutrientKeyPath(id).flatMap { entry[keyPath: $0] } != nil
            }
            if !extraIDs.isEmpty {
                DisclosureGroup("更多营养（\(extraIDs.count) 项）") {
                    ForEach(extraIDs, id: \.self) { id in
                        if let descriptor = NutritionCatalog.allKnownDescriptors[id],
                           let field = MealEntry.additionalNutrientKeyPath(id),
                           let value = entry[keyPath: field] {
                            let prefix = entry.aiEstimatedNutrientIDs?.contains(id) == true ? "约 " : ""
                            let amount = value.formatted(.number.precision(.significantDigits(1...3)))
                            LabeledContent(descriptor.component ?? descriptor.name,
                                           value: "\(prefix)\(amount) \(descriptor.rawUnit ?? descriptor.unit)")
                                .font(.footnote)
                        }
                    }
                }
                .font(.footnote)
            }
            if let note = entry.estimationNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private func microAccordionCard(
        groupKey: String,
        title: String,
        systemImage: String,
        ids: [String]
    ) -> some View {
        let isExpanded = store.expandedMicroGroup == groupKey
        let byID = Dictionary(uniqueKeysWithValues: store.periodSummary.metricAverages.map { ($0.metricID, $0) })
        let items = ids.compactMap { byID[$0] }
        let selectedLog = store.selectedDayLog

        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    store.send(.toggleMicroGroup(groupKey))
                } label: {
                    HStack {
                        Label(title, systemImage: systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(items.prefix(5), id: \.metricID) { avg in
                                Circle()
                                    .fill(avg.isEstimateOnly
                                          ? BevelTheme.inkSecondary.opacity(0.55)
                                          : BevelTheme.nutritionColor(for: avg.status))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(items, id: \.metricID) { avg in
                        let dayEval = NutritionTargetEvaluator.evaluate(
                            metricID: avg.metricID,
                            log: selectedLog,
                            validatedPlan: store.periodSummary.validatedPlan,
                            allowEstimates: true
                        )
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(dayEval.isEstimated
                                      ? BevelTheme.inkSecondary.opacity(0.55)
                                      : BevelTheme.nutritionColor(for: dayEval.status))
                                .frame(width: 9, height: 9)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(avg.metricName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    if dayEval.isEstimated {
                                        Text("估算")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(BevelTheme.surfaceElevated, in: Capsule())
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                    }
                                    Spacer()
                                    let prefix = selectedLog?.entries.contains { $0.aiEstimatedNutrientIDs?.contains(avg.metricID) == true } == true ? "约 " : ""
                                    Text(dayEval.value.map { "\(prefix)\(formatMetric($0)) \(dayEval.displayUnit)" } ?? "--")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.ink)
                                }
                                let periodValue = avg.averageValue ?? avg.estimatedAverageValue
                                let periodPrefix = avg.isEstimateOnly ? "估算 " : ""
                                let targetFloor = store.periodSummary.validatedPlan.validAdoptedItems[avg.metricID]?.lower
                                    ?? store.periodSummary.validatedPlan.validAdoptedItems[avg.metricID]?.upper
                                if let val = dayEval.value, let floor = targetFloor, floor > 0 {
                                    ProgressView(value: min(1.0, max(0.0, val / floor)))
                                        .tint(dayEval.isEstimated
                                              ? BevelTheme.inkSecondary.opacity(0.75)
                                              : BevelTheme.nutritionColor(for: dayEval.status))
                                        .padding(.vertical, 2)
                                }
                                Text("\(dayEval.isEstimated ? "估算 \(dayEval.status.label)（参考）" : dayEval.status.label) · \(dayEval.reason)\(dayEval.isEstimated ? " · AI 估算，仅方向参考" : "") · 周期均值 \(periodPrefix)\(periodValue.map { "\(formatMetric($0))\(avg.unit)" } ?? "--")")
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var quickActionsBar: some View {
        HStack(spacing: 10) {
            Button {
                store.send(.libraryPresented(true))
            } label: {
                Label("营养库", systemImage: "books.vertical")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .bodySeekLiquidPill(isSelected: false)
                    .foregroundStyle(BevelTheme.ink)
            }
            .buttonStyle(.plain)

            Button {
                store.send(.exportDailyMarkdownTapped)
            } label: {
                Label("导出记录", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .bodySeekLiquidPill(isSelected: false)
                    .foregroundStyle(BevelTheme.brand)
            }
            .buttonStyle(.plain)
        }
    }

    private func formatMetric(_ value: Double) -> String {
        if value >= 100 || value == value.rounded() {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}
