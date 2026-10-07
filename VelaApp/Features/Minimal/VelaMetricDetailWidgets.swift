import SwiftUI

struct CoreMetricHeroFact: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let value: String
    let systemImage: String
}

/// The first viewport for the five canonical scored domains. It preserves the
/// Today grammar while giving each metric its own physical representation:
/// rings for Recovery/Sleep/Strain, a dial for Stress, and reserve bars for
/// Energy. The score remains primary; guidance is one short, tappable line.
struct CoreMetricDetailHero: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metric: VelaMetricDetailView.MetricType
    let valueText: String
    let score: Double?
    let color: Color
    let state: MetricState
    let guidance: String
    let facts: [CoreMetricHeroFact]
    let baselineValue: Double?
    let targetRange: ClosedRange<Double>?
    let onAskCoach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 8) {
                BodySeekMetricGlyph(
                    kind: glyphKind,
                    size: 24,
                    tint: color
                )
                Text("今日读数 / \(metric.accessibleTitle)")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(color)
                    .tracking(1.1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    heroVisual
                    factColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    heroVisual
                        .frame(maxWidth: .infinity)
                    factColumn
                }
            }

            Divider()
                .overlay(VelaTheme.rhythmMist)

            Button {
                VelaHaptic.selection()
                onAskCoach()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("指导")
                            .font(VelaTheme.caption1().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Image(systemName: "sparkles")
                            .font(VelaTheme.caption2().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(guidance)
                            .font(VelaTheme.body().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(metric.accessibleTitle)指导，\(guidance)")
            .accessibilityHint("打开 Coach 继续追问")
        }
        .padding(18)
        .background {
            ZStack(alignment: .topTrailing) {
                VelaTheme.rhythmCanvasRaised
                BodySeekArtwork(kind: artworkKind, tint: color)
                    .frame(width: 180, height: 200)
                    .opacity(colorSchemeContrast == .increased ? 0 : 0.13)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: VelaTheme.radiusFeature, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusFeature, style: .continuous)
                .stroke(
                    colorSchemeContrast == .increased
                        ? VelaTheme.rhythmInk
                        : VelaTheme.rhythmMist.opacity(0.82),
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.6
                )
        }
        .accessibilityIdentifier("metric-detail-hero")
    }

    private var artworkKind: BodySeekArtworkKind {
        switch metric {
        case .sleep: return .sleep
        case .strain: return .strain
        case .stress: return .stress
        case .energy: return .energy
        default: return .recovery
        }
    }

    private var glyphKind: BodySeekMetricGlyphKind {
        switch metric {
        case .sleep: return .sleep
        case .strain, .activeCalories, .activeMinutes, .steps: return .strain
        case .stress, .hrv, .respiratoryRate: return .stress
        case .energy, .weight, .bodyFat: return .energy
        case .recovery, .rhr, .bloodOxygen: return .recovery
        }
    }

    @ViewBuilder
    private var heroVisual: some View {
        switch metric {
        case .recovery, .sleep, .strain:
            CoreMetricScoreRing(
                valueText: valueText,
                score: score,
                color: color,
                baselineValue: baselineValue,
                targetRange: metric == .strain ? targetRange : nil
            )
        case .stress:
            CoreMetricStressDial(score: score, state: state)
        case .energy:
            CoreMetricEnergyReserve(valueText: valueText, score: score, color: color)
        default:
            EmptyView()
        }
    }

    private var factColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(facts) { fact in
                HStack(spacing: 10) {
                    Image(systemName: fact.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 26, height: 26)
                        .background(color.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(fact.title)
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Text(fact.value)
                            .font(VelaTheme.subheadline().weight(.semibold).monospacedDigit())
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CoreMetricScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let valueText: String
    let score: Double?
    let color: Color
    let baselineValue: Double?
    let targetRange: ClosedRange<Double>?

    private var progress: Double {
        min(1, max(0, (score ?? 0) / 100))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(VelaTheme.rhythmCanvasRaised)

            Circle()
                .stroke(color.opacity(0.12), lineWidth: 9)

            if let targetRange {
                Circle()
                    .trim(
                        from: min(1, max(0, targetRange.lowerBound / 100)),
                        to: min(1, max(0, targetRange.upperBound / 100))
                    )
                    .stroke(
                        color.opacity(0.34),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(-7)
            }

            if score != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.70), color], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(VelaTheme.dataAnimation(reduceMotion: reduceMotion), value: progress)
            } else {
                Circle()
                    .stroke(
                        VelaTheme.rhythmInkSecondary.opacity(0.34),
                        style: StrokeStyle(lineWidth: 2, dash: [3, 5])
                    )
            }

            if let baselineValue {
                Circle()
                    .fill(VelaTheme.rhythmInkSecondary)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(VelaTheme.rhythmCanvasRaised, lineWidth: 2))
                    .offset(y: -58)
                    .rotationEffect(.degrees(min(100, max(0, baselineValue)) * 3.6))
                    .accessibilityHidden(true)
            }

            Text(valueText)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(VelaTheme.rhythmInk)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: 124, height: 124)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前值")
        .accessibilityValue(valueText)
    }
}

private struct CoreMetricStressDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let score: Double?
    let state: MetricState

    private let tickCount = 36

    private var filledTicks: Int {
        guard let score else { return 0 }
        return Int((min(100, max(0, score)) / 100 * Double(tickCount)).rounded(.up))
    }

    private var stateLabel: String {
        guard score != nil else { return "等待数据" }
        switch state {
        case .good: return "低"
        case .moderate: return "适中"
        case .poor: return "高"
        }
    }

    var body: some View {
        ZStack {
            // One Canvas node draws all 36 ticks (previously 36 individual
            // Capsule views) around the dial.
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<tickCount {
                    let angle = Angle.degrees(-128 + Double(index) * 256 / Double(tickCount - 1))
                    context.drawLayer { layer in
                        layer.translateBy(x: center.x, y: center.y)
                        layer.rotate(by: angle)
                        let rect = CGRect(x: -1.5, y: -57, width: 3, height: 10)
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        layer.fill(
                            path,
                            with: .color(index < filledTicks ? VelaTheme.color(for: state) : VelaTheme.rhythmMist)
                        )
                    }
                }
            }

            VStack(spacing: 2) {
                Text(score.map { String(Int($0.rounded())) } ?? "--")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(stateLabel)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(score == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.textColor(for: state))
            }
            .offset(y: 4)
        }
        .frame(width: 124, height: 124)
        .animation(VelaTheme.dataAnimation(reduceMotion: reduceMotion), value: filledTicks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前生理压力信号")
        .accessibilityValue(score.map { "\(Int($0.rounded()))，\(stateLabel)" } ?? "暂无数据")
    }
}

private struct CoreMetricEnergyReserve: View {
    let valueText: String
    let score: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                Text(valueText)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VelaTheme.rhythmInk)
            }

            SegmentedBatteryBar(
                percentage: min(1, max(0, (score ?? 0) / 100)),
                barCount: 18,
                color: color
            )
            .opacity(score == nil ? 0.45 : 1)
        }
        .padding(16)
        .frame(width: 154, height: 112, alignment: .leading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前能量剩余")
        .accessibilityValue(valueText)
    }
}

private extension VelaMetricDetailView.MetricType {
    var accessibleTitle: String {
        switch self {
        case .recovery: return "恢复"
        case .sleep: return "睡眠"
        case .strain: return "负荷"
        case .stress: return "压力"
        case .energy: return "能量"
        default: return rawValue
        }
    }
}

struct MetricCustomWidgetsSection: View {
    let metric: VelaMetricDetailView.MetricType
    let isSleep: Bool
    let dashboard: DashboardSummary
    
    // Sleep parameters
    let bedtimeHour: Int
    let bedtimeMinute: Int
    let wakeHour: Int
    let wakeMinute: Int
    let sleepTargetMinutes: Int
    let hasCompleteSleepTimes: Bool
    
    let bedtimeText: String
    let targetBedtimeText: String
    let wakeTimeText: String
    let primarySleepStartText: String
    
    // Timeline
    let selectedFullDateText: String
    
    // Heart Rate Zones
    let isLoadingHeartRateZones: Bool
    let heartRateZoneSummary: HeartRateZoneSummary?
    let heartRateZoneRowAction: (HeartRateZoneSummary.Zone, Double) -> AnyView
    let limitingFactors: [String]
    let metricColor: Color

    var body: some View {
        switch metric {
        case .recovery:
            VStack(alignment: .leading, spacing: VelaTheme.cardGap) {
                Text("恢复基线")
                    .font(VelaTheme.footnote().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)

                HStack(spacing: 10) {
                    recoveryBaselineMetric(
                        title: "HRV",
                        current: dashboard.recoveryMetrics.hrvMilliseconds,
                        baseline: dashboard.recoveryBaseline.hrvMilliseconds,
                        unit: "ms",
                        higherIsBetter: true
                    )
                    recoveryBaselineMetric(
                        title: "静息心率",
                        current: dashboard.recoveryMetrics.restingHeartRate,
                        baseline: dashboard.recoveryBaseline.restingHeartRate,
                        unit: "bpm",
                        higherIsBetter: false
                    )
                }

            }

        case .strain:
            // --- Strain Custom Views ---
            VStack(alignment: .leading, spacing: VelaTheme.cardGap) {
                // Timeline
                HStack {
                    Text("时间线")
                        .font(VelaTheme.footnote().weight(.bold))
                        .foregroundStyle(isSleep ? VelaTheme.inkGray : VelaTheme.rhythmInk)
                    Spacer()
                }
                
                VelaTimelineCard(
                    items: dashboard.workouts.map { workout in
                        VelaTimelineItem(
                            id: workout.id.uuidString,
                            title: workout.activityName,
                            subtitle: VelaMinimalFormatting.duration(
                                minutes: Int(workout.end.timeIntervalSince(workout.start) / 60.0)
                            ),
                            systemImage: "figure.run",
                            domain: .strain
                        )
                    },
                    emptyMessage: "此期间没有记录到活动。"
                )

                // Heart Rate Zones
                VStack(alignment: .leading, spacing: 10) {
                    Text("心率区间")
                        .font(VelaTheme.footnote().weight(.bold))
                        .foregroundStyle(isSleep ? VelaTheme.inkGray : VelaTheme.rhythmInk)

                    if isLoadingHeartRateZones {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 72)
                    } else if let heartRateZoneSummary {
                        VStack(spacing: 10) {
                            ForEach(heartRateZoneSummary.zones) { zone in
                                heartRateZoneRowAction(zone, heartRateZoneSummary.totalMinutes)
                            }
                        }
                    } else {
                        Text("此期间没有可用的逐点心率，无法生成分区明细。")
                            .font(VelaTheme.caption1())
                            .foregroundStyle(isSleep ? VelaTheme.inkGray : VelaTheme.muted)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )

                strainLoadContext
            }

        case .sleep:
            sleepTimelineContent

        case .stress:
            VStack(alignment: .leading, spacing: VelaTheme.cardGap) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("压力计算证据")
                        .font(VelaTheme.footnote().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)

                    stressEvidenceRow("心率", key: "rhr_stress", symbol: "heart.fill")
                    stressEvidenceRow("HRV", key: "hrv_stress", symbol: "waveform.path.ecg")
                    stressEvidenceRow("睡眠债", key: "sleep_debt_stress", symbol: "moon.zzz.fill")
                    stressEvidenceRow("近期负荷", key: "load_stress", symbol: "figure.run")

                    Label("尚无可追溯的连续日内压力采样", systemImage: "clock.badge.questionmark")
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.top, 2)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }

        case .energy:
            VStack(alignment: .leading, spacing: VelaTheme.cardGap) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("能量变化")
                                .font(VelaTheme.footnote().weight(.bold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Text("从早间储备到当前状态")
                                .font(VelaTheme.caption2())
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                        Spacer()
                        Text("\(Int(dashboard.energy.morningEnergy.rounded())) → \(dashboard.energy.formattedScore)")
                            .font(VelaTheme.subheadline().weight(.bold).monospacedDigit())
                            .foregroundStyle(metricColor)
                    }

                    energyReserveComparison

                    HStack(spacing: 8) {
                        energyDriver("负荷", value: dashboard.energy.components["strain_drain"])
                        energyDriver("压力", value: dashboard.energy.components["stress_drain"])
                        energyDriver("时间", value: dashboard.energy.components["time_drain"])
                        if let recharge = dashboard.energy.components["recharge"], recharge > 0 {
                            energyDriver("补充", value: recharge, positive: true)
                        }
                    }

                    Text("当前仅显示早间与当前两个可追溯的计算截面。")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }

        default:
            // --- Default Evidence List for other metrics ---
            VStack(alignment: .leading, spacing: 10) {
                Text("主要限制因素")
                    .font(VelaTheme.footnote())
                    .fontWeight(.bold)
                    .foregroundStyle(isSleep ? VelaTheme.inkGray : VelaTheme.muted)
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(limitingFactors, id: \.self) { factor in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(metricColor)
                                .frame(width: 6, height: 6)
                            Text(factor)
                                .font(VelaTheme.subheadline())
                                .foregroundStyle(isSleep ? VelaTheme.mistGray : VelaTheme.fg2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }
        }
    }

    private func recoveryBaselineMetric(
        title: String,
        current: Double?,
        baseline: Double?,
        unit: String,
        higherIsBetter: Bool
    ) -> some View {
        let delta = current.flatMap { value in baseline.map { value - $0 } }
        let isPositive = delta.map { higherIsBetter ? $0 >= 0 : $0 <= 0 }
        return VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(current.map { "\(Int($0.rounded())) \(unit)" } ?? "--")
                .font(VelaTheme.cardValue())
                .foregroundStyle(VelaTheme.rhythmInk)
                .monospacedDigit()
            Text(baseline.map { "基线 \(Int($0.rounded())) \(unit)" } ?? "个人基线建立中")
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            if let delta, let isPositive {
                Label(
                    "\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta))",
                    systemImage: isPositive ? "arrow.up.right" : "arrow.down.right"
                )
                .font(VelaTheme.caption2().weight(.semibold))
                .foregroundStyle(isPositive ? VelaTheme.recoveryColor : VelaTheme.warn)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }

    private var sleepTimelineContent: some View {
        SleepTimelineCard(
            summary: dashboard.sleepSummary,
            bedtimeText: bedtimeText,
            wakeTimeText: wakeTimeText,
            targetBedtimeText: targetBedtimeText,
            sleepTargetMinutes: sleepTargetMinutes,
            hasCompleteSleepTimes: hasCompleteSleepTimes
        )
    }

    private var strainLoadContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练节律")
                .font(VelaTheme.footnote().weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInk)
            HStack(spacing: 8) {
                loadFact("7 天负荷", key: "acute_7d_load")
                loadFact("28 天等效", key: "chronic_28d_equivalent")
                loadFact("负荷比", key: "training_load_ratio", suffix: "x")
            }
        }
        .padding(14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        }
    }

    private func loadFact(_ title: String, key: String, suffix: String = "") -> some View {
        let value = dashboard.strain.components[key]
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(2)
            Text(value.map { String(format: "%.1f%@", $0, suffix) } ?? "--")
                .font(VelaTheme.subheadline().weight(.semibold).monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func energyDriver(
        _ title: String,
        value: Double?,
        positive: Bool = false
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.muted)
            Text(value.map { "\(positive ? "+" : "−")\(String(format: "%.0f", abs($0)))" } ?? "--")
                .font(VelaTheme.caption1().weight(.bold).monospacedDigit())
                .foregroundStyle(positive ? VelaTheme.recoveryColor : VelaTheme.fg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(VelaTheme.rhythmMist.opacity(0.35), in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
    }

    private func stressEvidenceRow(
        _ title: String,
        key: String,
        symbol: String
    ) -> some View {
        let value = dashboard.stress.components[key]
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.stressColor)
                .frame(width: 28, height: 28)
                .background(VelaTheme.stressColor.opacity(0.10), in: Circle())
            Text(title)
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.rhythmInk)
            Spacer(minLength: 8)
            Text(value.map { "\(Int($0.rounded()))" } ?? "-- · 未采集")
                .font(VelaTheme.subheadline().weight(.semibold).monospacedDigit())
                .foregroundStyle(value == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
        }
        .frame(minHeight: VelaTheme.minimumHitTarget)
    }

    private var energyReserveComparison: some View {
        VStack(spacing: 12) {
            reserveBar(
                title: "早间储备",
                value: dashboard.energy.hasData ? dashboard.energy.morningEnergy : nil
            )
            reserveBar(
                title: "当前剩余",
                value: dashboard.energy.value
            )
        }
        .padding(.vertical, 4)
    }

    private func reserveBar(title: String, value: Double?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .frame(width: 68, alignment: .leading)
            SegmentedBatteryBar(
                percentage: min(1, max(0, (value ?? 0) / 100)),
                barCount: 20,
                color: VelaTheme.energyColor
            )
            .opacity(value == nil ? 0.35 : 1)
            Text(value.map { "\(Int($0.rounded()))" } ?? "--")
                .font(VelaTheme.caption1().weight(.bold).monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - iOS WidgetKit Glancing Views (P3)

/// 锁屏圆形小组件 (Lock Screen Accessory Circular)
public struct VelaLockScreenCircularView: View {
    public let snapshot: VelaWidgetSnapshot

    public init(snapshot: VelaWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .bold))
                Text(snapshot.recoveryScore.map { "\($0)" } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
    }

    private var ringProgress: Double {
        guard let score = snapshot.recoveryScore else { return 0 }
        return min(1, max(0, Double(score) / 100))
    }
}

/// 锁屏矩形小组件 (Lock Screen Accessory Rectangular)
public struct VelaLockScreenRectangularView: View {
    public let snapshot: VelaWidgetSnapshot

    public init(snapshot: VelaWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("恢复 \(snapshot.recoveryScore.map { "\($0)%" } ?? "—") · \(snapshot.decision)")
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }

            Text(snapshot.sessionTitle ?? snapshot.primaryAction)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Text(snapshot.summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 锁屏单行小组件 (Lock Screen Accessory Inline)
public struct VelaLockScreenInlineView: View {
    public let snapshot: VelaWidgetSnapshot

    public init(snapshot: VelaWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
            Text("恢复 \(snapshot.recoveryScore.map { "\($0)%" } ?? "—") · \(snapshot.decision)")
        }
    }
}

/// 桌面小尺寸组件 (System Small Widget)
public struct VelaSystemSmallWidgetView: View {
    public let snapshot: VelaWidgetSnapshot

    public init(snapshot: VelaWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("VELA")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Spacer()
                if let rhr = snapshot.restingHeartRate {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(VelaTheme.stressColor)
                        Text("\(rhr)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }

            Spacer()

            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(VelaTheme.rhythmMist, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(snapshot.recoveryScore.map { "\($0)" } ?? "—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text("恢复指数")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.meta)
                    Text(snapshot.decision)
                        .font(VelaTheme.subheadline().weight(.bold))
                        .foregroundStyle(scoreColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(snapshot.primaryAction)
                .font(VelaTheme.caption2().weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised)
    }

    private var ringProgress: Double {
        guard let score = snapshot.recoveryScore else { return 0 }
        return min(1, max(0, Double(score) / 100))
    }

    private var scoreColor: Color {
        guard let score = snapshot.recoveryScore else { return VelaTheme.muted }
        if score < 40 { return VelaTheme.stressColor }
        if score < 70 { return VelaTheme.tagOrange }
        return VelaTheme.recoveryColor
    }
}

/// 桌面中尺寸组件 (System Medium Widget)
public struct VelaSystemMediumWidgetView: View {
    public let snapshot: VelaWidgetSnapshot

    public init(snapshot: VelaWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        HStack(spacing: 16) {
            // 左侧恢复环
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(VelaTheme.rhythmMist, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text(snapshot.recoveryScore.map { "\($0)" } ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("恢复")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(VelaTheme.meta)
                    }
                }
                .frame(width: 72, height: 72)

                HStack(spacing: 8) {
                    if let hrv = snapshot.hrvMilliseconds {
                        Text("HRV \(hrv)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    if let rhr = snapshot.restingHeartRate {
                        Text("静息 \(rhr)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
            .frame(width: 90)

            Divider()
                .overlay(VelaTheme.rhythmMist)

            // 右侧决策与训练
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snapshot.decision)
                        .font(VelaTheme.headline().weight(.bold))
                        .foregroundStyle(scoreColor)
                    Spacer()
                    Text("VELA")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(VelaTheme.rhythmDeep)
                }

                Text(snapshot.sessionTitle ?? "今日无排期训练")
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineLimit(1)

                Text(snapshot.summary)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(2)
                    .lineSpacing(2)

                if let plan = snapshot.planTitle {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(VelaTheme.meta)
                        Text(plan)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VelaTheme.meta)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VelaTheme.rhythmCanvasRaised)
    }

    private var ringProgress: Double {
        guard let score = snapshot.recoveryScore else { return 0 }
        return min(1, max(0, Double(score) / 100))
    }

    private var scoreColor: Color {
        guard let score = snapshot.recoveryScore else { return VelaTheme.muted }
        if score < 40 { return VelaTheme.stressColor }
        if score < 70 { return VelaTheme.tagOrange }
        return VelaTheme.recoveryColor
    }
}

/// 桌面大尺寸组件 (System Large Widget)
public struct VelaSystemLargeWidgetView: View {
    public let snapshot: VelaWidgetSnapshot

    public init(snapshot: VelaWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("VELA")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Spacer()
                Text(snapshot.generatedAt, style: .date)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.meta)
            }

            // 头部恢复与决策
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(VelaTheme.rhythmMist, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text(snapshot.recoveryScore.map { "\($0)" } ?? "—")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("恢复")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VelaTheme.meta)
                    }
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.decision)
                        .font(VelaTheme.title3().weight(.bold))
                        .foregroundStyle(scoreColor)
                    Text(snapshot.primaryAction)
                        .font(VelaTheme.subheadline().weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(snapshot.summary)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(2)
                }
            }

            Divider()
                .overlay(VelaTheme.rhythmMist)

            // 四象限生理信号矩阵
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCell("睡眠", snapshot.sleepScore.map { "\($0)" } ?? "—", "moon.fill", VelaTheme.accent)
                metricCell("负荷", snapshot.strainScore.map { "\($0)" } ?? "—", "flame.fill", VelaTheme.tagOrange)
                metricCell("压力", snapshot.stressScore.map { "\($0)" } ?? "—", "waveform.path.ecg", VelaTheme.stressColor)
                metricCell("能量", snapshot.energyScore.map { "\($0)%" } ?? "—", "battery.75percent", VelaTheme.energyColor)
            }

            Spacer()

            // 底部计划状态
            if let plan = snapshot.planTitle {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 12))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text(plan)
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    if let progress = snapshot.planProgress {
                        Text(progress)
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.meta)
                    }
                }
                .padding(10)
                .background(VelaTheme.rhythmMist.opacity(0.4), in: RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised)
    }

    private func metricCell(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(VelaTheme.meta)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(VelaTheme.rhythmInk)
            }
            Spacer()
        }
        .padding(8)
        .background(VelaTheme.rhythmMist.opacity(0.35), in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
    }

    private var ringProgress: Double {
        guard let score = snapshot.recoveryScore else { return 0 }
        return min(1, max(0, Double(score) / 100))
    }

    private var scoreColor: Color {
        guard let score = snapshot.recoveryScore else { return VelaTheme.muted }
        if score < 40 { return VelaTheme.stressColor }
        if score < 70 { return VelaTheme.tagOrange }
        return VelaTheme.recoveryColor
    }
}

/// 小组件预览画廊 (Widget Preview Gallery)
public struct VelaWidgetPreviewGalleryView: View {
    @State private var mockSnapshot = VelaWidgetSnapshot(
        generatedAt: Date(),
        bodyStateTitle: "恢复状态良好",
        summary: "睡眠与 HRV 均在基线正常范围内，适宜安排高质量训练。",
        decision: "按计划训练",
        decisionConfidence: 0.88,
        recoveryScore: 84,
        sleepScore: 81,
        strainScore: 42,
        stressScore: 22,
        energyScore: 78,
        hrvMilliseconds: 62,
        restingHeartRate: 51,
        primaryAction: "今日排期：下肢力量进阶",
        planTitle: "四周力量进阶",
        sessionTitle: "下肢力量 · 深蹲与硬拉",
        sessionDetail: "50 分钟 · 中高强度",
        planProgress: "6/16 已完成"
    )

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Vela WidgetKit 小组件预览")
                    .font(VelaTheme.title2().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .padding(.horizontal)

                // 1. 锁屏小组件
                VStack(alignment: .leading, spacing: 12) {
                    Text("锁屏小组件 (Lock Screen)")
                        .font(VelaTheme.subheadline().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        VelaLockScreenCircularView(snapshot: mockSnapshot)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.black.opacity(0.8)))

                        VelaLockScreenRectangularView(snapshot: mockSnapshot)
                            .frame(width: 155, height: 60)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.8)))
                    }
                    .padding(.horizontal)

                    VelaLockScreenInlineView(snapshot: mockSnapshot)
                        .padding(.horizontal)
                        .foregroundStyle(VelaTheme.rhythmInk)
                }

                Divider()
                    .padding(.horizontal)

                // 2. 主屏小尺寸
                VStack(alignment: .leading, spacing: 10) {
                    Text("主屏小尺寸 (System Small)")
                        .font(VelaTheme.subheadline().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal)

                    VelaSystemSmallWidgetView(snapshot: mockSnapshot)
                        .frame(width: 155, height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                        .padding(.horizontal)
                }

                // 3. 主屏中尺寸
                VStack(alignment: .leading, spacing: 10) {
                    Text("主屏中尺寸 (System Medium)")
                        .font(VelaTheme.subheadline().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal)

                    VelaSystemMediumWidgetView(snapshot: mockSnapshot)
                        .frame(maxWidth: .infinity)
                        .frame(height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                        .padding(.horizontal)
                }

                // 4. 主屏大尺寸
                VStack(alignment: .leading, spacing: 10) {
                    Text("主屏大尺寸 (System Large)")
                        .font(VelaTheme.subheadline().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal)

                    VelaSystemLargeWidgetView(snapshot: mockSnapshot)
                        .frame(maxWidth: .infinity)
                        .frame(height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(VelaTheme.rhythmCanvas)
    }
}

// MARK: - MetricMethodologyCard (Methodology, Data Sources & Limitations)

struct MetricMethodologyCard: View {
    let metric: VelaMetricDetailView.MetricType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("方法与限制")
                .font(VelaTheme.footnote().weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12) {
                methodologyRow(
                    icon: "function",
                    title: "计算方法",
                    detail: methodologyDescription
                )
                Divider()
                    .overlay(VelaTheme.rhythmMist)
                methodologyRow(
                    icon: "lock.shield",
                    title: "数据来源",
                    detail: "直接读取 Apple 健康本机样本，无云端数据上传，离线可用。"
                )
                Divider()
                    .overlay(VelaTheme.rhythmMist)
                methodologyRow(
                    icon: "exclamationmark.triangle",
                    title: "使用限制",
                    detail: "仅作为日常运动与恢复建议参考，不作为医疗诊断依据；基线形成需连续佩戴 Apple Watch。"
                )
            }
            .padding(16)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("metric-detail-methodology")
    }

    private var methodologyDescription: String {
        switch metric {
        case .recovery:
            return "采用夜间 HRV (RMSSD) 与静息心率相对 14–28 天滚动基线的 Z 分数加权，综合评估自主神经平衡状态。"
        case .sleep:
            return "基于 Apple Watch 本机检测的实际睡眠时长（加权 50%）、阶段分布（深睡与 REM 占比加权 30%）以及就寝规律性（加权 20%）综合评分；完全离线计算，仅供日常作息参考，非医疗设备诊断。"
        case .strain:
            return "基于全天心率负荷与运动耗力模型综合累积（0–21 分），评估日间训练与身体消耗水平；支持查看急性与慢性负荷比率。"
        case .stress:
            return "结合静息心率、HRV（RMSSD）以及日间生理指标相对滚动个人基线的瞬时偏离度估算压力水平；日内连续采样取决于 Apple Watch 佩戴测量。"
        case .energy:
            return "基于急性训练负荷 (ATL) 与慢性训练负荷 (CTL) 平衡度估算身体能量储备（0–100 分）；明确标注为计算模型预测值，非直接测量电量事实。"
        default:
            return "结合历史均值与个人基线分析长期偏离趋势。"
        }
    }

    private func methodologyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(detail)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - SleepTimelineCard (U4: Real segments hypnogram, gap preservation, and clear time scale)

struct SleepTimelineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: SleepSummary
    let bedtimeText: String
    let wakeTimeText: String
    let targetBedtimeText: String
    let sleepTargetMinutes: Int
    let hasCompleteSleepTimes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 就寝与起止时间
            rhythmHeader

            Divider().overlay(VelaTheme.rhythmMist)

            // 2. 真实睡眠时间轴（Hypnogram）
            timelineSection

            Divider().overlay(VelaTheme.rhythmMist)

            // 3. 阶段分布与明细
            stageBreakdownSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep-timeline-card")
    }

    // MARK: - Rhythm Header
    private var rhythmHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                sleepTimeFact("入睡", value: hasCompleteSleepTimes ? bedtimeText : "--", symbol: "moon.fill")

                HStack(spacing: 4) {
                    Circle().fill(VelaTheme.sleepColor).frame(width: 6, height: 6)
                    Rectangle().fill(VelaTheme.sleepColor.opacity(0.22)).frame(height: 2)
                    Image(systemName: "arrow.right")
                        .font(VelaTheme.caption2().weight(.bold))
                        .foregroundStyle(VelaTheme.sleepColor)
                }
                .accessibilityHidden(true)

                sleepTimeFact("起床", value: hasCompleteSleepTimes ? wakeTimeText : "--", symbol: "sun.max.fill")
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VelaTheme.sleepColor)
                    Text("实际睡眠 \(summary.totalSleepMinutes > 0 ? VelaMinimalFormatting.duration(minutes: summary.totalSleepMinutes) : "--")")
                        .font(VelaTheme.caption1().weight(.semibold).monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInk)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Text("在床 \(inBedDurationText)")
                        .font(VelaTheme.caption1().monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("计划就寝 \(targetBedtimeText)", systemImage: "calendar")
                    Spacer()
                    Text("目标 \(VelaMinimalFormatting.duration(minutes: sleepTargetMinutes))")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("计划就寝 \(targetBedtimeText)", systemImage: "calendar")
                    Text("目标 \(VelaMinimalFormatting.duration(minutes: sleepTargetMinutes))")
                }
            }
            .font(VelaTheme.caption2())
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
    }

    private var inBedDurationText: String {
        guard let bed = summary.bedtime, let wake = summary.wakeTime else { return "--" }
        var diffMin = Int(wake.timeIntervalSince(bed) / 60)
        if diffMin < 0 { diffMin += 24 * 60 }
        return VelaMinimalFormatting.duration(minutes: diffMin)
    }

    private func sleepTimeFact(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(VelaTheme.caption2().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(value)
                .font(VelaTheme.title3().monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline Section (Hypnogram)
    @ViewBuilder
    private var timelineSection: some View {
        let validSegments = summary.segments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }

        if validSegments.isEmpty {
            VelaStateCard(state: .empty, message: "本晚没有可用的睡眠阶段记录。")
        } else {
            let windowStart = validSegments.first?.start ?? (summary.bedtime ?? Date())
            let windowEnd = validSegments.last?.end ?? (summary.wakeTime ?? Date())
            let totalSpan = max(windowEnd.timeIntervalSince(windowStart), 60)
            let hasStaging = validSegments.contains { $0.stage == .rem || $0.stage == .deep || $0.stage == .core }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(hasStaging ? "睡眠阶段时间轴" : "睡眠时间段")
                        .font(VelaTheme.caption1().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    Text(hasStaging ? "真实阶段采样 · 缺口如实留空" : "未分期 · 仅记录睡眠总段")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }

                if hasStaging {
                    // 4-track hypnogram
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let trackH = h / 4.0

                        ZStack(alignment: .topLeading) {
                            // Track background lines
                            VStack(spacing: 0) {
                                ForEach(0..<4) { i in
                                    Rectangle()
                                        .fill(VelaTheme.rhythmMist.opacity(i % 2 == 0 ? 0.28 : 0.12))
                                        .frame(height: trackH)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            // Draw each segment precisely
                            ForEach(validSegments) { segment in
                                let trackIndex: Int = {
                                    switch segment.stage {
                                    case .awake: return 0
                                    case .rem: return 1
                                    case .core: return 2
                                    case .deep: return 3
                                    case .asleep, .inBed: return 2
                                    }
                                }()
                                let startOffset = max(0, segment.start.timeIntervalSince(windowStart))
                                let endOffset = min(totalSpan, segment.end.timeIntervalSince(windowStart))
                                let startX = CGFloat(startOffset / totalSpan) * w
                                let endX = CGFloat(endOffset / totalSpan) * w
                                let barWidth = max(endX - startX, 2.5)

                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(sleepStageColor(segment.stage))
                                    .frame(width: barWidth, height: trackH - 3)
                                    .offset(x: startX, y: CGFloat(trackIndex) * trackH + 1.5)
                            }
                        }
                    }
                    .frame(height: 64)
                    .accessibilityHidden(true)
                } else {
                    // Unsegmented single track
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(VelaTheme.rhythmMist.opacity(0.3))
                                .frame(height: h)

                            ForEach(validSegments) { segment in
                                if segment.stage.countsTowardSleepDuration {
                                    let startOffset = max(0, segment.start.timeIntervalSince(windowStart))
                                    let endOffset = min(totalSpan, segment.end.timeIntervalSince(windowStart))
                                    let startX = CGFloat(startOffset / totalSpan) * w
                                    let endX = CGFloat(endOffset / totalSpan) * w
                                    let barWidth = max(endX - startX, 3)

                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(VelaTheme.sleepColor)
                                        .frame(width: barWidth, height: h - 4)
                                        .offset(x: startX, y: 2)
                                }
                            }
                        }
                    }
                    .frame(height: 28)
                    .accessibilityHidden(true)
                }

                // Time axis with cross-midnight labels
                HStack {
                    Text(formatTime(windowStart))
                    Spacer()
                    if totalSpan > 3 * 3600 {
                        Text(formatTime(windowStart.addingTimeInterval(totalSpan * 0.33)))
                        Spacer()
                        Text(formatTime(windowStart.addingTimeInterval(totalSpan * 0.66)))
                        Spacer()
                    }
                    Text(formatTime(windowEnd))
                }
                .font(VelaTheme.caption2().monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)

                if !hasStaging {
                    Label("此设备记录了睡眠总时间，未记录 REM / 深睡等阶段估计", systemImage: "info.circle")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(hypnogramAccessibilityLabel(segments: validSegments, start: windowStart, end: windowEnd, hasStaging: hasStaging))
        }
    }

    // MARK: - Stage Breakdown Section
    @ViewBuilder
    private var stageBreakdownSection: some View {
        let validSegments = summary.segments.filter { $0.end > $0.start }
        let hasStaging = validSegments.contains { $0.stage == .rem || $0.stage == .deep || $0.stage == .core }

        if hasStaging {
            VStack(spacing: 8) {
                let orderedStages: [SleepStage] = [.deep, .core, .rem, .awake]
                let total = max(displayedSleepStageTotal, 1)

                ForEach(orderedStages, id: \.self) { stage in
                    let mins = summary.stageMinutes[stage] ?? 0
                    let pct = Int((Double(mins) / Double(total) * 100).rounded())

                    HStack(spacing: 10) {
                        Circle()
                            .fill(sleepStageColor(stage))
                            .frame(width: 8, height: 8)

                        Text(sleepStageLabel(stage))
                            .font(VelaTheme.caption1().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .frame(width: 44, alignment: .leading)

                        Text(stageDescription(stage))
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(mins) 分钟")
                            .font(VelaTheme.caption1().weight(.medium).monospacedDigit())
                            .foregroundStyle(VelaTheme.rhythmInk)

                        Text("(\(pct)%)")
                            .font(VelaTheme.caption2().monospacedDigit())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Circle().fill(VelaTheme.sleepColor).frame(width: 8, height: 8)
                    Text("睡眠时长")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    Text("\(summary.totalSleepMinutes) 分钟")
                        .font(VelaTheme.caption1().monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                HStack(spacing: 10) {
                    Circle().fill(VelaTheme.rhythmInkSecondary).frame(width: 8, height: 8)
                    Text("卧床时长")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    Text(inBedDurationText)
                        .font(VelaTheme.caption1().monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
            }
        }
    }

    private var displayedSleepStageTotal: Int {
        let orderedStages: [SleepStage] = [.awake, .rem, .core, .deep]
        return orderedStages.reduce(0) { $0 + (summary.stageMinutes[$1] ?? 0) }
    }

    private func stageDescription(_ stage: SleepStage) -> String {
        switch stage {
        case .deep: return "身体与免疫恢复"
        case .core: return "日常维持与肌肉放松"
        case .rem: return "大脑与记忆整理"
        case .awake: return "夜间清醒或中断"
        case .asleep: return "睡眠状态"
        case .inBed: return "卧床未眠"
        }
    }

    private func sleepStageLabel(_ stage: SleepStage) -> String {
        switch stage {
        case .awake: return "清醒"
        case .rem: return "REM"
        case .core: return "核心"
        case .deep: return "深睡"
        case .asleep: return "睡眠"
        case .inBed: return "卧床"
        }
    }

    private func sleepStageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return VelaTheme.energyColor
        case .rem: return VelaTheme.sleepColor.opacity(0.72)
        case .core: return VelaTheme.sleepColor
        case .deep: return VelaTheme.rhythmDeep
        case .asleep, .inBed: return VelaTheme.rhythmInkSecondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func hypnogramAccessibilityLabel(
        segments: [SleepStageSegment],
        start: Date,
        end: Date,
        hasStaging: Bool
    ) -> String {
        if hasStaging {
            let deep = summary.stageMinutes[.deep] ?? 0
            let core = summary.stageMinutes[.core] ?? 0
            let rem = summary.stageMinutes[.rem] ?? 0
            let awake = summary.stageMinutes[.awake] ?? 0
            return "睡眠阶段时间轴：入睡 \(formatTime(start))，起床 \(formatTime(end))。实际睡眠 \(VelaMinimalFormatting.duration(minutes: summary.totalSleepMinutes))，在床 \(inBedDurationText)。深睡 \(deep)分钟，核心 \(core)分钟，REM \(rem)分钟，清醒 \(awake)分钟。"
        } else {
            return "睡眠时间轴：入睡 \(formatTime(start))，起床 \(formatTime(end))。实际睡眠 \(VelaMinimalFormatting.duration(minutes: summary.totalSleepMinutes))，在床 \(inBedDurationText)，未分期。"
        }
    }
}

