import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 趋势页：顶部周期切换；L0 五项分数纵览（周期走向模型完成前代替 `BSVerdictGrid`）；
/// L1 Coach 解读；L2 各项趋势图；L3 实验室（预测、规律、个人对照实验）。
public struct TrendsView: View {
    private struct Readout: Equatable {
        let label: String
        let value: String?
        let side: String?
    }

    @Bindable var store: StoreOf<TrendsFeature>
    private let zoomNamespace: Namespace.ID?
    @State private var readouts: [MetricKind: Readout] = [:]

    public init(store: StoreOf<TrendsFeature>, zoomNamespace: Namespace.ID? = nil) {
        self.store = store
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        BSPage("趋势") {
            heroSection
        } note: {
            noteSection
        } sections: {
            chartsSection
        } links: {
            labSection
        }
        .onChange(of: store.horizon) {
            readouts = [:]
        }
        .sheet(isPresented: coverageBinding) {
            coverageSheetView
        }
    }

    private var coverageBinding: Binding<Bool> {
        Binding(
            get: { store.showCoverageSheet },
            set: { store.send(.coverageSheetPresented($0)) }
        )
    }

    // MARK: - L0 周期切换与五项分数纵览

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: BSSpace.s) {
            horizonPills
            BSMetricGrid {
                ForEach(store.allMetricSeries, id: \.kind) { series in
                    overviewTile(series)
                }
            }
        }
    }

    private var horizonPills: some View {
        HStack(spacing: BSSpace.xs) {
            ForEach(TrendHorizon.allCases) { horizon in
                horizonPill(horizon)
            }
            Spacer(minLength: BSSpace.none)
        }
    }

    private func horizonPill(_ horizon: TrendHorizon) -> some View {
        let isSelected = store.horizon == horizon
        let background = isSelected ? BSColor.tint.opacity(BSOpacity.faint) : BSColor.surfaceInset
        let foreground = isSelected ? BSColor.tint : Color.secondary
        return Button {
            store.send(.horizonChanged(horizon))
        } label: {
            Text(horizon.title)
                .font(.subheadline)
                .foregroundStyle(foreground)
                .padding(.horizontal, BSSpace.s)
                .padding(.vertical, BSSpace.xs)
                .background(background, in: Capsule())
        }
        .id("\(horizon.rawValue)-\(isSelected)")
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("trends-horizon-\(horizon.rawValue)")
    }

    @ViewBuilder
    private func overviewTile(_ series: TrendSeries) -> some View {
        let current = store.snapshot.today.score(for: series.kind)
        let tile = BSMetricTile(
            title: series.kind.title,
            value: current.value.map { String($0) },
            unit: "分",
            availability: current.availability,
            delta: current.baselineDelta.map { Double($0) },
            comparison: "vs 基线",
            trend: series.points.compactMap { $0.value.map { Double($0) } },
            tint: BSColor.domain(series.kind),
            action: { store.send(.openMetricDetail(series.kind)) }
        )
        .accessibilityIdentifier("trends-score-\(series.kind.rawValue)")
        if let zoomNamespace {
            tile.bodyseekZoomSource(id: "trends-metric-\(series.kind.rawValue)", in: zoomNamespace)
        } else {
            tile
        }
    }

    // MARK: - L1 Coach 解读

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            BSCoachNote(
                noteText,
                engine: BSBriefEngine(store.dailyBrief?.engine),
                onAsk: askCoachAction,
                askIdentifier: "trends-ask-coach-button"
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trends-ai-insight-card")
            coverageButton
        }
    }

    private var noteText: String {
        if case let .generated(text, _) = store.aiInsightStatus { return text }
        return store.deterministicTrendSummary
    }

    private var askCoachAction: () -> Void {
        { store.send(.askCoachTapped("结合我\(store.horizon.title)\(store.selectedKind.title)趋势、明日预测与个人统计规律，给出解释和调整建议")) }
    }

    private var coverageButton: some View {
        Button {
            store.send(.coverageSheetPresented(true))
        } label: {
            Label("\(store.snapshot.sourceLabel) · 查看覆盖", systemImage: "calendar")
                .bsText(.caption)
                .frame(minHeight: BSSize.hitTarget)
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("trends-history-coverage")
    }

    // MARK: - L2 各项趋势图

    private var chartsSection: some View {
        BSSection("各项趋势") {
            VStack(spacing: BSSpace.s) {
                ForEach(store.allMetricSnapshots, id: \.kind) { snapshot in
                    trendCard(snapshot)
                }
            }
        }
    }

    private func trendCard(_ snapshot: ChartSeriesSnapshot) -> some View {
        let kind = snapshot.kind
        let readout = readouts[kind]
        let label = readout?.label ?? "最新"
        let value = readout == nil ? latestValue(snapshot) : readout?.value
        return BSChartCard(
            title: "\(kind.title) · \(store.horizon.title)",
            label: label,
            value: value,
            unit: "分",
            range: dateRange(snapshot),
            side: readout?.side ?? baselineText(snapshot),
            availability: availability(snapshot),
            height: .standard,
            caption: "覆盖 \(snapshot.coveredDays)/\(snapshot.totalDays) 天 · \(store.snapshot.sourceLabel)"
        ) {
            TrendHorizonChart(
                snapshot: snapshot,
                tint: BSColor.domain(kind),
                height: BSSize.chartStandard - BSSpace.l,
                showsHeader: false,
                onSelectDate: { date in select(kind: kind, snapshot: snapshot, date: date) },
                onSelectBucket: { bucket in select(kind: kind, bucket: bucket) }
            )
        }
    }

    private func availability(_ snapshot: ChartSeriesSnapshot) -> MetricAvailability {
        if snapshot.coveredDays == 0 { return .missing(reason: "这个周期内没有有效样本") }
        return .available
    }

    private func latestValue(_ snapshot: ChartSeriesSnapshot) -> String? {
        guard let value = snapshot.dailyPoints.last(where: { $0.value != nil })?.value else { return nil }
        return String(Int(value.rounded()))
    }

    private func baselineText(_ snapshot: ChartSeriesSnapshot) -> String? {
        snapshot.medianValue.map { "基线中位 \(Int($0.rounded()))" }
    }

    private func dateRange(_ snapshot: ChartSeriesSnapshot) -> String {
        guard let first = snapshot.dailyPoints.first?.date, let last = snapshot.dailyPoints.last?.date else { return "" }
        let start = first.formatted(.dateTime.month().day())
        let end = last.formatted(.dateTime.month().day())
        return "\(start)–\(end)"
    }

    private func select(kind: MetricKind, snapshot: ChartSeriesSnapshot, date: Date?) {
        store.send(.selectedDateChanged(date))
        guard let date, let point = nearestPoint(snapshot.dailyPoints, to: date) else {
            readouts[kind] = nil
            return
        }
        readouts[kind] = Readout(
            label: point.date.formatted(.dateTime.month().day()),
            value: point.value.map { String(Int($0.rounded())) },
            side: point.availability.reasonText
        )
    }

    private func select(kind: MetricKind, bucket: RangeCapsuleBucket?) {
        store.send(.selectedDateChanged(bucket?.endDate))
        guard let bucket else {
            readouts[kind] = nil
            return
        }
        let low = Int(bucket.p25.rounded())
        let high = Int(bucket.p75.rounded())
        readouts[kind] = Readout(
            label: bucket.label,
            value: String(Int(bucket.median.rounded())),
            side: "P25–P75 \(low)–\(high) · 覆盖 \(bucket.sampleCount)/\(bucket.totalDays) 天"
        )
    }

    private func nearestPoint(_ points: [ChartPointSnapshot], to date: Date) -> ChartPointSnapshot? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: - L3 实验室

    private var labSection: some View {
        BSSection("实验室") {
            VStack(spacing: BSSpace.s) {
                BSLabEntry("明日预测", value: forecastValue) {
                    TrendsForecastLabView(store: store)
                }
                BSLabEntry("我的规律", value: patternValue) {
                    TrendsPatternsLabView(store: store)
                }
                BSLabEntry("个人对照实验", value: experimentValue) {
                    TrendsExperimentsLabView(store: store)
                }
            }
        }
    }

    private var forecastValue: String? {
        switch store.personalForecast {
        case .insufficientData: "数据不足"
        case .available: nil
        }
    }

    private var patternValue: String? {
        let count = store.patternFindings.filter { $0.status != .dismissed }.count
        return count == 0 ? nil : "\(count) 条"
    }

    private var experimentValue: String? {
        let running = store.evaluatedExperiments.filter { $0.planItem.state == .adopted }.count
        return running == 0 ? nil : "进行中 \(running)"
    }

    // MARK: - 覆盖度

    private var coverageSheetView: some View {
        NavigationStack {
            List {
                ForEach(store.allMetricSeries, id: \.kind) { item in
                    HStack {
                        Label(item.kind.title, systemImage: item.kind.systemImage)
                            .foregroundStyle(BSColor.domain(item.kind))
                        Spacer()
                        Text("\(item.coveredDays)/\(item.totalDays) 天")
                            .bsText(.label)
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
