import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 营养页：L0 摄入环；L1 Coach 解读；L2 记一餐、当天餐次、本周热量；L3 周月看板、能量平衡、微量营养素二级页与营养目标。
public struct NutritionBoardView: View {
    private static let calorieID = "diet_kcal"

    @Bindable var store: StoreOf<NutritionFeature>

    public init(store: StoreOf<NutritionFeature>) {
        self.store = store
    }

    public var body: some View {
        BSPage("营养") {
            heroSection
        } note: {
            noteSection
        } sections: {
            sectionsContent
        } links: {
            linksContent
        }
        .oneLineHeader(subtitle: "今日饮食") {
            BSHeaderButton(systemImage: "plus", label: "记一餐", identifier: "nutrition-log-meal-header") {
                store.send(.mealLoggerPresented(true))
            }
            moreMenu
        }
        .onAppear {
            store.send(.onAppear)
        }
        .sheet(item: mealLoggerBinding) { logger in
            mealLoggerSheet(logger)
        }
        .sheet(isPresented: libraryBinding) {
            NutritionLibrarySheet(store: store)
        }
        .sheet(isPresented: profileBinding) {
            NutritionProfileTargetSheet(store: store)
        }
        .sheet(isPresented: markdownBinding) {
            if let md = store.exportedMarkdown {
                NutritionMarkdownSheet(markdown: md) {
                    store.send(.markdownSheetDismissed)
                }
            }
        }
    }

    // MARK: - 工具栏与弹层

    private var moreMenu: some View {
        BSHeaderMenu(systemImage: "ellipsis", label: "更多", identifier: "nutrition-more-menu") {
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
        }
    }

    private var mealLoggerBinding: Binding<NutritionFeature.MealLogger?> {
        Binding(
            get: { store.mealLogger },
            set: { if $0 == nil { store.send(.mealLoggerPresented(false)) } }
        )
    }

    private var libraryBinding: Binding<Bool> {
        Binding(
            get: { store.showLibrarySheet },
            set: { store.send(.libraryPresented($0)) }
        )
    }

    private var profileBinding: Binding<Bool> {
        Binding(
            get: { store.showProfileTargetSheet },
            set: { store.send(.profileTargetPresented($0)) }
        )
    }

    private var markdownBinding: Binding<Bool> {
        Binding(
            get: { store.exportedMarkdown != nil },
            set: { if !$0 { store.send(.markdownSheetDismissed) } }
        )
    }

    @ViewBuilder
    private func mealLoggerSheet(_ logger: NutritionFeature.MealLogger) -> some View {
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

    // MARK: - L0 摄入环

    private var heroSection: some View {
        VStack(spacing: BSSpace.s) {
            banner
            intakeCard
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let error = store.lastError {
            BSStateView(.error, message: error)
        } else if let status = store.statusMessage {
            BSCard {
                Label(status, systemImage: "checkmark.circle.fill")
                    .bsText(.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var intakeCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text(intakeTitle)
                    .bsText(.cardTitle)
                BSIntakeRing(
                    calories: store.selectedDayLog?.dietKcal,
                    target: target(Self.calorieID),
                    availability: intakeAvailability,
                    isEstimate: hasEstimates,
                    macros: macros
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-intake-ring")
    }

    private var intakeTitle: String {
        let day = store.selectedDayKey
        let suffix = day == store.todayKey ? " · 今天" : ""
        return "\(day.month)月\(day.day)日摄入\(suffix)"
    }

    private var intakeAvailability: MetricAvailability {
        guard let log = store.selectedDayLog else { return .missing(reason: "这一天还没有饮食记录") }
        if log.dietKcal == nil { return .missing(reason: "已记录的餐次缺少热量") }
        return .available
    }

    private var hasEstimates: Bool {
        store.selectedDayLog?.entries.contains(where: \.isEstimated) == true
    }

    private var macros: [BSMacroProgress] {
        [
            macro("碳水", id: "diet_carbs_g"),
            macro("蛋白质", id: "diet_protein_g"),
            macro("脂肪", id: "diet_fat_g"),
        ]
    }

    private func macro(_ name: String, id: String) -> BSMacroProgress {
        let reading = NutritionTargetEvaluator.evaluate(
            metricID: id,
            log: store.selectedDayLog,
            validatedPlan: store.periodSummary.validatedPlan
        )
        return BSMacroProgress(name: name, value: reading.value, target: target(id), unit: "g")
    }

    private func target(_ id: String) -> Double? {
        let item = store.periodSummary.validatedPlan.validAdoptedItems[id]
        return item?.lower ?? item?.upper
    }

    // MARK: - L1 Coach 解读

    private var noteSection: some View {
        BSCoachNote(
            noteText,
            engine: BSBriefEngine(store.dailyBrief?.engine),
            onAsk: askCoachAction,
            askIdentifier: "nutrition-ask-coach-button"
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-coach-advice-card")
    }

    private var askCoachAction: () -> Void {
        { store.send(.askCoachTapped("结合我这几天的营养摄入与维生素矿物质估算情况，帮我搭配下一顿，指出优先补充什么。")) }
    }

    private var noteText: String {
        if case let .generated(text, _) = store.coachAdviceStatus { return text }
        return store.deterministicAdviceSummary
    }

    // MARK: - L2 记一餐、当天餐次、本周热量

    @ViewBuilder
    private var sectionsContent: some View {
        BSSection("记一餐") {
            recordCard
        }
        BSSection("当天餐次") {
            mealsCard
        }
        BSSection(weekTitle) {
            weekCard
        }
    }

    private var recordCard: some View {
        BSCard {
            VStack(spacing: BSSpace.s) {
                Button {
                    store.send(.mealAssistantTapped)
                } label: {
                    Label("AI 记饮食（文字 / 拍照）", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BSColor.tint)
                .frame(minHeight: BSSize.hitTarget)
                .accessibilityIdentifier("nutrition-ai-entry")

                Button {
                    store.send(.mealLoggerPresented(true))
                } label: {
                    Label("手动记录", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: BSSize.hitTarget)
                .accessibilityIdentifier("nutrition-log-meal-button")
            }
        }
    }

    private var mealsCard: some View {
        let log = store.selectedDayLog
        let entries = log?.entries ?? []
        let byMeal = Dictionary(grouping: entries, by: \.mealType)
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text(mealsStatusLine(entries: entries))
                    .bsText(.label)
                if entries.isEmpty {
                    Text("这一天还没有饮食记录。")
                        .bsText(.caption)
                } else {
                    ForEach(MealType.allCases, id: \.self) { meal in
                        if let mealEntries = byMeal[meal] {
                            Divider()
                            mealGroup(meal, entries: mealEntries)
                        }
                    }
                }
                if log?.dietDayComplete != true {
                    closeDayButton
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-selected-day-card")
    }

    private func mealsStatusLine(entries: [MealEntry]) -> String {
        let day = store.selectedDayKey
        let dateLabel = day.year == store.todayKey.year ? "\(day.month) 月 \(day.day) 日" : day.isoString
        if entries.isEmpty { return dateLabel }
        return "\(dateLabel) · \(closeStatus)"
    }

    private var closeStatus: String {
        let log = store.selectedDayLog
        guard log?.dietDayComplete == true else { return "记录未完成" }
        let partial = log?.dietPartialFields ?? []
        return partial.isEmpty ? "已完成记录" : "已结账 · \(partial.count) 餐有缺项"
    }

    private var closeDayButton: some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            Button {
                store.send(.closeSelectedDayTapped(reviewSummary: nil))
            } label: {
                Label("完成当天记录", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: BSSize.hitTarget)
            .disabled(store.isSaving)
            .accessibilityIdentifier("nutrition-close-day-button")

            if let partial = store.selectedDayLog?.dietPartialFields, !partial.isEmpty {
                Text("还有 \(partial.count) 餐缺少热量或宏量营养素；结账后仍不会判定达标，补齐后才会参与四态评价。")
                    .bsText(.caption)
            }
        }
    }

    private func mealGroup(_ meal: MealType, entries: [MealEntry]) -> some View {
        let values = entries.compactMap { meal == .water ? $0.waterMl : $0.kcal }
        let unit = meal == .water ? "mL" : "kcal"
        let total = values.count == entries.count ? "\(Int(values.reduce(0, +).rounded())) \(unit)" : nil
        let hasEstimates = entries.contains(where: \.isEstimated)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                ForEach(entries) { entry in
                    mealEntryRow(entry)
                }
            }
            .padding(.top, BSSpace.xs)
        } label: {
            HStack {
                Text(meal.title)
                    .bsText(.cardTitle)
                Text("\(entries.count) 项")
                    .bsText(.caption)
                Spacer()
                if let total {
                    Text(hasEstimates ? "约 \(total)" : total)
                        .bsText(.label)
                }
            }
        }
        .accessibilityIdentifier("nutrition-meal-\(meal.rawValue)")
    }

    private func mealEntryRow(_ entry: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: BSSpace.xxs) {
            HStack {
                Text(entry.foodName)
                    .bsText(.label)
                Spacer()
                Text(entryAmount(entry))
                    .bsText(.caption)
                Button {
                    store.send(.mealEditTapped(entry))
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: BSSize.hitTarget, height: BSSize.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.bsPressable)
                .accessibilityLabel("编辑 \(entry.foodName)")
                .accessibilityIdentifier("nutrition-entry-edit-\(entry.id)")
                .disabled(store.isSaving)
            }
            Text(entry.portionDescription)
                .bsText(.caption)
            entryNutrients(entry)
            entryExtras(entry)
            if let note = entry.estimationNote, !note.isEmpty {
                Text(note)
                    .bsText(.caption)
            }
        }
    }

    private func entryAmount(_ entry: MealEntry) -> String {
        if let estimate = entry.energyEstimate { return "粗估 \(estimate.displayRange)" }
        let kcal = entry.kcal.map { "\(Int($0.rounded())) kcal" }
        let water = entry.waterMl.map { "\(Int($0.rounded())) mL" }
        guard let amount = kcal ?? water else { return "" }
        return entry.isEstimated ? "约 \(amount)" : amount
    }

    @ViewBuilder
    private func entryNutrients(_ entry: MealEntry) -> some View {
        let nutrients = [
            entry.carbsG.map { "碳水 \(nutritionFormatMetric($0)) g" },
            entry.proteinG.map { "蛋白质 \(nutritionFormatMetric($0)) g" },
            entry.fatG.map { "脂肪 \(nutritionFormatMetric($0)) g" },
        ].compactMap(\.self)
        if !nutrients.isEmpty {
            Text(nutrients.joined(separator: " · "))
                .bsText(.caption)
        }
    }

    @ViewBuilder
    private func entryExtras(_ entry: MealEntry) -> some View {
        let extraIDs = MealEntry.additionalNutrientIDs.filter { id in
            MealEntry.additionalNutrientKeyPath(id).flatMap { entry[keyPath: $0] } != nil
        }
        if !extraIDs.isEmpty {
            DisclosureGroup("更多营养（\(extraIDs.count) 项）") {
                ForEach(extraIDs, id: \.self) { id in
                    extraRow(entry, id: id)
                }
            }
            .bsText(.caption)
        }
    }

    @ViewBuilder
    private func extraRow(_ entry: MealEntry, id: String) -> some View {
        if let descriptor = NutritionCatalog.allKnownDescriptors[id],
           let field = MealEntry.additionalNutrientKeyPath(id),
           let value = entry[keyPath: field] {
            let prefix = entry.aiEstimatedNutrientIDs?.contains(id) == true ? "约 " : ""
            let amount = value.formatted(.number.precision(.significantDigits(1...3)))
            LabeledContent(
                descriptor.component ?? descriptor.name,
                value: "\(prefix)\(amount) \(descriptor.rawUnit ?? descriptor.unit)"
            )
            .bsText(.caption)
        }
    }

    private var weekTitle: String {
        store.periodMode == .month ? "本月热量" : "本周热量"
    }

    private var weekCard: some View {
        let summary = store.periodSummary
        let average = summary.metricAverages.first(where: { $0.metricID == Self.calorieID })?.averageValue
        return BSChartCard(
            title: weekTitle,
            label: "日均摄入",
            value: average.map { nutritionFormatMetric($0) },
            unit: "kcal",
            range: "\(summary.startDayKey.isoString) – \(summary.endDayKey.isoString)",
            side: deficitSide(summary.rollingDeficit7dKcal),
            availability: weekAvailability,
            height: .standard,
            caption: "只统计已记录的天数，缺失的天不计作零"
        ) {
            IntakeBarChart(points: weekPoints, target: target(Self.calorieID)) { id in
                if let key = store.periodDayKeys.first(where: { $0.isoString == id }) {
                    store.send(.daySelected(key))
                }
            }
        }
    }

    private var weekPoints: [IntakeBarPoint] {
        store.periodDayKeys.map { key in
            IntakeBarPoint(
                id: key.isoString,
                label: String(key.day),
                kcal: store.periodSummary.dayLogsByKey[key]?.dietKcal,
                isSelected: key == store.selectedDayKey
            )
        }
    }

    private var weekAvailability: MetricAvailability {
        let hasData = weekPoints.contains { $0.kcal != nil }
        return hasData ? .available : .missing(reason: "这段时间还没有已记录热量的天")
    }

    private func deficitSide(_ deficit: Double?) -> String {
        guard let deficit else { return "7 天日均：不足 3 天" }
        let kcal = Int(abs(deficit).rounded())
        if deficit < -30 { return "7 天日均盈余 \(kcal) kcal" }
        if deficit > 30 { return "7 天日均缺口 \(kcal) kcal" }
        return "7 天日均平衡"
    }

    // MARK: - L3

    @ViewBuilder
    private var linksContent: some View {
        BSSection("周月看板") {
            VStack(spacing: BSSpace.s) {
                periodControls
                macroMatrixCard
            }
        }
        BSSection("能量平衡") {
            energyBalanceCard
        }
        VStack(spacing: BSSpace.s) {
            BSNavRow("微量营养素明细", systemImage: "pills.fill", value: "29 项") {
                NutritionMicronutrientsView(store: store)
            }
            targetsRow
        }
    }

    private var targetsRow: some View {
        Button {
            store.send(.profileTargetPresented(true))
        } label: {
            BSCard {
                HStack(spacing: BSSpace.s) {
                    Label("营养目标", systemImage: "target")
                        .bsText(.cardTitle)
                    Spacer(minLength: BSSpace.xs)
                    Image(systemName: "chevron.right")
                        .bsText(.caption)
                }
            }
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("nutrition-targets-button")
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: BSSpace.s) {
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
                stepButton(systemImage: "chevron.left.circle.fill", step: -1, disabled: false)
                Spacer()
                Text("\(store.periodSummary.startDayKey.isoString) – \(store.periodSummary.endDayKey.isoString)")
                    .bsText(.label)
                Spacer()
                stepButton(systemImage: "chevron.right.circle.fill", step: 1, disabled: store.anchorDayKey >= store.todayKey)
            }
        }
    }

    private func stepButton(systemImage: String, step: Int, disabled: Bool) -> some View {
        Button {
            store.send(.stepPeriod(step))
        } label: {
            Image(systemName: systemImage)
                .frame(width: BSSize.hitTarget, height: BSSize.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.bsPressable)
        .disabled(disabled)
        .accessibilityLabel(step < 0 ? "上一个周期" : "下一个周期")
    }

    private var energyBalanceCard: some View {
        let log = store.selectedDayLog
        let isClosed = log?.dietDayComplete == true
        let energy = log.map { MealEnergySummary(entries: $0.entries) }
        let intakeText = energy?.displayRange ?? log?.dietKcal.map { nutritionFormatMetric($0) }
        let balanceText: String? = isClosed ? closedBalanceText(log) : "未完成"
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                BSMetricGrid {
                    BSMetricTile(title: "饮食摄入", value: intakeText, unit: "kcal", availability: tileAvailability(intakeText))
                    BSMetricTile(title: "消耗估算", value: expenditureText(log), unit: "kcal", availability: tileAvailability(expenditureText(log)))
                    BSMetricTile(title: "能量差", value: balanceText, unit: "kcal", availability: tileAvailability(balanceText))
                }
                energyFootnotes(energy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-energy-balance-card")
    }

    private func tileAvailability(_ value: String?) -> MetricAvailability {
        value == nil ? .missing(reason: "暂无数据") : .available
    }

    private func closedBalanceText(_ log: DailyNutritionLog?) -> String? {
        guard let surplus = log?.calorieSurplusKcal else { return nil }
        let kcal = Int(surplus.rounded())
        return kcal > 0 ? "+\(kcal)" : "\(kcal)"
    }

    private func expenditureText(_ log: DailyNutritionLog?) -> String? {
        guard let bmr = log?.bmrKcalUsed ?? store.profile?.bmrKcalReference, bmr > 0,
              let active = log?.sportKcal ?? store.selectedHealthDay?.raw.activeEnergyKcal, active >= 0
        else { return nil }
        return "\(Int((bmr + active).rounded()))"
    }

    @ViewBuilder
    private func energyFootnotes(_ energy: MealEnergySummary?) -> some View {
        if let energy {
            if energy.displayRange != nil, let known = energy.knownKcalSubtotal {
                Text("已有数值小计 \(known.formatted(.number.precision(.fractionLength(0)))) kcal")
                    .bsText(.caption)
            }
            if energy.missingEntryCount > 0 {
                Text("\(energy.missingEntryCount) 项热量待补")
                    .bsText(.caption)
            }
        }
    }

    private var macroMatrixCard: some View {
        let displayDays = store.periodDayKeys
        let macroIDs = Set(NutritionCatalog.macroDescriptors.map(\.id))
        let macroAverages = store.periodSummary.metricAverages.filter { macroIDs.contains($0.metricID) }
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Text("营养摄入")
                        .bsText(.cardTitle)
                    Spacer()
                    if store.periodMode == .month {
                        Text("左右滑动查看完整 \(displayDays.count) 天")
                            .bsText(.caption)
                    }
                }
                matrixLegend
                matrixGrid(days: displayDays, averages: macroAverages)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-macro-matrix")
    }

    private var matrixLegend: some View {
        HStack(spacing: BSSpace.s) {
            legendDot(color: BevelTheme.nutritionMet, label: "达标")
            legendDot(color: BevelTheme.nutritionLow, label: "偏低")
            legendDot(color: BevelTheme.nutritionOver, label: "偏高或超上限")
            legendDot(color: BevelTheme.nutritionUnknown, label: "记录未完成")
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Circle()
                .fill(color)
                .frame(width: BSSize.dot, height: BSSize.dot)
            Text(label)
                .bsText(.caption)
        }
    }

    private func matrixGrid(days: [DayKey], averages: [NutritionMetricPeriodAverage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                matrixHeader(days: days)
                ForEach(averages, id: \.metricID) { avg in
                    matrixRow(avg, days: days)
                }
            }
        }
        .defaultScrollAnchor(.trailing)
    }

    private var labelColumnWidth: CGFloat { BSSize.ringM }
    private var averageColumnWidth: CGFloat { BSSize.ringM + BSSpace.m }

    private func matrixHeader(days: [DayKey]) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Text("营养指标")
                .bsText(.caption)
                .frame(width: labelColumnWidth, alignment: .leading)
            ForEach(days, id: \.self) { key in
                dayButton(key)
            }
            Text("均值")
                .bsText(.caption)
                .frame(width: averageColumnWidth, alignment: .trailing)
        }
    }

    private func dayButton(_ key: DayKey) -> some View {
        let isSelected = key == store.selectedDayKey
        return Button {
            store.send(.daySelected(key))
        } label: {
            Text(String(format: "%d", key.day))
                .bsText(.caption)
                .frame(width: BSSize.glyph, height: BSSize.glyph)
                .background(isSelected ? BSColor.tint.opacity(BSOpacity.faint) : Color.clear, in: Capsule())
        }
        .buttonStyle(.bsPressable)
    }

    private func matrixRow(_ avg: NutritionMetricPeriodAverage, days: [DayKey]) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Text(avg.metricName)
                .bsText(.caption)
                .lineLimit(1)
                .frame(width: labelColumnWidth, alignment: .leading)
            ForEach(days, id: \.self) { key in
                matrixCell(avg, key: key)
            }
            HStack(spacing: BSSpace.xxs) {
                Circle()
                    .fill(BevelTheme.nutritionColor(for: avg.status))
                    .frame(width: BSSize.dot, height: BSSize.dot)
                Text(avg.averageValue.map { "\(nutritionFormatMetric($0))\(avg.unit)" } ?? "--")
                    .bsText(.caption)
                    .lineLimit(1)
            }
            .frame(width: averageColumnWidth, alignment: .trailing)
        }
    }

    private func matrixCell(_ avg: NutritionMetricPeriodAverage, key: DayKey) -> some View {
        let reading = NutritionTargetEvaluator.evaluate(
            metricID: avg.metricID,
            log: store.periodSummary.dayLogsByKey[key],
            validatedPlan: store.periodSummary.validatedPlan
        )
        let isSelected = key == store.selectedDayKey
        return Button {
            store.send(.daySelected(key))
        } label: {
            Circle()
                .fill(BevelTheme.nutritionColor(for: reading.status))
                .frame(width: BSSpace.s, height: BSSpace.s)
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: BSChartStroke.micro)
                }
        }
        .buttonStyle(.bsPressable)
        .frame(width: BSSize.glyph)
        .accessibilityLabel("\(avg.metricName) \(key.isoString) \(reading.status.label)")
    }
}
