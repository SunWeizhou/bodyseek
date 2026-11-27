import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 实验室二级页：明日预测。统计预测，不是诊断。
struct TrendsForecastLabView: View {
    @Bindable var store: StoreOf<TrendsFeature>

    var body: some View {
        BSPage("明日预测") {
            Text("基于你自己的历史数据做统计预测；区间来自历史误差校准，不构成医疗诊断。")
                .bsText(.caption)
        } sections: {
            personalForecastCard
        }
    }

    private var personalForecastCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack(spacing: BSSpace.xs) {
                    Label("身体预测", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text("统计预测 · 非诊断")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, BSSpace.xs)
                        .padding(.vertical, BSSpace.xxs)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                }

                switch store.personalForecast {
                case let .insufficientData(observedDays, minimumRequired, _):
                    Text("数据还不够。已记录 \(observedDays) 个有效日，至少需要 \(minimumRequired) 天才能运行端侧多目标预测模型。")
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.inkSecondary)

                case let .available(summary):
                    let selectedTarget = summary.target(named: store.selectedForecastTargetName)
                        ?? summary.targets.first

                    HStack {
                        Text("\(summary.targetDayKey.month) 月 \(summary.targetDayKey.day) 日明日预测")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Spacer()
                        Text(summary.runtimeBackend.contains("CoreML") ? "端侧 CoreML" : "本地线性基座")
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    Picker("预测指标", selection: Binding(
                        get: { selectedTarget?.name ?? store.selectedForecastTargetName },
                        set: { store.send(.forecastTargetSelected($0)) }
                    )) {
                        ForEach(summary.targets) { target in
                            Text(shortForecastTitle(for: target)).tag(target.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("trends-forecast-target-picker")

                    if let target = selectedTarget {
                        let targetTint = forecastTint(for: target.name)
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                Text(forecastTitle(for: target))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Text(formattedInterval(for: target))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                Text("近 14 天实测 \(target.recent14dObservedDays)/14 天 · 累计 \(target.totalObservedDays) 天")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(target.hasDirectTargetEvidence ? BevelTheme.inkSecondary : BevelTheme.energyColor)
                            }
                            Spacer()
                            Text(formattedPoint(for: target))
                                .font(.title2.weight(.bold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(targetTint)
                        }
                        .padding(BSSpace.s)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))

                        if !target.hasDirectTargetEvidence {
                            Text("近 14 天「\(shortForecastTitle(for: target))」直接实测不足（\(target.recent14dObservedDays) 天），当前预测由其他特征跨指标推算，区间仅供参考。")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.energyColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForecastFanChart(
                            target: target,
                            historyPoints: forecastHistoryPoints(for: target.name),
                            targetDate: summary.targetDayKey.calendarDayStart(),
                            tint: targetTint,
                            height: 186
                        )

                        VStack(alignment: .leading, spacing: BSSpace.xs) {
                            Text("模型预测特征贡献分解（非因果）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.inkSecondary)

                            FeatureAttributionChart(
                                drivers: target.drivers,
                                targetName: target.name,
                                height: 144
                            )
                        }
                        .padding(BSSpace.s)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
                    }

                    let secondaryTargets = summary.targets.filter { $0.name != selectedTarget?.name }
                    if !secondaryTargets.isEmpty {
                        HStack(spacing: BSSpace.xs) {
                            ForEach(secondaryTargets) { item in
                                Button {
                                    store.send(.forecastTargetSelected(item.name))
                                } label: {
                                    VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                        Text(shortForecastTitle(for: item))
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                        Text(formattedPoint(for: item))
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                            .fontDesign(.rounded)
                                            .foregroundStyle(BevelTheme.ink)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(BSSpace.xs)
                                    .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous))
                                }
                                .buttonStyle(.bsPressable)
                            }
                        }
                    }

                    DisclosureGroup("模型回测精度与技术依据") {
                        VStack(alignment: .leading, spacing: BSSpace.xs) {
                            Text("使用 \(summary.observedDays) 天因果特征。预测范围按 Split-Conformal 历史校准误差生成，仅作自我变化参考，不构成医疗诊断。")
                            ForEach(summary.targets) { target in
                                Text("\(forecastTitle(for: target)) · 回测 MAE \(formattedError(for: target)) · 80% 覆盖率 \(Int((target.walkForwardCov80 * 100).rounded()))%")
                            }
                            Text("模型 \(summary.modelVersion) · \(summary.runtimeBackend)")
                        }
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .padding(.top, BSSpace.xs)
                    }
                    .font(.subheadline)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-personal-forecast-card")
    }


    private func forecastHistoryPoints(for targetName: String) -> [(date: Date, value: Double)] {
        let ordered = store.snapshot.historyDays.sorted { $0.dayKey < $1.dayKey }.suffix(14)
        return ordered.compactMap { day -> (Date, Double)? in
            switch targetName {
            case "hrv_sdnn_ms":
                return day.raw.hrvMs.map { (day.date, $0) }
            case "resting_hr_bpm":
                return day.raw.restingHeartRateBpm.map { (day.date, $0) }
            case "sleep_efficiency":
                guard let asleep = day.raw.sleepAsleepMinutes, asleep > 0 else { return nil }
                let denom = max(day.raw.sleepInBedMinutes ?? 0, asleep + (day.raw.awakeMinutes ?? 0))
                guard denom > 0 else { return nil }
                return (day.date, min(1.0, max(0.0, Double(asleep) / Double(denom))))
            default:
                return nil
            }
        }
    }

    private func forecastTint(for targetName: String) -> Color {
        switch targetName {
        case "hrv_sdnn_ms": BevelTheme.recoveryColor
        case "resting_hr_bpm": BevelTheme.heartRateAverage
        case "sleep_efficiency": BevelTheme.sleepColor
        default: BevelTheme.brand
        }
    }

    private func forecastTitle(for target: PersonalForecastTargetResult) -> String {
        switch target.name {
        case "hrv_sdnn_ms": "夜间心率变异性 (HRV)"
        case "resting_hr_bpm": "晨间静息心率 (RHR)"
        case "sleep_efficiency": "夜间睡眠效率"
        default: target.title
        }
    }

    private func shortForecastTitle(for target: PersonalForecastTargetResult) -> String {
        switch target.name {
        case "hrv_sdnn_ms": "HRV"
        case "resting_hr_bpm": "静息心率"
        case "sleep_efficiency": "睡眠效率"
        default: target.title
        }
    }

    private func formattedPoint(for target: PersonalForecastTargetResult) -> String {
        if target.name == "sleep_efficiency" {
            return String(format: "%.1f%%", target.point * 100.0)
        }
        return String(format: "%.1f %@", target.point, target.unit)
    }

    private func formattedInterval(for target: PersonalForecastTargetResult) -> String {
        if target.name == "sleep_efficiency" {
            return String(format: "80%% 预测范围 %.1f%%–%.1f%%",
                          target.interval80Low * 100, target.interval80High * 100)
        }
        return String(format: "80%% 预测范围 %.1f–%.1f %@",
                      target.interval80Low, target.interval80High, target.unit)
    }

    private func formattedError(for target: PersonalForecastTargetResult) -> String {
        if target.name == "sleep_efficiency" {
            return String(format: "%.1f 个百分点", target.walkForwardMAE * 100)
        }
        return String(format: "%.2f %@", target.walkForwardMAE, target.unit)
    }
}

/// 实验室二级页：我的规律（统计关联，不是因果）。
struct TrendsPatternsLabView: View {
    @Bindable var store: StoreOf<TrendsFeature>

    var body: some View {
        BSPage("我的规律") {
            Text("规律来自你自己的历史数据，确认后会保存到 Coach 记忆。")
                .bsText(.caption)
        } sections: {
            patternsCard
        }
    }

    private var patternsCard: some View {
        let activeFindings = store.patternFindings.filter { $0.status != .dismissed }
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Label("我的规律", systemImage: "waveform.and.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text("统计关联 · 非因果")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                if activeFindings.isEmpty {
                    Text("还没有足够的历史记录来显示规律。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PatternForestChart(findings: Array(activeFindings.prefix(4)))
                        .padding(BSSpace.s)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))

                    ForEach(activeFindings.prefix(4)) { finding in
                        let summary = finding.statement.components(separatedBy: "（95% CI ").first ?? finding.statement

                        VStack(alignment: .leading, spacing: BSSpace.xs) {
                            HStack(spacing: BSSpace.xs) {
                                Text(finding.status == .confirmed ? "已确认" : "待确认")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, BSSpace.xs)
                                    .padding(.vertical, BSSpace.xxs)
                                    .background(
                                        finding.status == .confirmed ? Color.green.opacity(BSOpacity.faint) : BevelTheme.brandSoft,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(finding.status == .confirmed ? Color.green : BevelTheme.brand)

                                if M4APersonalPatternSeeds.seedIDs.contains(finding.id) {
                                    Text("示例预置")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, BSSpace.xs)
                                        .padding(.vertical, BSSpace.xxs)
                                        .background(BevelTheme.surfaceElevated, in: Capsule())
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                            }
                            Text(summary)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BevelTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("统计详情") {
                                VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                    if summary != finding.statement {
                                        Text(finding.statement)
                                    }
                                    Text(String(
                                        format: "%d 个样本 · 95%% 置信区间 %.2f 至 %.2f\n%@",
                                        finding.sampleSize, finding.ciLow, finding.ciHigh, finding.method
                                    ))
                                }
                                .font(.footnote)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .padding(.top, BSSpace.xxs)
                            }
                            .font(.subheadline)

                            if finding.status == .candidate {
                                HStack(spacing: BSSpace.s) {
                                    Button("确认规律") {
                                        store.send(.confirmPatternTapped(finding))
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(BevelTheme.brand)
                                    .accessibilityIdentifier("trends-pattern-confirm-\(finding.id.uuidString)")

                                    Button("忽略") {
                                        store.send(.dismissPatternTapped(finding))
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("trends-pattern-dismiss-\(finding.id.uuidString)")
                                }
                            } else {
                                Text("已保存到 Coach 记忆")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(BSSpace.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-patterns-card")
    }

}

/// 实验室二级页：个人对照实验（前后对比，仅供参考）。
struct TrendsExperimentsLabView: View {
    @Bindable var store: StoreOf<TrendsFeature>

    var body: some View {
        BSPage("个人对照实验") {
            Text("选一个 14 天的小实验，用你自己的前后对比来判断有没有用。")
                .bsText(.caption)
        } sections: {
            nOfOneExperimentCard
        }
    }

    private var nOfOneExperimentCard: some View {
        let rows = store.evaluatedExperiments
        let adoptedTemplateIDs = Set(rows.filter { $0.planItem.state == .adopted }.map { $0.record.templateID })

        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Label("个人对照实验", systemImage: "flask")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text("前后对比 · 仅供参考")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                if let err = store.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !rows.isEmpty {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: BSSpace.xs) {
                            HStack {
                                Text(row.record.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                Text(row.planItem.state == .adopted ? "进行中" : "已结束")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, BSSpace.xs)
                                    .padding(.vertical, BSSpace.xxs)
                                    .background(BevelTheme.brandSoft, in: Capsule())
                                    .foregroundStyle(BevelTheme.brand)
                            }

                            ProgressView(
                                value: Double(min(row.evaluation.elapsedDays, row.evaluation.durationDays)),
                                total: Double(max(1, row.evaluation.durationDays))
                            )
                            .tint(BevelTheme.brand)

                            if let adherent = row.evaluation.adherentMean,
                               let nonAdherent = row.evaluation.nonAdherentMean {
                                experimentComparisonBars(
                                    adherentMean: adherent,
                                    nonAdherentMean: nonAdherent,
                                    unit: row.evaluation.targetUnit
                                )
                            }

                            Text(row.evaluation.summary)
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if row.planItem.state == .adopted {
                                HStack {
                                    Text("第 \(row.evaluation.elapsedDays)/\(row.evaluation.durationDays) 天 · \(row.record.targetMetric.title)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                    Spacer()
                                    Button("结束实验") {
                                        store.send(.completeExperimentTapped(row.planItem))
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("trends-nof1-complete-\(row.record.templateID)")
                                }
                            }
                        }
                        .padding(BSSpace.s)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
                    }
                }

                ForEach(NOfOneExperimentTemplate.presets) { template in
                    let isAdopted = adoptedTemplateIDs.contains(template.id)
                    HStack(alignment: .top, spacing: BSSpace.s) {
                        VStack(alignment: .leading, spacing: BSSpace.xxs) {
                            Text(template.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            Text(template.hypothesis)
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(isAdopted ? "进行中" : "开始 14 天实验") {
                            store.send(.startExperimentTapped(template))
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(BevelTheme.brand)
                        .disabled(isAdopted)
                        .accessibilityIdentifier("trends-nof1-start-\(template.id)")
                    }
                    .padding(BSSpace.s)
                    .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-nof1-card")
    }

    private func experimentComparisonBars(
        adherentMean: Double,
        nonAdherentMean: Double,
        unit: String
    ) -> some View {
        let maxRef = max(adherentMean, nonAdherentMean, 1.0)
        return VStack(spacing: BSSpace.xxs) {
            comparisonBarRow(label: "达标日", value: adherentMean, maxRef: maxRef, unit: unit, tint: BevelTheme.recoveryColor)
            comparisonBarRow(label: "未达标", value: nonAdherentMean, maxRef: maxRef, unit: unit, tint: BevelTheme.inkSecondary)
        }
    }

    private func comparisonBarRow(
        label: String,
        value: Double,
        maxRef: Double,
        unit: String,
        tint: Color
    ) -> some View {
        HStack(spacing: BSSpace.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
                .frame(width: BSSize.hitTarget, alignment: .leading)
            ProgressView(value: min(1.0, max(0.05, value / (maxRef * 1.08))))
                .tint(tint)
            Text(String(format: "%.1f %@", value, unit))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
        }
    }

}
