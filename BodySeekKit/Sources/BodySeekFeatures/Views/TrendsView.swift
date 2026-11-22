import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct TrendsView: View {
    @Bindable var store: StoreOf<TrendsFeature>
    private let zoomNamespace: Namespace.ID?

    public init(store: StoreOf<TrendsFeature>, zoomNamespace: Namespace.ID? = nil) {
        self.store = store
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        let activeSeries = store.activeSeries
        let horizonDays = Array(store.snapshot.historyDays.suffix(store.horizon.dayCount))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                horizonPills(selected: store.horizon)

                trendsAIInsightCard

                interactiveChartCard(series: activeSeries)

                personalForecastCard

                dualAxisCard(days: horizonDays)

                patternsCard

                nOfOneExperimentCard

                ForEach(store.allMetricSeries, id: \.kind) { series in
                    metricRowCard(series: series)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("趋势")
        .bodyseekNavigationBarInline()
        .sheet(isPresented: Binding(
            get: { store.showCoverageSheet },
            set: { store.send(.coverageSheetPresented($0)) }
        )) {
            coverageSheetView
        }
    }

    private func horizonPills(selected: TrendHorizon) -> some View {
        HStack(spacing: 8) {
            ForEach(TrendHorizon.allCases) { horizon in
                let isSelected = selected == horizon
                Button {
                    store.send(.horizonChanged(horizon))
                } label: {
                    Text(horizon.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? BevelTheme.brand : BevelTheme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .bodySeekLiquidPill(isSelected: isSelected, tint: BevelTheme.brand)
                }
                .id("\(horizon.rawValue)-\(isSelected)")
                .buttonStyle(.plain)
                .accessibilityIdentifier("trends-horizon-\(horizon.rawValue)")
            }
        }
        .padding(.vertical, 2)
    }

    private var trendsAIInsightCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("AI 趋势解读", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Button {
                        store.send(.refreshAIInsightTapped)
                    } label: {
                        HStack(spacing: 4) {
                            if case .loading = store.aiInsightStatus {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(aiRefreshLabel)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trends-ai-refresh-button")
                }

                switch store.aiInsightStatus {
                case let .generated(text, engine):
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("由 \(engine) 生成 · 基于\(store.horizon.title)\(store.selectedKind.title)与当前模型快照")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)

                case let .unconfigured(reason):
                    Text(store.deterministicTrendSummary)
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)

                case .idle, .loading:
                    Text(store.deterministicTrendSummary)
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        store.send(.coverageSheetPresented(true))
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                            Text("\(store.snapshot.sourceLabel) · 查看覆盖")
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trends-history-coverage")

                    Spacer()

                    Button {
                        store.send(.askCoachTapped("结合我\(store.horizon.title)\(store.selectedKind.title)趋势、明日预测与个人统计规律，给出解释和调整建议"))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            Text("问 Coach 深究")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trends-ask-coach-button")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-ai-insight-card")
    }

    private var aiRefreshLabel: String {
        switch store.aiInsightStatus {
        case .loading: "解读中"
        case .generated: "重新解读"
        case .idle, .unconfigured: "AI 深度解读"
        }
    }

    private func interactiveChartCard(series: TrendSeries) -> some View {
        let tint = BevelTheme.color(for: store.selectedKind)
        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(store.selectedKind.title)趋势", systemImage: store.selectedKind.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Button {
                        store.send(.openMetricDetail(store.selectedKind))
                    } label: {
                        HStack(spacing: 2) {
                            Text("详情")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MetricKind.allCases) { kind in
                            let selected = store.selectedKind == kind
                            let kindTint = BevelTheme.color(for: kind)
                            Button {
                                store.send(.kindSelected(kind))
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(kindTint)
                                        .frame(width: 7, height: 7)
                                    Text(kind.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selected ? BevelTheme.ink : BevelTheme.inkSecondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? kindTint.opacity(0.16) : BevelTheme.surfaceElevated,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TrendHorizonChart(
                    snapshot: store.activeChartSnapshot,
                    tint: tint,
                    onSelectDate: { date in
                        store.send(.selectedDateChanged(date))
                    },
                    onSelectBucket: { bucket in
                        store.send(.selectedDateChanged(bucket?.endDate))
                    }
                )
            }
        }
    }

    private var personalForecastCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("身体预测", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text("统计预测 · 非诊断")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
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
                            VStack(alignment: .leading, spacing: 2) {
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
                        .padding(10)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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

                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型预测特征贡献分解（非因果）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.inkSecondary)

                            FeatureAttributionChart(
                                drivers: target.drivers,
                                targetName: target.name,
                                height: 144
                            )
                        }
                        .padding(10)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    let secondaryTargets = summary.targets.filter { $0.name != selectedTarget?.name }
                    if !secondaryTargets.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(secondaryTargets) { item in
                                Button {
                                    store.send(.forecastTargetSelected(item.name))
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shortForecastTitle(for: item))
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                        Text(formattedPoint(for: item))
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                            .fontDesign(.rounded)
                                            .foregroundStyle(BevelTheme.ink)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(9)
                                    .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    DisclosureGroup("模型回测精度与技术依据") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("使用 \(summary.observedDays) 天因果特征。预测范围按 Split-Conformal 历史校准误差生成，仅作自我变化参考，不构成医疗诊断。")
                            ForEach(summary.targets) { target in
                                Text("\(forecastTitle(for: target)) · 回测 MAE \(formattedError(for: target)) · 80% 覆盖率 \(Int((target.walkForwardCov80 * 100).rounded()))%")
                            }
                            Text("模型 \(summary.modelVersion) · \(summary.runtimeBackend)")
                        }
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .padding(.top, 6)
                    }
                    .font(.subheadline)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-personal-forecast-card")
    }

    private func dualAxisCard(days: [DailyComputedDay]) -> some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("恢复与训练负荷对照")
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)

                LoadRecoveryComboChart(days: days) { date in
                    store.send(.selectedDateChanged(date))
                }
            }
        }
    }

    private var patternsCard: some View {
        let activeFindings = store.patternFindings.filter { $0.status != .dismissed }
        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
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
                        .padding(10)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    ForEach(activeFindings.prefix(4)) { finding in
                        let summary = finding.statement.components(separatedBy: "（95% CI ").first ?? finding.statement

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(finding.status == .confirmed ? "已确认" : "待确认")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        finding.status == .confirmed ? Color.green.opacity(0.16) : BevelTheme.brandSoft,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(finding.status == .confirmed ? Color.green : BevelTheme.brand)

                                if M4APersonalPatternSeeds.seedIDs.contains(finding.id) {
                                    Text("示例预置")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(BevelTheme.surfaceElevated, in: Capsule())
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                            }
                            Text(summary)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BevelTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("统计详情") {
                                VStack(alignment: .leading, spacing: 4) {
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
                                .padding(.top, 4)
                            }
                            .font(.subheadline)

                            if finding.status == .candidate {
                                HStack(spacing: 10) {
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
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-patterns-card")
    }

    private var nOfOneExperimentCard: some View {
        let rows = store.evaluatedExperiments
        let adoptedTemplateIDs = Set(rows.filter { $0.planItem.state == .adopted }.map { $0.record.templateID })

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.record.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                Text(row.planItem.state == .adopted ? "进行中" : "已结束")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
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
                        .padding(10)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                ForEach(NOfOneExperimentTemplate.presets) { template in
                    let isAdopted = adoptedTemplateIDs.contains(template.id)
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
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
                    .padding(10)
                    .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        return VStack(spacing: 4) {
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
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
                .frame(width: 42, alignment: .leading)
            ProgressView(value: min(1.0, max(0.05, value / (maxRef * 1.08))))
                .tint(tint)
            Text(String(format: "%.1f %@", value, unit))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
        }
    }

    @ViewBuilder
    private func metricRowCard(series: TrendSeries) -> some View {
        let tint = BevelTheme.color(for: series.kind)
        let current = store.snapshot.today.score(for: series.kind)
        let button = Button {
            store.send(.openMetricDetail(series.kind))
        } label: {
            BevelCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(series.kind.title, systemImage: series.kind.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint)
                        Spacer()
                        Text(current.formattedScore)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .foregroundStyle(BevelTheme.ink)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    MiniSparkline(
                        points: series.points.map { ($0.date, $0.value.map(Double.init)) },
                        tint: tint,
                        baselineRange: series.baselineRange,
                        height: 44
                    )

                    HStack {
                        Text(series.median.map { "基线中位 \($0)" } ?? "样本积累中")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Spacer()
                        Text("覆盖 \(series.coveredDays)/\(series.totalDays) 天")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trends-score-\(series.kind.rawValue)")

        if let zoomNamespace {
            button.bodyseekZoomSource(id: "trends-metric-\(series.kind.rawValue)", in: zoomNamespace)
        } else {
            button
        }
    }

    private var coverageSheetView: some View {
        NavigationStack {
            List {
                ForEach(store.allMetricSeries, id: \.kind) { item in
                    HStack {
                        Label(item.kind.title, systemImage: item.kind.systemImage)
                            .foregroundStyle(BevelTheme.color(for: item.kind))
                        Spacer()
                        Text("\(item.coveredDays)/\(item.totalDays) 天")
                            .monospacedDigit()
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }
            }
            .navigationTitle("历史数据覆盖度")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("关闭") {
                        store.send(.coverageSheetPresented(false))
                    }
                }
            }
        }
        .accessibilityIdentifier("trends-coverage-sheet")
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
