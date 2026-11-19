import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct MetricDetailView: View {
    @Bindable var store: StoreOf<MetricDetailFeature>
    private let zoomNamespace: Namespace.ID?
    private let zoomPrefix: String

    public init(
        store: StoreOf<MetricDetailFeature>,
        zoomNamespace: Namespace.ID? = nil,
        zoomPrefix: String = "today-metric"
    ) {
        self.store = store
        self.zoomNamespace = zoomNamespace
        self.zoomPrefix = zoomPrefix
    }

    public var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                chartCard

                evidenceCard

                Button {
                    store.send(.askCoachTapped)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("向 Coach 追问\(store.kind.title)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(BevelTheme.onBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityIdentifier("detail-ask-coach")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle(store.kind.title)
        .bodyseekNavigationBarInline()
        .bodyseekHideTabBar(!store.isSheet)
        .toolbar {
            if store.isSheet {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button {
                        store.send(.closeTapped)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("metric-detail-close")
                }
            }
        }

        if let zoomNamespace, !store.isSheet {
            content.bodyseekZoomTransition(sourceID: "\(zoomPrefix)-\(store.kind.rawValue)", in: zoomNamespace)
        } else {
            content
        }
    }

    private var headerCard: some View {
        let tint = BevelTheme.color(for: store.kind)
        return BevelCard {
            HStack(spacing: 16) {
                MetricRingView(score: store.currentScore, diameter: 86, lineWidth: 10)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(store.currentScore.badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.14), in: Capsule())

                        if let delta = store.currentScore.baselineDelta {
                            let sign = delta >= 0 ? "+" : ""
                            Text("较基线 \(sign)\(delta)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.deviationInk)
                        }
                    }

                    Text(store.kind.shortExplanation)
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var chartCard: some View {
        let series = store.series
        let tint = BevelTheme.color(for: store.kind)
        return BevelCard {
            VStack(alignment: .leading, spacing: 14) {
                Picker("时间窗口", selection: Binding(
                    get: { store.horizon },
                    set: { store.send(.horizonChanged($0)) }
                )) {
                    ForEach(TrendHorizon.allCases) { horizon in
                        Text(horizon.title).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline) {
                    Text(selectedPointLabel(series: series) ?? "\(store.currentScore.formattedScore) 分")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    if let median = series.median {
                        Text("基线 \(median) · 覆盖 \(series.coveredDays)/\(series.totalDays) 天")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    } else {
                        Text("覆盖 \(series.coveredDays)/\(series.totalDays) 天")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }

                let chartSnapshot = BevelScoringEngine.buildChartSeriesSnapshot(
                    for: store.kind,
                    horizon: store.horizon,
                    days: store.snapshot.historyDays,
                    referenceDate: store.snapshot.referenceDate
                )
                if store.horizon.usesRangeCapsules {
                    RangeCapsuleChart(snapshot: chartSnapshot, tint: tint) { bucket in
                        store.send(.selectedDateChanged(bucket?.endDate))
                    }
                } else {
                    TrendLineChart(snapshot: chartSnapshot, tint: tint) { date in
                        store.send(.selectedDateChanged(date))
                    }
                }

                Text(series.statusSummary)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private var evidenceCard: some View {
        let day = store.snapshot.today
        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("数据依据")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                if store.kind == .sleep && day.raw.sleepAsleepMinutes != nil {
                    SleepStageChart(segments: day.raw.sleepSegments, height: 158, interactive: true)
                    Divider()
                } else if store.kind == .stress && !day.stressTimeline.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("24 小时自主神经压力节律")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        IntradayBarChart(bins: day.stressTimeline, height: 112, interactive: true)
                    }
                    Divider()
                } else if store.kind == .energy && !day.energyCurve.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("昼夜电池充放电轨迹")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        EnergyAreaChart(curve: day.energyCurve, height: 112, interactive: true)
                    }
                    Divider()
                }

                evidenceRow("HRV (SDNN)", value: day.raw.hrvMs.map { "\(Int($0.rounded())) ms" } ?? "--")
                evidenceRow("静息心率", value: day.raw.restingHeartRateBpm.map { "\(Int($0.rounded())) bpm" } ?? "--")
                evidenceRow("睡眠时长", value: day.sleep.value != nil ? day.sleep.subtitle : "--")
                evidenceRow("动态消耗", value: day.raw.activeEnergyKcal.map { "\(Int($0.rounded())) kcal" } ?? "--")
                evidenceRow("锻炼时间", value: day.raw.exerciseMinutes.map { "\($0) 分钟" } ?? "--")
            }
        }
    }

    private func evidenceRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(BevelTheme.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(value == "--" ? BevelTheme.inkSecondary : BevelTheme.ink)
        }
    }

    private func selectedPointLabel(series: TrendSeries) -> String? {
        guard let selectedDate = store.selectedDate,
              let point = series.points.min(by: {
                  abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
              }) else {
            return nil
        }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return "\(f.string(from: point.date)) · \(point.value.map { "\($0) 分" } ?? "--")"
    }
}
