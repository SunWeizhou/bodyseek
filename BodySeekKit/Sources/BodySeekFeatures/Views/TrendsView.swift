import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct TrendsView: View {
    @Bindable var store: StoreOf<TrendsFeature>
    @State private var showsExploration = false
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

                interactiveChartCard(series: activeSeries)

                summaryCard(series: activeSeries)

                DisclosureGroup(isExpanded: $showsExploration) {
                    VStack(alignment: .leading, spacing: 12) {
                        personalForecastCard
                        dualAxisCard(days: horizonDays)
                        nOfOneExperimentCard
                        patternsCard
                    }
                    .padding(.top, 12)
                } label: {
                    Text("预测、对照与规律")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                        .accessibilityIdentifier("trends-exploration")
                }
                .padding(.horizontal, 4)

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

    private func summaryCard(series: TrendSeries) -> some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(series.statusSummary)
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    store.send(.coverageSheetPresented(true))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("\(store.snapshot.sourceLabel) · 查看覆盖")
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

                // 统一的分周期胶囊图：7 天按日、30 天/6 个月按周、3 年按月。
                TrendHorizonChart(
                    snapshot: store.activeChartSnapshot,
                    tint: tint,
                    onSelectBucket: { bucket in
                        store.send(.selectedDateChanged(bucket?.endDate))
                    }
                )
            }
        }
    }

    private func dualAxisCard(days: [DailyComputedDay]) -> some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("恢复与训练负荷")
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)

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
                    Text("数据还不够。已记录 \(observedDays) 个有效日，至少需要 \(minimumRequired) 天。")
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.inkSecondary)

                case let .available(summary):
                    Text("\(summary.targetDayKey.month) 月 \(summary.targetDayKey.day) 日预测")
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.inkSecondary)

                    ForEach(summary.targets) { target in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(forecastTitle(for: target))
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

                    DisclosureGroup("预测依据") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("使用 \(summary.observedDays) 天有效记录。预测范围按历史误差校准，供比较波动参考。")
                            ForEach(summary.targets) { target in
                                Text("\(forecastTitle(for: target)) · 回测平均误差 \(formattedError(for: target))")
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

    private func forecastTitle(for target: PersonalForecastTargetResult) -> String {
        switch target.name {
        case "hrv_sdnn_ms": "夜间心率变异性"
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
                    Text("还没有足够的历史记录来显示规律。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(activeFindings.prefix(4)) { finding in
                        let summary = finding.statement.components(separatedBy: "（95% CI ").first ?? finding.statement

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
