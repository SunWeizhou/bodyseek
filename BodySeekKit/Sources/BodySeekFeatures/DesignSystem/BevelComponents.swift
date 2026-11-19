import BodySeekCore
import Liveline
import SleepChartKit
import SwiftUI

public struct BevelCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(BevelTheme.hairline.opacity(0.55), lineWidth: 0.5)
            )
    }
}

/// Full-bleed atmospheric `MeshGradient` extending behind navigation bar and header, feathering smoothly into canvas.
public struct BevelAmbientAura: View {
    public let recoveryScore: Int?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    public init(recoveryScore: Int?) {
        self.recoveryScore = recoveryScore
    }

    public var body: some View {
        let baseAlpha = colorScheme == .dark ? 0.16 : 0.10
        let tint: Color = switch recoveryScore {
        case .some(75...): BevelTheme.recoveryColor
        case .some(50..<75): BevelTheme.brand
        case .some: BevelTheme.strainColor
        case .none: BevelTheme.sleepColor
        }
        let shift = Float(reduceMotion ? 0 : sin(phase) * 0.06)

        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5 + shift, 0.0], [1.0, 0.0],
                [0.0, 0.45], [0.5 - shift, 0.42 + shift], [1.0, 0.45],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                tint.opacity(baseAlpha), tint.opacity(baseAlpha * 0.65), BevelTheme.canvas,
                tint.opacity(baseAlpha * 0.35), BevelTheme.sleepColor.opacity(baseAlpha * 0.25), BevelTheme.canvas,
                BevelTheme.canvas, BevelTheme.canvas, BevelTheme.canvas,
            ]
        )
        .frame(height: 360)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }
}

public struct MetricRingView: View {
    public let score: MetricScore
    public let diameter: CGFloat
    public let lineWidth: CGFloat

    public init(score: MetricScore, diameter: CGFloat = 88, lineWidth: CGFloat = 9) {
        self.score = score
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let tint = BevelTheme.color(for: score.kind)
        let progress = Double(score.value ?? 0) / 100.0

        ZStack {
            Circle()
                .stroke(BevelTheme.scoreTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: score.value == nil ? 0 : progress)
                .stroke(
                    tint.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.65, bounce: 0.15), value: score.value)
            Text(score.formattedScore)
                .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(score.value == nil ? BevelTheme.inkSecondary : BevelTheme.ink)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Liveline Open-Source Visualizations

enum BodySeekChartFormatting {
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func monthDay(_ timestamp: TimeInterval) -> String {
        monthDayFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func hour(_ timestamp: TimeInterval) -> String {
        hourFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func livelinePoints(from items: [(date: Date, value: Double?)]) -> [LivelinePoint] {
        items.compactMap { item in
            guard let val = item.value, val.isFinite else { return nil }
            return LivelinePoint(time: item.date.timeIntervalSince1970, value: val)
        }
        .sorted { $0.time < $1.time }
    }

    static func span(for points: [LivelinePoint], minimumSpan: TimeInterval = 24 * 3600) -> TimeInterval {
        guard let first = points.first?.time, let last = points.last?.time else { return minimumSpan }
        return max(minimumSpan, (last - first) * 1.04)
    }
}

/// Clean sparkline powered by `Liveline` monotone cubic Canvas renderer.
public struct MetricSparklineChart: View {
    public let points: [(date: Date, value: Double?)]
    public let tint: Color
    public let baselineRange: ClosedRange<Double>?
    public let height: CGFloat

    public init(
        points: [(date: Date, value: Double?)],
        tint: Color,
        baselineRange: ClosedRange<Double>? = nil,
        height: CGFloat = 44
    ) {
        self.points = points
        self.tint = tint
        self.baselineRange = baselineRange
        self.height = height
    }

    public var body: some View {
        let livelinePts = BodySeekChartFormatting.livelinePoints(from: points)
        if livelinePts.count < 2 {
            dashedPlaceholder
                .frame(height: height)
        } else {
            let latest = livelinePts.last?.value ?? 0
            let bands: [LivelineReferenceBand] = baselineRange.map {
                [LivelineReferenceBand(axis: .value, start: $0.lowerBound, end: $0.upperBound, label: nil, color: tint, opacity: 0.08)]
            } ?? []
            let config = LivelineChartConfiguration(
                appearance: LivelineChartAppearance(
                    theme: .automatic,
                    grid: false,
                    fill: true,
                    lineWidth: 2.0,
                    showValue: false,
                    padding: LivelinePadding(top: 5, right: 3, bottom: 3, left: 3)
                ),
                effects: LivelineChartEffects(
                    badge: false,
                    pulse: false,
                    endpointDecorations: true,
                    fadeEffects: false,
                    tooltipOutline: false
                ),
                viewport: LivelineChartViewport(
                    window: BodySeekChartFormatting.span(for: livelinePts),
                    exaggerate: true
                ),
                interaction: LivelineChartInteraction(
                    scrub: false,
                    showsTooltipOnHover: false,
                    showsModeControls: false,
                    showsSeriesControls: false
                ),
                motion: LivelineChartMotion(paused: true, lerpSpeed: 1.0),
                annotations: LivelineChartAnnotations(
                    autoDetectMomentum: false,
                    referenceBands: bands
                ),
                formatting: LivelineChartFormatting(
                    value: { "\(Int($0.rounded()))" },
                    time: { _ in "" }
                )
            )
            LivelineChart(data: livelinePts, value: latest, color: tint, configuration: config)
                .frame(height: height)
                .clipped()
        }
    }

    private var dashedPlaceholder: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.4))
        }
    }
}

/// Interactive single-metric trend chart powered by `Liveline` with personal IQR band & touch scrub tooltip.
public struct BevelMetricTrendChart: View {
    public let series: TrendSeries
    public let tint: Color
    @Binding public var selectedDate: Date?

    public init(series: TrendSeries, tint: Color, selectedDate: Binding<Date?>) {
        self.series = series
        self.tint = tint
        self._selectedDate = selectedDate
    }

    public var body: some View {
        let livelinePts: [LivelinePoint] = series.points.compactMap { pt in
            guard let val = pt.value else { return nil }
            return LivelinePoint(time: pt.date.timeIntervalSince1970, value: Double(val))
        }

        if livelinePts.count < 2 {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(BevelTheme.inkSecondary)
                Text("当前时间窗口内暂无可绘制趋势")
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 196)
        } else {
            let latest = livelinePts.last?.value ?? 0
            let bands: [LivelineReferenceBand] = series.baselineRange.map {
                [LivelineReferenceBand(axis: .value, start: $0.lowerBound, end: $0.upperBound, label: nil, color: tint, opacity: 0.09)]
            } ?? []
            let lines: [LivelineReferenceLine] = series.median.map {
                [LivelineReferenceLine(value: Double($0), axis: .value, label: nil, color: BevelTheme.inkSecondary.opacity(0.32), dash: .dashed)]
            } ?? []

            let config = LivelineChartConfiguration(
                appearance: LivelineChartAppearance(
                    theme: .automatic,
                    grid: true,
                    fill: true,
                    lineWidth: 2.3,
                    showValue: false,
                    padding: LivelinePadding(top: 12, right: nil, bottom: nil, left: 6)
                ),
                effects: LivelineChartEffects(
                    badge: false,
                    pulse: false,
                    endpointDecorations: true,
                    fadeEffects: false,
                    tooltipOutline: true
                ),
                viewport: LivelineChartViewport(
                    window: BodySeekChartFormatting.span(for: livelinePts),
                    exaggerate: true
                ),
                interaction: LivelineChartInteraction(
                    scrub: true,
                    showsTooltipOnHover: true,
                    showsModeControls: false,
                    showsSeriesControls: false
                ),
                motion: LivelineChartMotion(paused: true, lerpSpeed: 1.0),
                annotations: LivelineChartAnnotations(
                    autoDetectMomentum: false,
                    referenceLines: lines,
                    referenceBands: bands
                ),
                formatting: LivelineChartFormatting(
                    value: { "\(Int($0.rounded()))" },
                    time: { BodySeekChartFormatting.monthDay($0) }
                ),
                callbacks: LivelineChartCallbacks(
                    onHover: { hover in
                        let nextDate = hover.map { Date(timeIntervalSince1970: $0.time) }
                        if selectedDate != nextDate {
                            selectedDate = nextDate
                        }
                    }
                )
            )

            LivelineChart(data: livelinePts, value: latest, color: tint, configuration: config)
                .frame(height: 204)
                .bodyseekSelectionHaptic(trigger: selectedDate)
        }
    }
}

/// High-fidelity Apple Health staircase sleep timeline powered by `DanielJamesTronca/SleepChartKit`.
public struct SleepStageTimelineView: View {
    public let segments: [SleepStageSegment]
    public let height: CGFloat

    public init(segments: [SleepStageSegment], height: CGFloat = 148) {
        self.segments = segments
        self.height = height
    }

    public var body: some View {
        let samples: [SleepChartKit.SleepSample] = segments.map { seg in
            let kitStage: SleepChartKit.SleepStage = switch seg.stage {
            case .awake: .awake
            case .rem: .asleepREM
            case .core: .asleepCore
            case .deep: .asleepDeep
            }
            return SleepChartKit.SleepSample(stage: kitStage, startDate: seg.startDate, endDate: seg.endDate)
        }

        if samples.isEmpty {
            Text("昨晚暂无睡眠分期片段")
                .font(.footnote)
                .foregroundStyle(BevelTheme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SleepChartView(
                samples: samples,
                style: .timeline,
                colorProvider: BodySeekSleepColorProvider(),
                displayNameProvider: CustomSleepStageDisplayNameProvider(customNames: [
                    .awake: "清醒",
                    .asleepREM: "REM",
                    .asleepCore: "核心",
                    .asleepDeep: "深睡",
                ])
            )
            .frame(height: height)
        }
    }
}

private struct BodySeekSleepColorProvider: SleepStageColorProvider {
    func color(for stage: SleepChartKit.SleepStage) -> Color {
        switch stage {
        case .awake: BevelTheme.sleepStageColor(.awake)
        case .asleepREM: BevelTheme.sleepStageColor(.rem)
        case .asleepCore: BevelTheme.sleepStageColor(.core)
        case .asleepDeep: BevelTheme.sleepStageColor(.deep)
        case .asleepUnspecified: BevelTheme.sleepColor
        case .inBed: BevelTheme.inkSecondary.opacity(0.35)
        }
    }
}

/// 24-hour autonomic stress bar chart powered by `Liveline`.
public struct StressHeatmapChart: View {
    public let bins: [StressTimelineBin]
    public let height: CGFloat
    public let interactive: Bool

    public init(bins: [StressTimelineBin], height: CGFloat = 34, interactive: Bool = false) {
        self.bins = bins
        self.height = height
        self.interactive = interactive
    }

    public var body: some View {
        if bins.isEmpty {
            RoundedRectangle(cornerRadius: 6)
                .fill(BevelTheme.scoreTrack)
                .frame(height: height)
        } else {
            let baseDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            let barPoints = bins.sorted { $0.hour < $1.hour }.map { bin in
                LivelinePoint(time: baseDay + Double(bin.hour) * 3600, value: Double(bin.value))
            }
            let config = LivelineChartConfiguration(
                appearance: LivelineChartAppearance(
                    theme: .automatic,
                    grid: interactive,
                    fill: true,
                    showValue: false,
                    padding: LivelinePadding(
                        top: interactive ? 8 : 4,
                        right: interactive ? nil : 4,
                        bottom: interactive ? nil : 2,
                        left: 4
                    )
                ),
                effects: LivelineChartEffects(badge: false, pulse: false, endpointDecorations: false),
                viewport: LivelineChartViewport(window: 24 * 3600, exaggerate: false),
                interaction: LivelineChartInteraction(
                    scrub: interactive,
                    showsTooltipOnHover: interactive,
                    showsModeControls: false,
                    showsSeriesControls: false
                ),
                motion: LivelineChartMotion(paused: true, lerpSpeed: 1.0),
                annotations: LivelineChartAnnotations(autoDetectMomentum: false),
                formatting: LivelineChartFormatting(
                    value: { "\(Int($0.rounded()))" },
                    time: { interactive ? BodySeekChartFormatting.hour($0) : "" }
                )
            )
            LivelineChart(
                bars: barPoints,
                color: BevelTheme.stressColor,
                style: LivelineBarStyle(
                    widthRatio: 0.65,
                    cornerRadius: 3,
                    baseline: 0,
                    positiveColor: BevelTheme.stressColor,
                    showsBaseline: false
                ),
                configuration: config
            )
            .frame(height: height)
            .clipped()
        }
    }
}

/// Circadian recharge & discharge curve for Energy / Body Battery powered by `Liveline`.
public struct EnergyBatteryCurveChart: View {
    public let curve: [EnergyCurvePoint]
    public let height: CGFloat
    public let interactive: Bool

    public init(curve: [EnergyCurvePoint], height: CGFloat = 34, interactive: Bool = false) {
        self.curve = curve
        self.height = height
        self.interactive = interactive
    }

    public var body: some View {
        let livelinePts = curve.sorted { $0.hour < $1.hour }.map {
            LivelinePoint(time: $0.date.timeIntervalSince1970, value: Double($0.value))
        }
        if livelinePts.count < 2 {
            RoundedRectangle(cornerRadius: 6)
                .fill(BevelTheme.scoreTrack)
                .frame(height: height)
        } else {
            let latest = livelinePts.last?.value ?? 50
            let config = LivelineChartConfiguration(
                appearance: LivelineChartAppearance(
                    theme: .automatic,
                    grid: interactive,
                    fill: true,
                    lineWidth: 2.0,
                    showValue: false,
                    padding: LivelinePadding(
                        top: interactive ? 8 : 5,
                        right: interactive ? nil : 4,
                        bottom: interactive ? nil : 2,
                        left: 4
                    )
                ),
                effects: LivelineChartEffects(
                    badge: false,
                    pulse: false,
                    endpointDecorations: interactive,
                    fadeEffects: false
                ),
                viewport: LivelineChartViewport(
                    window: BodySeekChartFormatting.span(for: livelinePts, minimumSpan: 12 * 3600),
                    exaggerate: true
                ),
                interaction: LivelineChartInteraction(
                    scrub: interactive,
                    showsTooltipOnHover: interactive,
                    showsModeControls: false,
                    showsSeriesControls: false
                ),
                motion: LivelineChartMotion(paused: true, lerpSpeed: 1.0),
                annotations: LivelineChartAnnotations(autoDetectMomentum: false),
                formatting: LivelineChartFormatting(
                    value: { "\(Int($0.rounded()))%" },
                    time: { interactive ? BodySeekChartFormatting.hour($0) : "" }
                )
            )
            LivelineChart(
                data: livelinePts,
                value: latest,
                color: BevelTheme.energyColor,
                configuration: config
            )
            .frame(height: height)
            .clipped()
        }
    }
}

/// Multi-series Recovery vs Strain relationship chart powered by `Liveline` Canvas renderer.
public struct DualAxisLoadRecoveryChart: View {
    public let days: [DailyComputedDay]
    @Binding public var selectedDate: Date?

    public init(days: [DailyComputedDay], selectedDate: Binding<Date?>) {
        self.days = days
        self._selectedDate = selectedDate
    }

    public var body: some View {
        let recoveryPts: [LivelinePoint] = days.compactMap { day in
            guard let val = day.recovery.value else { return nil }
            return LivelinePoint(time: day.date.timeIntervalSince1970, value: Double(val))
        }
        let strainPts: [LivelinePoint] = days.compactMap { day in
            guard let val = day.strain.value else { return nil }
            return LivelinePoint(time: day.date.timeIntervalSince1970, value: Double(val))
        }

        if recoveryPts.count < 2 && strainPts.count < 2 {
            Text("暂无负荷与恢复对照数据")
                .font(.footnote)
                .foregroundStyle(BevelTheme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 185)
        } else {
            let series: [LivelineSeries] = [
                LivelineSeries(
                    id: "recovery",
                    data: recoveryPts,
                    value: recoveryPts.last?.value ?? 0,
                    color: BevelTheme.recoveryColor,
                    label: "恢复"
                ),
                LivelineSeries(
                    id: "strain",
                    data: strainPts,
                    value: strainPts.last?.value ?? 0,
                    color: BevelTheme.strainColor,
                    label: "负荷"
                ),
            ].filter { !$0.data.isEmpty }

            let allPts = (recoveryPts + strainPts).sorted { $0.time < $1.time }
            let config = LivelineChartConfiguration(
                appearance: LivelineChartAppearance(
                    theme: .automatic,
                    grid: true,
                    fill: false,
                    lineWidth: 2.2,
                    showValue: false,
                    padding: LivelinePadding(top: 10, right: nil, bottom: nil, left: 6)
                ),
                effects: LivelineChartEffects(badge: false, pulse: false, endpointDecorations: true),
                viewport: LivelineChartViewport(
                    window: BodySeekChartFormatting.span(for: allPts),
                    exaggerate: true
                ),
                interaction: LivelineChartInteraction(
                    scrub: true,
                    showsTooltipOnHover: true,
                    seriesToggleCompact: false,
                    seriesLegendSide: .leading,
                    showsModeControls: false,
                    showsSeriesControls: true
                ),
                motion: LivelineChartMotion(paused: true, lerpSpeed: 1.0),
                annotations: LivelineChartAnnotations(autoDetectMomentum: false),
                formatting: LivelineChartFormatting(
                    value: { "\(Int($0.rounded()))" },
                    time: { BodySeekChartFormatting.monthDay($0) }
                ),
                callbacks: LivelineChartCallbacks(
                    onHover: { hover in
                        let nextDate = hover.map { Date(timeIntervalSince1970: $0.time) }
                        if selectedDate != nextDate {
                            selectedDate = nextDate
                        }
                    }
                )
            )

            LivelineChart(series: series, configuration: config)
                .frame(height: 196)
                .bodyseekSelectionHaptic(trigger: selectedDate)
        }
    }
}

/// Color-coded stacked bar for Apple Watch Workout Heart Rate Zones 1–5.
public struct WatchHeartRateZonesBar: View {
    public let zones: WorkoutHeartRateZones

    public init(zones: WorkoutHeartRateZones) {
        self.zones = zones
    }

    public var body: some View {
        let total = max(1, Double(zones.totalZoneMinutes))
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(zones.zone1Minutes, total: total, width: geo.size.width, color: .gray.opacity(0.5))
                    segment(zones.zone2Minutes, total: total, width: geo.size.width, color: BevelTheme.infoBlue)
                    segment(zones.zone3Minutes, total: total, width: geo.size.width, color: BevelTheme.recoveryColor)
                    segment(zones.zone4Minutes, total: total, width: geo.size.width, color: BevelTheme.energyColor)
                    segment(zones.zone5Minutes, total: total, width: geo.size.width, color: BevelTheme.stressColor)
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                zoneTag("Z2", zones.zone2Minutes, color: BevelTheme.infoBlue)
                zoneTag("Z3", zones.zone3Minutes, color: BevelTheme.recoveryColor)
                zoneTag("Z4", zones.zone4Minutes, color: BevelTheme.energyColor)
                zoneTag("Z5", zones.zone5Minutes, color: BevelTheme.stressColor)
            }
        }
    }

    @ViewBuilder
    private func segment(_ mins: Int, total: Double, width: CGFloat, color: Color) -> some View {
        if mins > 0 {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: max(4, width * CGFloat(Double(mins) / total)))
        }
    }

    private func zoneTag(_ label: String, _ mins: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(mins)分")
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
        }
    }
}

/// Custom vector organic illustration shown when HealthKit is unauthorized or empty.
public struct ReadinessEmptyIllustration: View {
    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .stroke(BevelTheme.brand.opacity(0.14), lineWidth: 12)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0.1, to: 0.72)
                .stroke(BevelTheme.sleepColor.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-25))
            BodySeekBrandMark(size: 30)
        }
    }
}
