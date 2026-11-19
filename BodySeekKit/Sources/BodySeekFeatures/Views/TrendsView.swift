import BodySeekCore
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
                horizonPills

                summaryCard(series: activeSeries)

                interactiveChartCard(series: activeSeries)

                dualAxisCard(days: horizonDays)

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

    private var horizonPills: some View {
        HStack(spacing: 8) {
            ForEach(TrendHorizon.allCases) { horizon in
                let isSelected = store.horizon == horizon
                Button {
                    store.send(.horizonChanged(horizon))
                } label: {
                    Text(horizon.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? BevelTheme.ink : BevelTheme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? BevelTheme.card : Color.clear, in: Capsule())
                }
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

                BevelMetricTrendChart(
                    series: series,
                    tint: tint,
                    selectedDate: Binding(
                        get: { store.selectedDate },
                        set: { store.send(.selectedDateChanged($0)) }
                    )
                )
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

                DualAxisLoadRecoveryChart(
                    days: days,
                    selectedDate: Binding(
                        get: { store.selectedDate },
                        set: { store.send(.selectedDateChanged($0)) }
                    )
                )
            }
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

                    MetricSparklineChart(
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
