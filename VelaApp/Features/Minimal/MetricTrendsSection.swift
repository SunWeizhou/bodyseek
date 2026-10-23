import SwiftUI

struct CoreMetricTrendSeries: Equatable {
    var title: String
    var valueText: String
    var icon: String
    var statusLabel: String
    var valueDirection: TrendValueDirection
    var assessment: TrendAssessment
    var history: [Double]
}

extension VelaMetricDetailView.MetricType {
    var coreMetric: CoreHealthMetric? {
        switch self {
        case .hrv: return .hrv
        case .rhr: return .restingHeartRate
        case .sleep: return .sleepScore
        case .recovery: return .recovery
        case .strain: return .strain
        case .stress: return .stress
        case .energy: return .energy
        case .respiratoryRate: return .respiratoryRate
        case .bloodOxygen: return .oxygenSaturation
        case .weight: return .bodyWeight
        case .bodyFat: return .bodyFat
        case .steps: return .steps
        case .activeCalories: return .activeCalories
        case .activeMinutes: return nil
        }
    }
}

enum CoreMetricTrendMapper {
    static func seriesList(
        for metric: VelaMetricDetailView.MetricType,
        findings: [HealthTrendFinding] = [],
        snapshots: [DailyHealthSnapshot],
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) -> [TrendItem] {
        guard let core = metric.coreMetric else { return [] }

        let horizons: [HealthTrendHorizon] = [.sevenDays, .thirtyDays, .sixMonths]
        var items: [TrendItem] = []

        for horizon in horizons {
            let days = horizon.windowDays
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
            let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end

            let valuesWithDate = snapshots
                .filter { $0.date >= start && $0.date < end }
                .sorted { $0.date < $1.date }
                .compactMap { snap -> (Date, Double)? in
                    guard let v = value(for: metric, snapshot: snap) else { return nil }
                    return (snap.date, v)
                }

            let values = valuesWithDate.map { $0.1 }
            let finding = findings.first { $0.metric == core && $0.horizon == horizon }

            let horizonTitle = "\(horizon.detailedTitle)\(title(for: metric))"
            let valText = finding?.isAvailable == true ? (finding?.currentValueFormatted ?? "--") : (values.last.map { valueText(for: metric, value: $0) } ?? "--")
            let status = finding?.summary ?? "\(horizon.detailedTitle)数据积累中"
            let valueDir = finding?.valueDirection ?? .stable
            let assess = finding?.assessment ?? .insufficientData

            items.append(
                TrendItem(
                    title: horizonTitle,
                    value: valText,
                    icon: icon(for: metric),
                    statusLabel: status,
                    valueDirection: valueDir,
                    assessment: assess,
                    statusColor: assessmentColor(for: assess),
                    graphColor: assessmentColor(for: assess),
                    history: normalize(values)
                )
            )
        }

        return items
    }

    private static func assessmentColor(for assessment: TrendAssessment) -> Color {
        switch assessment {
        case .favorable: return VelaTheme.stateGood
        case .unfavorable: return VelaTheme.statePoor
        case .neutral: return VelaTheme.rhythmInkSecondary
        case .insufficientData: return VelaTheme.meta
        }
    }

    private static func value(
        for metric: VelaMetricDetailView.MetricType,
        snapshot: DailyHealthSnapshot
    ) -> Double? {
        switch metric {
        case .strain: snapshot.strainScore
        case .recovery: snapshot.recoveryScore
        case .sleep: snapshot.sleepScore
        case .stress: snapshot.stressIndex
        case .energy: snapshot.currentEnergy ?? snapshot.energyBank
        case .hrv: snapshot.hrvAverage
        case .rhr: snapshot.restingHeartRate
        case .weight: snapshot.bodyWeight
        case .bodyFat: snapshot.bodyFatPercent
        case .respiratoryRate: snapshot.respiratoryRate
        case .bloodOxygen: snapshot.oxygenSaturation
        case .steps: snapshot.steps
        case .activeCalories: snapshot.activeCalories
        case .activeMinutes: snapshot.activeMinutes ?? snapshot.workoutDuration
        }
    }

    private static func title(for metric: VelaMetricDetailView.MetricType) -> String {
        switch metric {
        case .strain: "负荷"
        case .recovery: "恢复"
        case .sleep: "睡眠"
        case .stress: "压力"
        case .energy: "能量"
        case .hrv: "HRV"
        case .rhr: "静息心率"
        case .weight: "体重"
        case .bodyFat: "体脂"
        case .respiratoryRate: "呼吸率"
        case .bloodOxygen: "血氧"
        case .steps: "步数"
        case .activeCalories: "活动消耗"
        case .activeMinutes: "活跃时长"
        }
    }

    private static func icon(for metric: VelaMetricDetailView.MetricType) -> String {
        switch metric {
        case .strain: "figure.run"
        case .recovery: "heart.circle.fill"
        case .sleep: "moon.stars.fill"
        case .stress: "waveform.path.ecg"
        case .energy: "bolt.fill"
        case .hrv: "waveform.path.ecg"
        case .rhr: "heart.fill"
        case .weight: "scalemass.fill"
        case .bodyFat: "figure.arms.open"
        case .respiratoryRate: "lungs.fill"
        case .bloodOxygen: "drop.fill"
        case .steps: "shoeprints.fill"
        case .activeCalories: "flame.fill"
        case .activeMinutes: "clock.badge.checkmark"
        }
    }

    private static func valueText(
        for metric: VelaMetricDetailView.MetricType,
        value: Double
    ) -> String {
        switch metric {
        case .strain, .recovery, .sleep, .energy, .stress:
            return "\(Int(value.rounded()))"
        case .hrv:
            return "\(Int(value.rounded())) ms"
        case .rhr:
            return "\(Int(value.rounded())) bpm"
        case .weight:
            return String(format: "%.1f kg", value)
        case .bodyFat:
            return String(format: "%.1f%%", value)
        case .respiratoryRate:
            return "\(Int(value.rounded()))/min"
        case .bloodOxygen:
            return "\(Int(value.rounded()))%"
        case .steps:
            return "\(Int(value.rounded())) 步"
        case .activeCalories:
            return "\(Int(value.rounded())) kcal"
        case .activeMinutes:
            return "\(Int(value.rounded())) 分钟"
        }
    }

    private static func normalize(_ values: [Double]) -> [Double] {
        guard let minimum = values.min(), let maximum = values.max() else { return [] }
        let distance = maximum - minimum
        guard distance > 0 else { return values.map { _ in 0.5 } }
        return values.map { ($0 - minimum) / distance }
    }
}

struct TrendItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let statusLabel: String
    var valueDirection: TrendValueDirection = .stable
    var assessment: TrendAssessment = .neutral
    let statusColor: Color
    let graphColor: Color
    let history: [Double]
}

struct MetricTrendsSection: View {
    let isSleep: Bool
    let items: [TrendItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("多尺度趋势与动量")
                    .font(VelaTheme.footnote().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
            }
            
            VStack(spacing: 0) {
                if items.isEmpty {
                    Label("积累更多数据后显示多尺度生理变化", systemImage: "chart.line.uptrend.xyaxis")
                        .font(VelaTheme.footnote())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(VelaTheme.rhythmDeep)
                                Text(item.title)
                                    .font(.system(.caption, design: .default, weight: .bold))
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                Spacer()
                                if item.assessment != .insufficientData {
                                    HStack(spacing: 4) {
                                        Image(systemName: item.valueDirection.icon)
                                            .font(.system(size: 10, weight: .bold))
                                        Text(item.assessment.label)
                                            .font(.system(.caption2, design: .default, weight: .semibold))
                                    }
                                    .foregroundStyle(item.statusColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(item.statusColor.opacity(0.12)))
                                }
                            }

                            HStack(alignment: .bottom, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.value)
                                        .font(.system(.title3, design: .default, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(VelaTheme.rhythmInk)
                                    Text(item.statusLabel)
                                        .font(.system(.caption2, design: .default))
                                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                
                                // Live sparkline path graph
                                if !item.history.isEmpty && item.history.count >= 2 {
                                    SparklineLineGraph(data: item.history, color: item.statusColor, height: 32, width: 85)
                                } else {
                                    Text("--")
                                        .font(VelaTheme.caption2())
                                        .foregroundStyle(VelaTheme.muted)
                                        .frame(width: 85, height: 32, alignment: .trailing)
                                }
                            }
                        }
                        .padding(14)

                        if index < items.count - 1 {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
        }
    }
}
