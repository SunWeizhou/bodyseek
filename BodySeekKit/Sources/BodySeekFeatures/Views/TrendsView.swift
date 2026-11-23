import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 趋势页（UI v4 §5）：周期切换 → 一张大图卡（统计头联动、横向锁定选点、查看逐日数据）→
/// 彩色纵览列表（同时是指标切换器）→ Coach 解读与覆盖度；右上角"实验室"入口。
public struct TrendsView: View {
    private struct Selection: Equatable {
        let label: String
        let value: String?
        let side: String
    }

    private static let chartAnchor = "trends-main-chart"
    private static let dailyRowLimit = 31
    private static let rollingWindow = 28
    private static let miniBarDays = 7

    @Bindable var store: StoreOf<TrendsFeature>
    private let zoomNamespace: Namespace.ID?
    @State private var selection: Selection?
    @State private var chartResetToken = 0
    @Environment(\.bsScrollTo) private var scrollTo

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
            EmptyView()
        } links: {
            labSection
        }
        .oneLineHeader(subtitle: rangeSubtitle) {
            labButton
        }
        .onChange(of: store.horizon) {
            clearSelection()
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

    private var labButton: some View {
        NavigationLink {
            TrendsLabHubView(store: store)
        } label: {
            BSHeaderGlyph(systemImage: "flask")
        }
        .accessibilityLabel("实验室")
        .accessibilityIdentifier("trends-lab-button")
    }

    private var activeSnapshot: ChartSeriesSnapshot {
        store.allMetricSnapshots.first { $0.kind == store.selectedKind } ?? store.activeChartSnapshot
    }

    private var rangeSubtitle: String {
        dateRange(activeSnapshot)
    }

    // MARK: - L0 周期切换、大图卡与纵览列表

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: BSSpace.s) {
            horizonPills
            mainChartCard
                .id(Self.chartAnchor)
            overviewList
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

    // MARK: 大图卡

    private var mainChartCard: some View {
        let snapshot = activeSnapshot
        let kind = snapshot.kind
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text("\(kind.title) · \(store.horizon.title)")
                    .bsText(.cardTitle)
                BSChartHeader(
                    label: selection?.label ?? "\(kind.title) · 日均",
                    value: selection == nil ? meanValue(snapshot) : selection?.value,
                    unit: "分",
                    range: dateRange(snapshot),
                    onClear: selection == nil ? nil : { clearSelection() },
                    trailing: {
                        Text(selection?.side ?? "\(snapshot.coveredDays) / \(snapshot.totalDays) 天有记录")
                            .bsText(.label)
                            .multilineTextAlignment(.trailing)
                    }
                )
                .accessibilityIdentifier("trends-main-chart-readout")
                chartRegion(snapshot)
                legend(kind)
                dailyDisclosure(snapshot)
                detailLink(kind)
            }
        }
    }

    @ViewBuilder
    private func chartRegion(_ snapshot: ChartSeriesSnapshot) -> some View {
        if snapshot.coveredDays == 0 {
            Text("这个周期内没有有效样本")
                .bsText(.label)
                .frame(maxWidth: .infinity, minHeight: BSSize.chartStandard)
                .background(BSColor.surfaceInset, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
        } else {
            TrendHorizonChart(
                snapshot: snapshot,
                tint: BSColor.domain(snapshot.kind),
                height: BSSize.chartStandard,
                showsHeader: false,
                onSelectDate: { date in select(snapshot: snapshot, date: date) },
                onSelectBucket: { bucket in select(snapshot: snapshot, bucket: bucket) }
            )
            .id(chartResetToken)
        }
    }

    private func legend(_ kind: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: BSSpace.xxs) {
            HStack(spacing: BSSpace.s) {
                legendItem(color: BSColor.domain(kind), text: kind.title)
                legendItem(color: Color.secondary.opacity(BSOpacity.muted), text: "平时范围")
            }
            Text("平时范围：每天之前 \(Self.rollingWindow) 天有效观测的 P25–P75；有效观测不足 7 天的日子不画。")
                .bsText(.caption)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Circle()
                .fill(color)
                .frame(width: BSSize.dot, height: BSSize.dot)
            Text(text)
                .bsText(.caption)
        }
    }

    private func dailyDisclosure(_ snapshot: ChartSeriesSnapshot) -> some View {
        DisclosureGroup {
            VStack(spacing: BSSpace.xs) {
                HStack {
                    Text("日期")
                    Spacer()
                    Text("数值")
                    Text("平时范围")
                        .frame(minWidth: BSSize.ringL, alignment: .trailing)
                }
                .bsText(.caption)
                ForEach(dailyRows(snapshot)) { point in
                    HStack {
                        Text(point.date.formatted(.dateTime.month().day()))
                        Spacer()
                        Text(point.value.map { String(Int($0.rounded())) } ?? "--")
                        Text(rangeText(point.rollingBand))
                            .frame(minWidth: BSSize.ringL, alignment: .trailing)
                    }
                    .bsText(.label)
                }
            }
            .padding(.top, BSSpace.xs)
        } label: {
            Text("查看逐日数据")
                .bsText(.label)
        }
        .accessibilityIdentifier("trends-daily-data")
    }

    private func dailyRows(_ snapshot: ChartSeriesSnapshot) -> [ChartPointSnapshot] {
        Array(snapshot.dailyPoints.suffix(Self.dailyRowLimit).reversed())
    }

    private func rangeText(_ band: RollingBand?) -> String {
        guard let band else { return "--" }
        return "\(Int(band.lower.rounded()))–\(Int(band.upper.rounded()))"
    }

    private func detailLink(_ kind: MetricKind) -> some View {
        Button {
            store.send(.openMetricDetail(kind))
        } label: {
            Text("查看\(kind.title)详情 →")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BSColor.domain(kind))
                .frame(minHeight: BSSize.hitTarget, alignment: .leading)
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("trends-open-detail-\(kind.rawValue)")
    }

    private func meanValue(_ snapshot: ChartSeriesSnapshot) -> String? {
        let values = snapshot.dailyPoints.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return String(Int((values.reduce(0, +) / Double(values.count)).rounded()))
    }

    // MARK: 选点

    private func clearSelection() {
        selection = nil
        chartResetToken += 1
        store.send(.selectedDateChanged(nil))
    }

    private func select(snapshot: ChartSeriesSnapshot, date: Date?) {
        store.send(.selectedDateChanged(date))
        guard let date, let point = nearestPoint(snapshot.dailyPoints, to: date) else {
            selection = nil
            return
        }
        let label = point.date.formatted(.dateTime.month().day()) + " · " + snapshot.kind.title
        selection = Selection(
            label: label,
            value: point.value.map { String(Int($0.rounded())) },
            side: bandText(value: point.value, band: point.rollingBand, reason: point.availability.reasonText)
        )
    }

    private func select(snapshot: ChartSeriesSnapshot, bucket: RangeCapsuleBucket?) {
        store.send(.selectedDateChanged(bucket?.endDate))
        guard let bucket else {
            selection = nil
            return
        }
        selection = Selection(
            label: "\(bucket.label) 起 · \(snapshot.kind.title)",
            value: String(Int(bucket.median.rounded())),
            side: bandText(value: bucket.median, band: bucket.rollingBand, reason: nil)
        )
    }

    private func bandText(value: Double?, band: RollingBand?, reason: String?) -> String {
        guard let value else { return reason ?? "当天缺失" }
        guard let band else { return "平时范围积累中（有效观测不足 7 晚）" }
        let position: String
        if value < band.lower {
            position = "低于"
        } else if value > band.upper {
            position = "高于"
        } else {
            position = "处于"
        }
        return "\(position)平时范围 \(rangeText(band))（\(band.sampleCount)/\(Self.rollingWindow) 晚）"
    }

    private func nearestPoint(_ points: [ChartPointSnapshot], to date: Date) -> ChartPointSnapshot? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func dateRange(_ snapshot: ChartSeriesSnapshot) -> String {
        guard let first = snapshot.dailyPoints.first?.date, let last = snapshot.dailyPoints.last?.date else { return "" }
        let start = first.formatted(.dateTime.month().day())
        let end = last.formatted(.dateTime.month().day())
        return "\(start)–\(end)"
    }

    // MARK: 纵览列表

    private var overviewList: some View {
        BSCard {
            VStack(spacing: BSSpace.xxs) {
                ForEach(store.allMetricSnapshots, id: \.kind) { snapshot in
                    overviewRow(snapshot)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trends-overview-list")
    }

    private func overviewRow(_ snapshot: ChartSeriesSnapshot) -> some View {
        let kind = snapshot.kind
        return BSTrendSwitchRow(
            title: kind.title,
            systemImage: BSIconBlock.symbol(for: kind),
            tint: BSColor.domain(kind),
            meanText: meanValue(snapshot) ?? "--",
            changeText: changeText(snapshot),
            isSelected: kind == store.selectedKind,
            identifier: "trends-score-\(kind.rawValue)",
            action: { switchKind(kind) },
            mini: { miniView(snapshot) }
        )
    }

    @ViewBuilder
    private func miniView(_ snapshot: ChartSeriesSnapshot) -> some View {
        let tint = BSColor.domain(snapshot.kind)
        if snapshot.kind == .strain {
            let recent = snapshot.dailyPoints.suffix(Self.miniBarDays).map(\.value)
            LoadWeekBarsMini(values: recent, tint: tint)
        } else {
            BSMiniTrendLine(points: miniPoints(snapshot), tint: tint)
        }
    }

    private func miniPoints(_ snapshot: ChartSeriesSnapshot) -> [Double] {
        if snapshot.capsules.count >= 2 { return snapshot.capsules.map(\.median) }
        return snapshot.dailyPoints.compactMap(\.value)
    }

    private func changeText(_ snapshot: ChartSeriesSnapshot) -> String {
        guard let delta = snapshot.halfDelta else { return "--" }
        if delta == 0 { return "持平" }
        return delta > 0 ? "+\(delta)" : "−\(abs(delta))"
    }

    private func switchKind(_ kind: MetricKind) {
        if kind != store.selectedKind {
            store.send(.kindSelected(kind))
            clearSelection()
        }
        scrollTo?(Self.chartAnchor)
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

    // MARK: - L3 实验室

    private var labSection: some View {
        BSSection("实验室") {
            TrendsLabEntries(store: store)
        }
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

/// 实验室三个入口（预测、规律、个人对照实验）；趋势页底部与"实验室"二级页共用。
struct TrendsLabEntries: View {
    @Bindable var store: StoreOf<TrendsFeature>

    var body: some View {
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
}

/// "实验室"二级页：右上角入口进入。
struct TrendsLabHubView: View {
    @Bindable var store: StoreOf<TrendsFeature>

    var body: some View {
        BSPage("实验室") {
            EmptyView()
        } sections: {
            TrendsLabEntries(store: store)
        }
    }
}
