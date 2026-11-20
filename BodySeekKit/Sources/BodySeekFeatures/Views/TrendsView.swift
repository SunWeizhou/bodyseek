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

                summaryCard(series: activeSeries)

                interactiveChartCard(series: activeSeries)

                personalForecastCard

                dualAxisCard(days: horizonDays)

                nOfOneExperimentCard

                patternsCard

                ForEach(store.allMetricSeries, id: \.kind) { series in
                    metricRowCard(series: series)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("趋势")
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

    private func summaryCard(series: TrendSeries) -> some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(store.horizon.title)小结")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Spacer()
                    Text(store.snapshot.sourceLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                Text(series.statusSummary)
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    store.send(.coverageSheetPresented(true))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("图中 \(series.coveredDays)/\(series.totalDays) 天有评分")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BevelTheme.inkSecondary)
                }
                .accessibilityIdentifier("trends-history-coverage")
            }
        }
    }

    private func interactiveChartCard(series: TrendSeries) -> some View {
        let tint = BevelTheme.color(for: store.selectedKind)
        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(store.selectedKind.title)交互趋势", systemImage: store.selectedKind.systemImage)
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

                if store.horizon.usesRangeCapsules {
                    RangeCapsuleChart(
                        snapshot: store.activeChartSnapshot,
                        tint: tint
                    ) { bucket in
                        store.send(.selectedDateChanged(bucket?.endDate))
                    }
                } else {
                    TrendLineChart(
                        snapshot: store.activeChartSnapshot,
                        tint: tint
                    ) { date in
                        store.send(.selectedDateChanged(date))
                    }
                }
            }
        }
    }

    private func dualAxisCard(days: [DailyComputedDay]) -> some View {
        let load = store.snapshot.trainingLoad
        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("恢复 × 负荷演化对照")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                        Text("对比近期训练负荷节奏与恢复储备变化，拖拽可查看每日双值")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    Spacer()
                    Text(load.acwrRatio.map { String(format: "ACWR %.2f", $0) } ?? "ACWR --")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                }

                LoadRecoveryComboChart(days: days) { date in
                    store.send(.selectedDateChanged(date))
                }
            }
        }
    }

    private var personalForecastCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("明天身体预测", systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text("个人统计预测 · 非医学诊断")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                }

                switch store.personalForecast {
                case let .insufficientData(observedDays, minimumRequired, reason):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("当前有效样本 \(observedDays)/\(minimumRequired) 天（绝不零填充补齐）")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BevelTheme.inkSecondary)

                case let .available(summary):
                    HStack {
                        Text("目标日 \(summary.targetDayKey.isoString)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Spacer()
                        Text(summary.modelVersion)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    ForEach(summary.targets) { target in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Text(formattedInterval(for: target))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer()
                            Text(formattedPoint(for: target))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.ink)
                        }
                        .padding(10)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Text("运行时：\(summary.runtimeBackend) · 基于 \(summary.observedDays) 天严格因果特征与 80% Split-Conformal 校准区间。")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-personal-forecast-card")
    }

    private func formattedPoint(for target: PersonalForecastTargetResult) -> String {
        if target.name == "sleep_efficiency" {
            return String(format: "%.1f%%", target.point * 100.0)
        }
        return String(format: "%.1f %@", target.point, target.unit)
    }

    private func formattedInterval(for target: PersonalForecastTargetResult) -> String {
        if target.name == "sleep_efficiency" {
            return String(
                format: "80%% 预测区间 [%.1f%%, %.1f%%] · 历史回测 MAE %.1f%%",
                target.interval80Low * 100.0,
                target.interval80High * 100.0,
                target.walkForwardMAE * 100.0
            )
        }
        return String(
            format: "80%% 预测区间 [%.1f, %.1f] %@ · 历史回测 MAE %.2f",
            target.interval80Low,
            target.interval80High,
            target.unit,
            target.walkForwardMAE
        )
    }

    private var nOfOneExperimentCard: some View {
        let rows = store.evaluatedExperiments
        let adoptedTemplateIDs = Set(rows.filter { $0.planItem.state == .adopted }.map { $0.record.templateID })

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("N-of-1 自我对照实验", systemImage: "flask")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text("个人对比 · 非临床因果结论")
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
                        VStack(alignment: .leading, spacing: 6) {
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
                            Text(row.evaluation.summary)
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if row.planItem.state == .adopted {
                                HStack {
                                    Text("起始 \(row.record.startDayKey.isoString) · \(row.record.targetMetric.title)")
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

    private var patternsCard: some View {
        let activeFindings = store.patternFindings.filter { $0.status != .dismissed }
        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
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
                    Text("待导入 3 年历史导出报告或持续积累 ≥ 40 天样本后，将在此发布带置信区间（95% CI）与样本量的分布滞后规律。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(activeFindings.prefix(4)) { finding in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(finding.status == .confirmed ? "已确认" : "待确认")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        finding.status == .confirmed ? Color.green.opacity(0.16) : BevelTheme.brandSoft,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(finding.status == .confirmed ? Color.green : BevelTheme.brand)
                                Spacer()
                                Text("n=\(finding.sampleSize)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Text(finding.statement)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BevelTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(String(
                                format: "效应 %.2f · 95%% CI [%.2f, %.2f] · %@",
                                finding.effect,
                                finding.ciLow,
                                finding.ciHigh,
                                finding.method
                            ))
                            .font(.caption2.monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(BevelTheme.deviationInk)

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
                                Text("已晋升为 Verified Pattern 长期记忆")
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
}
