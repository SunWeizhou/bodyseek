import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 二级页：29 项微量营养素（14 项维生素 + 15 项矿物质）。一级页只保留热量和三大宏量。
struct NutritionMicronutrientsView: View {
    @Bindable var store: StoreOf<NutritionFeature>

    var body: some View {
        BSPage("微量营养素") {
            Text("按所选日期的记录和当前周期的均值评估；AI 估算的数值只作方向参考。")
                .bsText(.caption)
        } sections: {
            microGroup(
                groupKey: "vitamins",
                title: "维生素追踪（14 项）",
                systemImage: "pills.fill",
                ids: NutritionCatalog.vitaminOrder.map { "diet_vitamins::\($0)" }
            )
            microGroup(
                groupKey: "minerals",
                title: "矿物质追踪（15 项）",
                systemImage: "atom",
                ids: NutritionCatalog.mineralOrder.map { "diet_minerals::\($0)" }
            )
        }
    }

    private func microGroup(groupKey: String, title: String, systemImage: String, ids: [String]) -> some View {
        let isExpanded = store.expandedMicroGroup == groupKey
        let byID = Dictionary(uniqueKeysWithValues: store.periodSummary.metricAverages.map { ($0.metricID, $0) })
        let items = ids.compactMap { byID[$0] }
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                groupHeader(groupKey: groupKey, title: title, systemImage: systemImage, items: items, isExpanded: isExpanded)
                if isExpanded {
                    ForEach(items, id: \.metricID) { avg in
                        metricRow(avg)
                    }
                }
            }
        }
    }

    private func groupHeader(
        groupKey: String,
        title: String,
        systemImage: String,
        items: [NutritionMetricPeriodAverage],
        isExpanded: Bool
    ) -> some View {
        Button {
            store.send(.toggleMicroGroup(groupKey))
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .bsText(.cardTitle)
                Spacer()
                HStack(spacing: BSSpace.xxs) {
                    ForEach(items.prefix(5), id: \.metricID) { avg in
                        Circle()
                            .fill(statusColor(estimateOnly: avg.isEstimateOnly, status: avg.status))
                            .frame(width: BSSize.dot, height: BSSize.dot)
                    }
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .bsText(.caption)
            }
            .frame(minHeight: BSSize.hitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.bsPressable)
    }

    private func statusColor(estimateOnly: Bool, status: NutritionReadingStatus) -> Color {
        estimateOnly ? BSColor.dimmed : BevelTheme.nutritionColor(for: status)
    }

    private func metricRow(_ avg: NutritionMetricPeriodAverage) -> some View {
        let selectedLog = store.selectedDayLog
        let dayEval = NutritionTargetEvaluator.evaluate(
            metricID: avg.metricID,
            log: selectedLog,
            validatedPlan: store.periodSummary.validatedPlan,
            allowEstimates: true
        )
        return HStack(alignment: .top, spacing: BSSpace.xs) {
            Circle()
                .fill(statusColor(estimateOnly: dayEval.isEstimated, status: dayEval.status))
                .frame(width: BSSize.dot, height: BSSize.dot)
                .padding(.top, BSSpace.xxs)
            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                metricTitleLine(avg, dayEval: dayEval)
                progressLine(avg, dayEval: dayEval)
                Text(metricDetail(avg, dayEval: dayEval))
                    .bsText(.caption)
            }
        }
    }

    private func metricTitleLine(_ avg: NutritionMetricPeriodAverage, dayEval: NutritionEvaluatedReading) -> some View {
        let aiEstimated = store.selectedDayLog?.entries.contains { $0.aiEstimatedNutrientIDs?.contains(avg.metricID) == true } == true
        let prefix = aiEstimated ? "约 " : ""
        let valueText = dayEval.value.map { "\(prefix)\(nutritionFormatMetric($0)) \(dayEval.displayUnit)" } ?? "--"
        return HStack {
            Text(avg.metricName)
                .bsText(.label)
            if dayEval.isEstimated {
                BSEvidenceChip("估算")
            }
            Spacer()
            Text(valueText)
                .bsText(.label)
        }
    }

    @ViewBuilder
    private func progressLine(_ avg: NutritionMetricPeriodAverage, dayEval: NutritionEvaluatedReading) -> some View {
        let item = store.periodSummary.validatedPlan.validAdoptedItems[avg.metricID]
        let floor = item?.lower ?? item?.upper
        if let value = dayEval.value, let floor, floor > 0 {
            ProgressView(value: min(1.0, max(0.0, value / floor)))
                .tint(statusColor(estimateOnly: dayEval.isEstimated, status: dayEval.status))
        }
    }

    private func metricDetail(_ avg: NutritionMetricPeriodAverage, dayEval: NutritionEvaluatedReading) -> String {
        let periodValue = avg.averageValue ?? avg.estimatedAverageValue
        let periodPrefix = avg.isEstimateOnly ? "估算 " : ""
        let periodText = periodValue.map { "\(nutritionFormatMetric($0))\(avg.unit)" } ?? "--"
        let statusText = dayEval.isEstimated ? "估算 \(dayEval.status.label)（参考）" : dayEval.status.label
        let aiNote = dayEval.isEstimated ? " · AI 估算，仅方向参考" : ""
        return "\(statusText) · \(dayEval.reason)\(aiNote) · 周期均值 \(periodPrefix)\(periodText)"
    }
}

/// 营养数值的统一格式：≥100 或整数不带小数，其余保留一位。
func nutritionFormatMetric(_ value: Double) -> String {
    if value >= 100 || value == value.rounded() {
        return "\(Int(value.rounded()))"
    }
    return String(format: "%.1f", value)
}
