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
            LazyVStack(alignment: .leading, spacing: 14) {
                if let error = store.lastError {
                    bannerCard(error, isError: true)
                } else if let status = store.statusMessage {
                    bannerCard(status, isError: false)
                }

                periodHeaderControls

                energyBalanceCard

                macroCircleMatrixCard

                selectedDayMealsCard

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
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("每日营养素")
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
                        Label("个人档案与 DRIs 目标", systemImage: "person.text.rectangle")
                    }
                    Divider()
                    Button {
                        store.send(.exportDailyMarkdownTapped)
                    } label: {
                        Label("导出选中日 Markdown", systemImage: "doc.plaintext")
                    }
                    Button {
                        store.send(.exportTargetsMarkdownTapped)
                    } label: {
                        Label("导出营养目标 Markdown", systemImage: "doc.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("nutrition-more-menu")
            }

            ToolbarItem(placement: .bodyseekTrailing) {
                Button("完成") {
                    store.send(.closeTapped)
                }
                .accessibilityIdentifier("nutrition-done-button")
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .sheet(isPresented: Binding(
            get: { store.showMealLoggerSheet },
            set: { store.send(.mealLoggerPresented($0)) }
        )) {
            NutritionMealLoggerSheet(store: store)
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
        let expenditure: Double? = {
            if let bmr = log?.bmrKcalUsed ?? store.profile?.bmrKcalReference, bmr > 0,
               let active = log?.sportKcal ?? store.snapshot.today.raw.activeEnergyKcal, active >= 0 {
                return bmr + active
            }
            return nil
        }()
        let surplusText: String = {
            if let s = log?.calorieSurplusKcal, isClosed {
                return s >= 0 ? "+\(Int(s.rounded())) kcal" : "\(Int(s.rounded())) kcal"
            }
            return isClosed ? "--" : "未结账"
        }()

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("能量平衡（\(store.selectedDayKey.isoString)）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                        Text(store.periodSummary.validatedPlan.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .lineLimit(2)
                    }
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

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], alignment: .leading, spacing: 10) {
                    energyMetricTile(
                        label: "饮食摄入",
                        value: intake.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "kcal",
                        tint: BevelTheme.brand
                    )
                    energyMetricTile(
                        label: "BMR + 运动消耗",
                        value: expenditure.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "kcal",
                        tint: BevelTheme.strainColor
                    )
                    energyMetricTile(
                        label: "当日盈亏",
                        value: surplusText,
                        unit: isClosed ? "kcal" : "暂不判断",
                        tint: BevelTheme.nutritionInkColor(for: isClosed ? .met : .unknown)
                    )
                    energyMetricTile(
                        label: "近 7 日日均缺口",
                        value: store.periodSummary.rollingDeficit7dKcal.map { "\(Int($0.rounded()))" } ?? "--",
                        unit: "需≥3完整日",
                        tint: BevelTheme.ink
                    )
                }

                if !isClosed {
                    Button {
                        store.send(.closeSelectedDayTapped(reviewSummary: nil))
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("完成 \(store.selectedDayKey.isoString) 饮食结账并结算盈亏")
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
            Text(unit)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
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
                    Text("核心营养与圆圈状态（\(store.periodMode.title)）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                }

                // Four-state honest color legend
                HStack(spacing: 12) {
                    legendDot(color: BevelTheme.nutritionMet, label: "达标")
                    legendDot(color: BevelTheme.nutritionLow, label: "偏低")
                    legendDot(color: BevelTheme.nutritionOver, label: "偏高/超UL")
                    legendDot(color: BevelTheme.nutritionUnknown, label: "未记/未结账")
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
        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(store.selectedDayKey.isoString) 餐次记录")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    Button {
                        store.send(.mealLoggerPresented(true))
                    } label: {
                        Label("记一餐", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BevelTheme.brand, in: Capsule())
                            .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nutrition-log-meal-button")
                }

                if let entries = log?.entries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.mealType.title)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(BevelTheme.surfaceElevated, in: Capsule())
                                .foregroundStyle(BevelTheme.brand)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.foodName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(BevelTheme.ink)
                                    if entry.isEstimated {
                                        Text("估算")
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                    }
                                    Spacer()
                                    Text(entry.kcal.map { "\(Int($0.rounded())) kcal" } ?? entry.waterMl.map { "\(Int($0.rounded())) mL" } ?? "--")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.ink)
                                }
                                Text("\(entry.portionDescription) · 碳 \(entry.carbsG.map(formatMetric) ?? "--")g · 蛋 \(entry.proteinG.map(formatMetric) ?? "--")g · 脂 \(entry.fatG.map(formatMetric) ?? "--")g")
                                    .font(.caption2.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                    }
                } else {
                    Text("该生理日暂无餐次明细；点击右上「记一餐」即可按营养库精准换算。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-selected-day-card")
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
                                    .fill(BevelTheme.nutritionColor(for: avg.status))
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
                            validatedPlan: store.periodSummary.validatedPlan
                        )
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(BevelTheme.nutritionColor(for: dayEval.status))
                                .frame(width: 9, height: 9)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(avg.metricName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    Spacer()
                                    Text(dayEval.value.map { "\(formatMetric($0)) \(dayEval.displayUnit)" } ?? "--")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.ink)
                                }
                                Text("\(dayEval.reason) · 周期均值 \(avg.averageValue.map { "\(formatMetric($0))\(avg.unit)" } ?? "--")")
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
                Label("营养库（\(store.foodLibrary.count)）", systemImage: "books.vertical")
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
                Label("导出 MD", systemImage: "square.and.arrow.up")
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
