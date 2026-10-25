import SwiftUI
import BodySeekDomain

private struct ScoreTrendDescriptor: Identifiable {
    let metric: CoreHealthMetric
    let detail: VelaMetricDetailView.MetricType
    let title: String
    let icon: String

    var id: String { metric.rawValue }
}

/// Compatibility adapter for the first host migration. It snapshots the
/// already-loaded summary records into value-only inputs for TrendsStore;
/// persistence and the existing dashboard formulas remain unchanged.
private struct SummaryTrendsHistoryProvider: TrendsHistoryProviding {
    let snapshots: [DailyHealthSnapshot]
    let findings: [HealthTrendFinding]
    var isPreview = false

    func history(
        metric: CoreHealthMetric,
        horizon: HealthTrendHorizon,
        endingAt selectedDay: Date,
        calendar: Calendar
    ) async throws -> TrendsHistoryPayload {
        TrendsHistoryPayload(
            snapshots: snapshots,
            finding: findings.first {
                $0.metric == metric && $0.horizon == horizon
            },
            baselineBand: usualRange(metric: metric, snapshots: snapshots, horizon: horizon, endingAt: selectedDay, calendar: calendar),
            provenanceByDay: isPreview ? Dictionary(uniqueKeysWithValues: snapshots.map {
                (calendar.startOfDay(for: $0.date), TrendsPointProvenance(source: .derived, sourceLabel: "示例数据", detail: "仅用于界面预览"))
            }) : [:]
        )
    }

    /// Usual personal range is the baseline median ± one robust scale.
    /// A flat history has no scale, so the band stays absent instead of a made-up width.
    private func usualRange(
        metric: CoreHealthMetric,
        snapshots: [DailyHealthSnapshot],
        horizon: HealthTrendHorizon,
        endingAt selectedDay: Date,
        calendar: Calendar
    ) -> ClosedRange<Double>? {
        let samples = snapshots.compactMap { snapshot -> BaselineSample? in
            guard let value = scoreValue(metric, snapshot: snapshot) else { return nil }
            return BaselineSample(date: snapshot.date, value: value)
        }
        guard let estimate = BaselineEstimator.estimate(
            samples: samples,
            asOf: selectedDay,
            windowDays: horizon.windowDays,
            minimumSamples: horizon.requiredSampleCount,
            calendar: calendar
        ), let scale = estimate.robustScale, scale > 0 else {
            return nil
        }
        let half = scale * BaselineEstimator.stableZ
        return (estimate.median - half)...(estimate.median + half)
    }

    private func scoreValue(_ metric: CoreHealthMetric, snapshot: DailyHealthSnapshot) -> Double? {
        switch metric {
        case .sleepScore: return snapshot.sleepScore
        case .recovery: return snapshot.recoveryScore
        case .strain: return snapshot.strainScore
        case .stress: return snapshot.stressIndex
        case .energy: return snapshot.currentEnergy ?? snapshot.energyBank
        default: return nil
        }
    }
}

// MARK: - VelaTrendsView — five scored time series first, raw vitals second

struct VelaTrendsView: View {
    let selectedDate: Date
    let dashboard: DashboardSummary
    let localDataRevision: Int
    let loader: PersistedTrendsWindowLoader
    let onAskCoach: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedHorizon: HealthTrendHorizon = .thirtyDays
    @State private var selectedMetricForDetail: VelaMetricDetailView.MetricType?
    @State private var showAllMetricCatalog = false
    @State private var dailyRecordsLoadError: String?
    @State private var trendStates: [CoreHealthMetric: TrendsViewState] = [:]
    @State private var trendRetryNonce = 0
    @State private var selectedRecoveryTrendDate: Date?
    @State private var showHistoryCoverage = false
    @State private var rawCoverage: HistoricalCoverageSummary?
    @State private var loadedWindowID: String?

    private var healthBrief: PersonalHealthBrief? { dashboard.personalHealthBrief }
    private var allTrends: [HealthTrendFinding] { dashboard.healthTrends }

    private var horizonFindings: [HealthTrendFinding] {
        allTrends.filter { $0.horizon == selectedHorizon }
    }

    private var availableFindings: [HealthTrendFinding] {
        horizonFindings.filter { $0.isAvailable }
    }

    private var horizonNotableShifts: [HealthTrendFinding] {
        availableFindings.filter { $0.isNotable }
    }

    private var scoreDescriptors: [ScoreTrendDescriptor] {
        [
            .init(metric: .recovery, detail: .recovery, title: "恢复", icon: "heart.circle.fill"),
            .init(metric: .sleepScore, detail: .sleep, title: "睡眠", icon: "moon.stars.fill"),
            .init(metric: .strain, detail: .strain, title: "负荷", icon: "figure.run"),
            .init(metric: .stress, detail: .stress, title: "压力", icon: "waveform.path.ecg"),
            .init(metric: .energy, detail: .energy, title: "能量", icon: "bolt.fill")
        ]
    }

    private var hasAnyScoreHistory: Bool {
        scoreDescriptors.contains { descriptor in
            scoreHistory(for: descriptor.metric).count >= 2
        }
    }

    /// One row leads the section: a notable shift first, then any available
    /// finding, then the first descriptor. Copy and scoring are untouched;
    /// this only decides where the visual weight goes.
    private var focusMetric: CoreHealthMetric? {
        let metrics = scoreDescriptors.map(\.metric)
        if let notable = metrics.first(where: { finding(for: $0)?.isNotable == true }) {
            return notable
        }
        if let available = metrics.first(where: { finding(for: $0)?.isAvailable == true }) {
            return available
        }
        return metrics.first
    }

    var body: some View {
        ScrollView {
            // Five fixed overview cards do not need lazy height estimation.
            // Keep their layout stable while scrolling and switching windows.
            VStack(alignment: .leading, spacing: VelaTheme.sectionGap) {
                trendHistoryErrorCard
                compactAgentObservation
                fiveScoreTrendSection
                trendLegend

                if !hasAnyScoreHistory && scoreDescriptors.allSatisfy({ finding(for: $0.metric)?.isAvailable != true }) {
                    compactCalibrationCard
                }

                metricCatalogDisclosure
                    .padding(.top, 8)
                if showAllMetricCatalog {
                    groupedMetricBrowserSection
                    recoveryTrendChart
                    if selectedHorizon != .threeYears {
                        threeYearTrajectoryCard
                    }
                    if healthBrief?.subheadline.isEmpty != false {
                        askVelaTrendCard
                    }
                }
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, VelaTheme.space4)
            .padding(.bottom, VelaFloatingNavigationMetrics.contentBottomPadding + 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("trends-content")
        .background(VelaTheme.rhythmCanvas)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: trendLoadID) {
            await loadTrends()
        }
        .onAppear { VelaAppState.shared.visibleTrendHorizon = selectedHorizon }
        .onChange(of: selectedHorizon) { _, horizon in
            VelaAppState.shared.visibleTrendHorizon = horizon
        }
        .sheet(item: $selectedMetricForDetail) { metric in
            NavigationStack {
                VelaMetricDetailView(
                    metric: metric,
                    selectedDate: selectedDate,
                    dashboardSnapshot: dashboard,
                    isPresentedInSheet: true
                )
            }
            .presentationDetents([.large])
            .velaSheetSurface()
        }
    }

    // MARK: - Five scored time series

    private var fiveScoreTrendSection: some View {
        let focus = focusMetric
        let others = scoreDescriptors.filter { $0.metric != focus }
        return VStack(spacing: VelaTheme.cardGap) {
            if let focusDescriptor = scoreDescriptors.first(where: { $0.metric == focus }) {
                scoreTrendRow(focusDescriptor, isFocus: true)
            }
            ForEach(others) { descriptor in
                scoreTrendRow(descriptor, isFocus: false)
            }
        }
    }

    /// First host migration slice: the existing recovery path now renders the
    /// Store-owned series while the legacy rows remain unchanged.
    @ViewBuilder
    private var recoveryTrendChart: some View {
        if let recoveryState = trendStates[.recovery],
           let series = recoveryState.series,
           recoveryState.phase == .ready {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("恢复趋势")
                        .font(VelaTheme.callout().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    Text(dashboard.source == .preview ? "示例曲线 · 缺失日期保留空档" : "缺失日期保留空档")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }

                TrendsOneMetricChart(
                    series: series,
                    selectedDate: $selectedRecoveryTrendDate,
                    tint: VelaTheme.rhythmInk
                )
                .accessibilityIdentifier("trends-recovery-store-chart")
            }
            .padding(14)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            }
        }
    }

    private func scoreTrendRow(_ descriptor: ScoreTrendDescriptor, isFocus: Bool) -> some View {
        let finding = finding(for: descriptor.metric)
        let trendPoints = scoreTrendPoints(for: descriptor.metric)
        let values = trendPoints.compactMap(\.value)
        let valueText = scoreValueText(descriptor: descriptor, finding: finding, values: values)
        let series = currentSeries(for: descriptor.metric)

        return Button {
            selectedMetricForDetail = descriptor.detail
        } label: {
            if isFocus {
                focusTrendRowContent(
                    descriptor: descriptor,
                    finding: finding,
                    valueText: valueText,
                    series: series,
                    sampleCount: values.count
                )
            } else {
                compactTrendRowContent(
                    descriptor: descriptor,
                    finding: finding,
                    valueText: valueText,
                    series: series,
                    sampleCount: values.count
                )
            }
        }
        .buttonStyle(.cardPress)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("trends-score-\(descriptor.metric.rawValue)")
        .accessibilityLabel(scoreAccessibilityLabel(descriptor: descriptor, finding: finding, values: values))
        .accessibilityHint("打开\(descriptor.title)详情")
    }

    /// The one row with visual weight: larger numeral, taller chart, one caption line.
    private func focusTrendRowContent(
        descriptor: ScoreTrendDescriptor,
        finding: HealthTrendFinding?,
        valueText: String,
        series: TrendsMetricSeries?,
        sampleCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(descriptor.title)
                            .font(VelaTheme.callout().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        if finding?.isNotable == true {
                            BaselineDeviationMarker(
                                directionLabel: finding.flatMap { BaselineDeviationCopy.label(for: $0) },
                                showsLabel: false,
                                diameter: 7
                            )
                        }
                    }
                    Text(scoreTrendCaption(finding: finding, sampleCount: sampleCount))
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 4) {
                    Text(valueText)
                        .font(VelaTheme.heroValue())
                        .foregroundStyle(valueText == "--" ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .layoutPriority(1)
            }
            trendSparkline(series: series, descriptor: descriptor, height: 44)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, VelaTheme.compactCardPadding)
        .padding(.vertical, VelaTheme.space3)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .trendMetricCardSurface()
        .contentShape(Rectangle())
    }

    /// Dense rows: one short line, a 24pt chart, and a supporting-size numeral.
    private func compactTrendRowContent(
        descriptor: ScoreTrendDescriptor,
        finding: HealthTrendFinding?,
        valueText: String,
        series: TrendsMetricSeries?,
        sampleCount: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(descriptor.title)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    if finding?.isNotable == true {
                        BaselineDeviationMarker(
                            directionLabel: finding.flatMap { BaselineDeviationCopy.label(for: $0) },
                            showsLabel: false,
                            diameter: 6
                        )
                    }
                }
                Text(compactTrendCaption(finding: finding, sampleCount: sampleCount))
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 84, alignment: .leading)

            trendSparkline(series: series, descriptor: descriptor, height: 24)
                .frame(maxWidth: .infinity)

            Text(valueText)
                .font(VelaTheme.callout().weight(.semibold).monospacedDigit())
                .foregroundStyle(valueText == "--" ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                .frame(minWidth: 32, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(.horizontal, VelaTheme.space3)
        .padding(.vertical, VelaTheme.space2)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .trendMetricCardSurface()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func trendSparkline(
        series: TrendsMetricSeries?,
        descriptor: ScoreTrendDescriptor,
        height: CGFloat
    ) -> some View {
        if let series {
            VStack(spacing: 3) {
                GeometryReader { geo in
                    DateAwareSparkline(
                        points: series.points,
                        color: VelaTheme.rhythmInk,
                        height: geo.size.height,
                        width: geo.size.width,
                        band: series.baselineBand,
                        marksLatestPoint: true
                    )
                }
                .frame(height: height)
                .accessibilityIdentifier("trends-overview-chart-\(descriptor.metric.rawValue)")
                HStack {
                    if let first = series.points.first, let last = series.points.last {
                        Text(first.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                        Spacer(minLength: 0)
                        Text(last.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                    }
                }
                .font(VelaTheme.caption2().monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .accessibilityHidden(true)
            }

        } else {
            Text(dailyRecordsLoadError == nil ? "正在读取记录…" : "暂无可用记录")
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
    }

    private var compactCalibrationCard: some View {
        NavigationLink(destination: HistoricalBackfillView()) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("同步或回填健康数据，建立个人趋势")
                    .font(VelaTheme.footnote().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(14)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        }
        .buttonStyle(.cardPress)
    }

    @ViewBuilder
    private var compactAgentObservation: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(HealthTrendHorizon.allCases) { horizon in
                        let selected = horizon == selectedHorizon
                        Button {
                            selectedHorizon = horizon
                            VelaHaptic.selection()
                        } label: {
                            Text(horizon.title)
                            .font(VelaTheme.subheadline().weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(Capsule().fill(selected ? VelaTheme.segmentOn : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trends-horizon-\(horizon.rawValue)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trends-horizon-picker")
            .accessibilityLabel("趋势时间范围")

            periodSummary
        }
        .sheet(isPresented: $showHistoryCoverage) {
            TrendsHistoryCoverageSheet(
                horizon: selectedHorizon,
                rows: coverageRows,
                isPreview: dashboard.source == .preview,
                rawCoverage: loadedWindowID == trendLoadID ? rawCoverage : nil
            )
            .presentationDetents([.medium, .large])
            .velaSheetSurface()
        }
    }

    private var coverageRows: [TrendsCoverageRow] {
        scoreDescriptors.map { descriptor in
            let points = scoreTrendPoints(for: descriptor.metric)
            return TrendsCoverageRow(
                id: descriptor.metric.rawValue,
                title: descriptor.title,
                scoredDays: points.filter { $0.value != nil }.count,
                windowDays: points.isEmpty ? selectedHorizon.windowDays : points.count,
                requiredDays: selectedHorizon.requiredSampleCount,
                isLoaded: currentSeries(for: descriptor.metric) != nil,
                baselineDays: finding(for: descriptor.metric)?.sampleCount
            )
        }
    }

    private var periodSummary: some View {
        let summary = TrendsPeriodSummary.make(
            horizon: selectedHorizon,
            findings: scoreDescriptors.compactMap { finding(for: $0.metric) }
        )
        let rows = coverageRows
        let loaded = rows.filter(\.isLoaded)
        let hasAvailableSignal = !availableFindings.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 8))) {
                    Text("\(selectedHorizon.title)小结")
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if dashboard.source == .preview {
                        Text("示例数据")
                            .font(VelaTheme.caption2().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(Capsule().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                    }
                }
                // A compact judgment line: the empty case must not own the fold.
                Text(summary.headline)
                    .font(hasAvailableSignal ? VelaTheme.statement() : VelaTheme.title3())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = summary.detail {
                    // One line only; the coverage sheet carries the full context.
                    Text(detail)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trends-period-summary")

            Button {
                showHistoryCoverage = true
                VelaHaptic.selection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(TrendsCoverageRow.summaryText(loaded, horizon: selectedHorizon))
                        .font(VelaTheme.caption1().weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trends-history-coverage")
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trendLegend: some View {
        Text(trendLegendText)
            .font(VelaTheme.caption2())
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("阴影为个人常见范围；空心圆不等于不好，只表示偏离你的平时；空档日期暂无评分")
    }

    /// One compact legend line replaces the three stacked gray captions.
    private var trendLegendText: String {
        var parts: [String] = []
        if scoreDescriptors.contains(where: { scoreBand(for: $0.metric) != nil }) {
            parts.append("阴影为常见范围")
        }
        parts.append("空心圆=偏离平时")
        parts.append("空档=暂无评分")
        return parts.joined(separator: " · ")
    }

    private var metricCatalogDisclosure: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.24)) {
                showAllMetricCatalog.toggle()
            }
            VelaHaptic.selection()
        } label: {
            HStack {
                Text("更多健康指标")
                    .font(VelaTheme.callout().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Image(systemName: showAllMetricCatalog ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showAllMetricCatalog ? "已展开" : "已收起")
    }

    private func finding(for metric: CoreHealthMetric) -> HealthTrendFinding? {
        allTrends.first { $0.metric == metric && $0.horizon == selectedHorizon }
    }

    private func currentSeries(for metric: CoreHealthMetric) -> TrendsMetricSeries? {
        guard loadedWindowID == trendLoadID,
              let series = trendStates[metric]?.series,
              series.horizon == selectedHorizon else { return nil }
        return series
    }

    private func scoreTrendPoints(for metric: CoreHealthMetric) -> [TrendsChartPoint] {
        currentSeries(for: metric)?.points ?? []
    }

    private func scoreBand(for metric: CoreHealthMetric) -> ClosedRange<Double>? {
        trendStates[metric]?.series?.baselineBand
    }

    private func scoreHistory(for metric: CoreHealthMetric) -> [Double] {
        trendStates[metric]?.series?.points.compactMap(\.value) ?? []
    }

    private func scoreValueText(
        descriptor: ScoreTrendDescriptor,
        finding: HealthTrendFinding?,
        values: [Double]
    ) -> String {
        let value = finding?.isAvailable == true
            ? finding?.currentValue
            : currentScoreValue(for: descriptor.metric)
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }

    private func scoreTrendCaption(finding: HealthTrendFinding?, sampleCount: Int) -> String {
        guard let finding, finding.isAvailable else {
            if sampleCount >= selectedHorizon.requiredSampleCount {
                return "图中 \(sampleCount) 个评分日（含当天）"
            }
            return "图中 \(sampleCount) 个评分日（含当天） · 基线历史 \(finding?.sampleCount ?? 0)/\(selectedHorizon.requiredSampleCount) 天"
        }
        if finding.isNotable {
            return BaselineDeviationCopy.label(for: finding) ?? BaselineDeviationCopy.unusualFallback
        }
        if let baseline = finding.baselineValue {
            return "基线 \(Int(baseline.rounded())) · \(finding.valueDirection.label)"
        }
        return "\(finding.sampleCount) 天 · \(finding.valueDirection.label)"
    }

    /// Compact rows keep one short line. The full phrasing survives in
    /// `scoreTrendCaption` for VoiceOver and for the detail sheet.
    private func compactTrendCaption(finding: HealthTrendFinding?, sampleCount: Int) -> String {
        guard let finding, finding.isAvailable else {
            return sampleCount > 0 ? "\(sampleCount) 个评分日" : "等待历史"
        }
        if finding.isNotable {
            return BaselineDeviationCopy.label(for: finding) ?? BaselineDeviationCopy.unusualFallback
        }
        if let baseline = finding.baselineValue {
            return "基线 \(Int(baseline.rounded())) · \(finding.valueDirection.label)"
        }
        return "\(finding.sampleCount) 天 · \(finding.valueDirection.label)"
    }

    private func scoreAccessibilityLabel(
        descriptor: ScoreTrendDescriptor,
        finding: HealthTrendFinding?,
        values: [Double]
    ) -> String {
        let value = scoreValueText(descriptor: descriptor, finding: finding, values: values)
        let state = scoreTrendCaption(finding: finding, sampleCount: values.count)
        return "\(descriptor.title)，\(value)，\(state)"
    }

    private func currentScoreValue(for metric: CoreHealthMetric) -> Double? {
        switch metric {
        case .recovery: return dashboard.recovery.hasData ? dashboard.recovery.value : nil
        case .sleepScore: return dashboard.sleepScore.hasData ? dashboard.sleepScore.value : nil
        case .strain: return dashboard.strain.hasData ? dashboard.strain.value : nil
        case .stress: return dashboard.stress.hasData ? dashboard.stress.value : nil
        case .energy: return dashboard.energy.hasData ? dashboard.energy.value : nil
        default: return nil
        }
    }

    private var trendLoadID: String {
        "\(selectedHorizon.rawValue)|\(selectedDate.timeIntervalSinceReferenceDate)|\(localDataRevision)|\(trendRetryNonce)"
    }

    /// Lets the horizon control paint before the history read. Cancelling the
    /// task keeps the visible series until a newer load finishes.
    private func loadTrends() async {
        let horizon = selectedHorizon
        let selectedDate = selectedDate
        let findings = allTrends
        await Task.yield()
        guard !Task.isCancelled else { return }
        let loaded = loader.load(horizon: horizon, endingAt: selectedDate)
        guard !Task.isCancelled else { return }
        let provider = SummaryTrendsHistoryProvider(
            snapshots: loaded.snapshots,
            findings: findings,
            isPreview: loaded.isPreview
        )
        var states: [CoreHealthMetric: TrendsViewState] = [:]
        for metric in scoreDescriptors.map(\.metric) {
            guard !Task.isCancelled else { return }
            let store = TrendsStore(
                provider: provider,
                selectedDay: selectedDate,
                horizon: horizon,
                metric: metric
            )
            await store.send(.appear)
            states[metric] = store.state
        }
        guard !Task.isCancelled else { return }
        loadedWindowID = trendLoadID
        rawCoverage = loaded.rawCoverage
        dailyRecordsLoadError = loaded.errorMessage
        trendStates = states
    }

    // MARK: - Empty State View

    @ViewBuilder
    private var trendHistoryErrorCard: some View {
        if let dailyRecordsLoadError {
            VelaStateCard(
                state: .error,
                title: "趋势历史暂时无法读取",
                message: dailyRecordsLoadError,
                actionTitle: "重试",
                action: { trendRetryNonce += 1 }
            )
            .accessibilityIdentifier("trends-history-error")
        }
    }

    private var emptyHorizonStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VelaTheme.rhythmDeep.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "waveform.path.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("\(selectedHorizon.detailedTitle) 数据积累中")
                    .font(VelaTheme.headline().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)

                Text("当前周期需要至少 \(selectedHorizon.requiredSampleCount) 天有效记录。继续佩戴 Apple Watch 记录，或在设置中回填历史健康数据。")
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            NavigationLink(destination: HistoricalBackfillView()) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(VelaTheme.footnote().weight(.semibold))
                    Text("前往回填三年 Apple 健康数据")
                        .font(VelaTheme.footnote().weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(VelaTheme.rhythmDeepOn)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(VelaTheme.rhythmDeep))
            }
            .buttonStyle(.cardPress)
            .padding(.bottom, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
        .accessibilityIdentifier("trends-empty-state")
    }

    // MARK: - Tier 2: System Narrative Section

    private var systemNarrativeSection: some View {
        Group {
            if let brief = healthBrief, !brief.possibleDrivers.isEmpty || !brief.subheadline.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        Text("系统关联观察")
                            .font(VelaTheme.footnote().weight(.bold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        Spacer()
                    }

                    Text(brief.subheadline)
                        .font(VelaTheme.body().weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !brief.possibleDrivers.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(brief.possibleDrivers, id: \.self) { driver in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(VelaTheme.rhythmDeep.opacity(0.7))
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 6)
                                    Text(driver)
                                        .font(VelaTheme.footnote())
                                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                )
            }
        }
    }

    // MARK: - Tier 3: Grouped Metric Browser

    private var groupedMetricBrowserSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("生理系统指标浏览")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)

            // 1. 心血管与节律
            metricGroup(
                title: "心血管与自主节律",
                metrics: [
                    (.hrv, .hrv),
                    (.restingHeartRate, .rhr),
                    (.respiratoryRate, .respiratoryRate),
                    (.oxygenSaturation, .bloodOxygen)
                ]
            )

            // 2. 睡眠与恢复
            metricGroup(
                title: "睡眠与恢复",
                metrics: [
                    (.sleepDuration, .sleep),
                    (.recovery, .recovery),
                    (.energy, .energy)
                ]
            )

            // 3. 日常负荷与活动
            metricGroup(
                title: "日常负荷与活动",
                metrics: [
                    (.strain, .strain),
                    (.stress, .stress),
                    (.steps, .steps),
                    (.activeCalories, .activeCalories)
                ]
            )

            // 4. 身体组成
            metricGroup(
                title: "身体组成",
                metrics: [
                    (.bodyWeight, .weight),
                    (.bodyFat, .bodyFat)
                ]
            )
        }
    }

    private func metricGroup(
        title: String,
        metrics: [(CoreHealthMetric, VelaMetricDetailView.MetricType)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(VelaTheme.footnote().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, pair in
                    browserRow(for: pair.0, metricType: pair.1)
                    if index < metrics.count - 1 {
                        Divider()
                            .overlay(VelaTheme.rhythmMist)
                            .padding(.leading, 48)
                    }
                }
            }
            .velaNativeCard(radius: VelaTheme.radiusLg)
        }
    }

    private func browserRow(for metric: CoreHealthMetric, metricType: VelaMetricDetailView.MetricType) -> some View {
        let finding = allTrends.first { $0.metric == metric && $0.horizon == selectedHorizon }

        return Button {
            selectedMetricForDetail = metricType
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            browserMetricIcon(metric)
                            Text(metric.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }

                        Text(finding?.isAvailable == true
                             ? (finding?.summary ?? "")
                             : "需至少 \(selectedHorizon.requiredSampleCount) 天，当前 \(finding?.sampleCount ?? 0) 天")
                            .font(VelaTheme.footnote())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(finding?.isAvailable == true ? (finding?.currentValueFormatted ?? "--") : "--")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(finding?.isAvailable == true ? VelaTheme.rhythmInk : VelaTheme.muted)
                            if let finding, finding.isAvailable {
                                Image(systemName: finding.valueDirection.icon)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(assessmentColor(for: finding.assessment))
                                    .accessibilityLabel(finding.assessment.label)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        browserMetricIcon(metric)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(finding?.isAvailable == true
                                 ? (finding?.summary ?? "")
                                 : "需至少 \(selectedHorizon.requiredSampleCount) 天，当前 \(finding?.sampleCount ?? 0) 天")
                                .font(VelaTheme.footnote())
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(finding?.isAvailable == true ? (finding?.currentValueFormatted ?? "--") : "--")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(finding?.isAvailable == true ? VelaTheme.rhythmInk : VelaTheme.muted)
                            if let finding, finding.isAvailable {
                                Image(systemName: finding.valueDirection.icon)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(assessmentColor(for: finding.assessment))
                                    .accessibilityLabel(finding.assessment.label)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开指标详情")
    }

    private func browserMetricIcon(_ metric: CoreHealthMetric) -> some View {
        Image(systemName: metric.icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(accentColor(for: metric))
            .frame(width: 32, height: 32)
            .background(VelaTheme.rhythmMist.opacity(0.72), in: Circle())
    }

    // MARK: - Three-Year Trajectory Card

    private var threeYearTrajectoryCard: some View {
        NavigationLink(destination: LongTermHealthTrendView()) {
            HStack(spacing: 14) {
                Image(systemName: "chart.xyaxis.line")
                    .font(VelaTheme.title3().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                            .fill(VelaTheme.rhythmMist.opacity(0.8))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("三年健康轨迹与基线")
                        .font(VelaTheme.callout().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("查看长期月均演变与同比分析")
                        .font(VelaTheme.footnote())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ask Vela Trend Card

    private var askVelaTrendCard: some View {
        Button {
            onAskCoach(selectedHorizonCoachQuestion)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(VelaTheme.body().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)

                VStack(alignment: .leading, spacing: 2) {
                    Text("向 Vela 深入分析\(selectedHorizon.detailedTitle)变化")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("探讨心率、睡眠与压力之间的可能联系")
                        .font(VelaTheme.footnote())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .fill(VelaTheme.rhythmMist.opacity(0.45))
            )
        }
        .buttonStyle(.cardPress)
        .accessibilityHint("打开 Vela，并带入当前趋势范围与显著变化")
    }

    private var selectedHorizonCoachQuestion: String {
        let notable = horizonNotableShifts.prefix(3).map {
            "\($0.metric.title)：\($0.summary)"
        }
        let evidence = notable.isEmpty
            ? "本周期没有达到显著阈值的变化。"
            : "当前显著变化：" + notable.joined(separator: "；")
        return "请综合分析我\(selectedHorizon.detailedTitle)的身体体征变化，解释值得关注的关联，并给出一个最优先行动。\(evidence)"
    }

    private func detailMetric(for metric: CoreHealthMetric) -> VelaMetricDetailView.MetricType {
        switch metric {
        case .hrv: return .hrv
        case .restingHeartRate: return .rhr
        case .sleepDuration, .sleepScore: return .sleep
        case .recovery: return .recovery
        case .strain: return .strain
        case .stress: return .stress
        case .energy: return .energy
        case .respiratoryRate: return .respiratoryRate
        case .oxygenSaturation: return .bloodOxygen
        case .bodyWeight: return .weight
        case .bodyFat: return .bodyFat
        case .steps: return .steps
        case .activeCalories: return .activeCalories
        }
    }

    // MARK: - Helper Colors

    private func accentColor(for metric: CoreHealthMetric) -> Color {
        switch metric {
        case .hrv, .recovery: return VelaTheme.rhythmInk
        case .restingHeartRate, .strain: return VelaTheme.rhythmInk
        case .sleepDuration, .sleepScore: return VelaTheme.rhythmInk
        case .stress: return VelaTheme.rhythmInk
        case .energy: return VelaTheme.rhythmInk
        case .respiratoryRate, .oxygenSaturation, .bodyWeight, .bodyFat, .steps, .activeCalories:
            return VelaTheme.rhythmDeep
        }
    }

    private func assessmentColor(for assessment: TrendAssessment) -> Color {
        switch assessment {
        case .favorable: return VelaTheme.brandLeaf
        case .unfavorable: return VelaTheme.rhythmInk
        case .neutral: return VelaTheme.rhythmInkSecondary
        case .insufficientData: return VelaTheme.muted
        }
    }
}

// MARK: - Period summary

/// One sentence for the selected window, built only from that window's
/// published trend findings. It never borrows today's brief.
struct TrendsPeriodSummary: Equatable {
    let headline: String
    let detail: String?

    static func make(horizon: HealthTrendHorizon, findings: [HealthTrendFinding]) -> TrendsPeriodSummary {
        let scoped = findings.filter { $0.horizon == horizon }
        let available = scoped.filter(\.isAvailable)
        let insufficient = scoped.filter { !$0.isAvailable }
        guard !available.isEmpty else {
            let most = scoped.map(\.sampleCount).max() ?? 0
            return TrendsPeriodSummary(
                headline: "\(horizon.title)内的评分记录还不够判断变化",
                detail: "基线需要至少 \(horizon.requiredSampleCount) 个历史评分日，目前最多 \(most) 天，不含所选当天。"
            )
        }

        let rising = available.filter { $0.valueDirection == .rising }
        let falling = available.filter { $0.valueDirection == .falling }
        let steady = available.filter { $0.valueDirection != .rising && $0.valueDirection != .falling }
        var parts: [String] = []
        if !rising.isEmpty { parts.append("\(names(rising))上升") }
        if !falling.isEmpty { parts.append("\(names(falling))下降") }
        if !steady.isEmpty {
            if rising.isEmpty && falling.isEmpty {
                parts.append(steady.count == 5 ? "五项都比较平稳" : "\(names(steady))都比较平稳")
            } else {
                parts.append("\(names(steady))平稳")
            }
        }

        var notes: [String] = []
        let notable = available.filter(\.isNotable)
        if !notable.isEmpty {
            let labels = notable.map { "\($0.metric.shortTitle)\(BaselineDeviationCopy.label(for: $0) ?? "偏离")" }
            notes.append("最新一天\(labels.joined(separator: "、"))，对你而言不常见。")
        }
        if !insufficient.isEmpty {
            notes.append("\(names(insufficient))有评分的天数还不够，暂不判断。")
        }
        if notes.isEmpty {
            notes.append("方向按这段时间前后两半的中位数比较，不代表因果。")
        }
        return TrendsPeriodSummary(
            headline: parts.joined(separator: "，") + "。",
            detail: notes.joined(separator: " ")
        )
    }

    private static func names(_ findings: [HealthTrendFinding]) -> String {
        findings.map(\.metric.shortTitle).joined(separator: "、")
    }
}

// MARK: - History coverage

/// Scored days per metric in the loaded window. Counts come from the same
/// series the charts draw; a gap is a day without a score, never a zero.
struct TrendsCoverageRow: Identifiable, Equatable {
    let id: String
    let title: String
    let scoredDays: Int
    let windowDays: Int
    let requiredDays: Int
    let isLoaded: Bool
    var baselineDays: Int? = nil

    static func summaryText(_ rows: [TrendsCoverageRow], horizon: HealthTrendHorizon) -> String {
        guard let window = rows.map(\.windowDays).max(), !rows.isEmpty else {
            return "查看有评分的天数"
        }
        let scored = rows.map(\.scoredDays)
        let low = scored.min() ?? 0
        let high = scored.max() ?? 0
        let range = low == high ? "\(low)" : "\(low)–\(high)"
        return "图中 \(range)/\(window) 天有评分（含当天）"
    }
}

struct TrendsHistoryCoverageSheet: View {
    let horizon: HealthTrendHorizon
    let rows: [TrendsCoverageRow]
    let isPreview: Bool
    var rawCoverage: HistoricalCoverageSummary? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("图表包含所选当天；个人基线只使用当天之前的有效记录。因此图中评分天数与基线天数可能不同。")
                        .font(VelaTheme.subheadline())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            coverageRow(row)
                            if row.id != rows.last?.id {
                                Divider().overlay(VelaTheme.rhythmMist)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))

                    if let rawCoverage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("本机已有的原始汇总").font(VelaTheme.subheadline().weight(.semibold))
                            Text("有原始信号 \(rawCoverage.rawDays) 天，其中 \(rawCoverage.rawDaysWithoutScores) 天没有五项评分；另有 \(rawCoverage.emptyDays) 天仅有空记录。")
                                .font(VelaTheme.footnote())
                            Text("没有评分不等于没有健康记录。补算只处理从未计算的历史日；已计算但证据不足的日期仍可能没有分数。")
                                .font(VelaTheme.caption1()).foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("空档通常来自")
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        ForEach([
                            "那天没有佩戴 Apple Watch，或关键信号（如 HRV、睡眠）没有记录；",
                            "数据还没有从 Apple 健康同步到本机；",
                            "原始汇总已回填，但该日期尚未计算评分；",
                            "评分所需的证据不足，这一天按规则不计算。"
                        ], id: \.self) { line in
                            Text(line)
                                .font(VelaTheme.footnote())
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !isPreview {
                        NavigationLink(destination: HistoricalBackfillView()) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("同步或回填 Apple 健康历史")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .padding(16)
                            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(VelaTheme.pagePadding)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("有评分的天数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("history-coverage-details")
    }

    private func coverageRow(_ row: TrendsCoverageRow) -> some View {
        let fraction = row.windowDays > 0 ? Double(row.scoredDays) / Double(row.windowDays) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text(row.isLoaded ? "\(row.scoredDays) / \(row.windowDays) 天" : "读取中")
                    .font(VelaTheme.subheadline().monospacedDigit())
                    .foregroundStyle(VelaTheme.rhythmInk)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(VelaTheme.rhythmMist)
                    Capsule()
                        .fill(row.scoredDays < row.requiredDays ? VelaTheme.deviationInk : VelaTheme.rhythmInk)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            if row.isLoaded {
                Text("基线历史 \(row.baselineDays ?? 0)/\(row.requiredDays) 天，不含当天")
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.deviationInk)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metric row surface

/// Shared hairline card for the five score rows. The focus row and the dense
/// rows differ in height and type scale, never in chrome.
private struct TrendMetricCardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            }
    }
}

private extension View {
    func trendMetricCardSurface() -> some View {
        modifier(TrendMetricCardSurfaceModifier())
    }
}
