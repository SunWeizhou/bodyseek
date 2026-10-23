import Charts
import SwiftData
import SwiftUI

enum IntradayPhysiologyMetric {
    case stress
    case energy

    var signalColor: Color {
        switch self {
        case .stress: VelaTheme.rhythmInk
        case .energy: VelaTheme.rhythmInk
        }
    }

    var emptyTitle: String {
        switch self {
        case .stress: "暂无连续压力采样"
        case .energy: "暂无日内能量采样"
        }
    }
}

struct IntradayPhysiologyPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let value: Double
    let isActive: Bool
}

enum IntradayPhysiologySeriesBuilder {
    static func build(
        metric: IntradayPhysiologyMetric,
        records: [IntradaySignalBucketRecord],
        restingHeartRate: Double?,
        morningEnergy: Double?,
        currentEnergy: Double?
    ) -> [IntradayPhysiologyPoint] {
        let grouped = Dictionary(grouping: records, by: \.bucketStart)
        let orderedDates = grouped.keys.sorted()
        guard !orderedDates.isEmpty else { return [] }

        let heartRates = records
            .filter { $0.signalRawValue == HealthSignal.workoutHR.rawValue }
            .map(\.average)
            .filter { $0 > 0 }
        let inferredResting = heartRates.min()
        let baseline = max(restingHeartRate ?? inferredResting ?? 60, 40)

        var cumulativeLoad = 0.0
        let morning = morningEnergy ?? currentEnergy

        return orderedDates.compactMap { date in
            let buckets = grouped[date] ?? []
            let hr = buckets.first(where: { $0.signalRawValue == HealthSignal.workoutHR.rawValue })?.average
            let activeEnergy = buckets
                .filter { $0.signalRawValue == HealthSignal.activeEnergy.rawValue }
                .reduce(0) { $0 + max($1.average, 0) }
            let steps = buckets
                .filter { $0.signalRawValue == HealthSignal.stepCount.rawValue }
                .reduce(0) { $0 + max($1.average, 0) }
            let isActive = activeEnergy > 0.1 || steps >= 20

            switch metric {
            case .stress:
                guard let hr else { return nil }
                let elevation = max(0, (hr - baseline) / max(baseline, 1))
                let activityContext = isActive ? 8.0 : 0.0
                let score = min(max(elevation * 92 + activityContext, 0), 100)
                return IntradayPhysiologyPoint(
                    date: date,
                    value: score,
                    isActive: isActive
                )

            case .energy:
                guard let morning else { return nil }
                let hrLoad = hr.map { max(0, ($0 - baseline) / max(baseline, 1)) * 1.4 } ?? 0
                cumulativeLoad += activeEnergy * 0.045 + steps * 0.002 + hrLoad
                let projected = max(0, morning - cumulativeLoad)
                return IntradayPhysiologyPoint(
                    date: date,
                    value: projected,
                    isActive: isActive
                )
            }
        }
    }
}

struct DailyStressChartView: View {
    @Environment(\.modelContext) private var modelContext

    let metric: IntradayPhysiologyMetric
    let selectedDate: Date
    let restingHeartRate: Double?
    let morningEnergy: Double?
    let currentEnergy: Double?
    let isSleep: Bool

    @State private var points: [IntradayPhysiologyPoint] = []

    var body: some View {
        Group {
            if points.count > 1 {
                Chart(points) { point in
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("分数", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metric.signalColor.opacity(0.25), metric.signalColor.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("分数", point.value)
                    )
                    .foregroundStyle(metric.signalColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))

                    if point.isActive {
                        PointMark(
                            x: .value("时间", point.date),
                            y: .value("分数", point.value)
                        )
                        .symbolSize(14)
                        .foregroundStyle(metric.signalColor.opacity(0.85))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(VelaTheme.rhythmMist)
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text("\(score)")
                            }
                        }
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
                .accessibilityLabel(metric == .stress ? "日内压力趋势" : "日内能量趋势")
                .accessibilityValue("\(points.count) 个真实数据时段")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.5))
                    Text(metric.emptyTitle)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: selectedDate) {
            loadSeries()
        }
    }

    private func loadSeries() {
        let range = HealthDayBoundary(calendar: .current).range(forLabelDate: selectedDate)
        let start = range.start
        let end = range.end
        let records = (try? HealthSnapshotRepository(modelContext: modelContext)
            .fetchIntradayBuckets(from: start, until: end)) ?? []
        points = IntradayPhysiologySeriesBuilder.build(
            metric: metric,
            records: records,
            restingHeartRate: restingHeartRate,
            morningEnergy: morningEnergy,
            currentEnergy: currentEnergy
        )
    }
}
