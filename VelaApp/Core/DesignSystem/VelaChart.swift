import SwiftUI

// MARK: - Canonical metric score ring

struct VelaMetricScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let score: Double?
    let label: String
    let domain: VelaMetricDomain
    var size: CGFloat = VelaTheme.ringMd
    var accent: Color? = nil
    var targetRange: ClosedRange<Double>? = nil
    var allowsOverflow = false
    var showsLabel = true
    var direction: String? = nil
    var confidence: String? = nil
    var dataState: String? = nil

    @State private var animatedProgress = 0.0

    private var clampedProgress: Double {
        guard let score else { return 0 }
        return min(max(score / 100, 0), 1)
    }

    private var overflowProgress: Double {
        guard allowsOverflow, let score, score > 100 else { return 0 }
        return min((score - 100) / 100, 1)
    }

    private var valueText: String {
        score.map { String(Int($0.rounded())) } ?? "--"
    }

    var body: some View {
        VStack(spacing: showsLabel ? 8 : 0) {
            ZStack {
                Circle()
                    .stroke(
                        score == nil
                            ? VelaTheme.rhythmMist
                            : effectiveColor.opacity(0.14),
                        style: StrokeStyle(
                            lineWidth: ringWidth,
                            lineCap: .round,
                            dash: score == nil ? [4, 6] : []
                        )
                    )

                if let targetRange {
                    Circle()
                        .trim(
                            from: min(max(targetRange.lowerBound / 100, 0), 1),
                            to: min(max(targetRange.upperBound / 100, 0), 1)
                        )
                        .stroke(
                            effectiveColor.opacity(0.24),
                            style: StrokeStyle(lineWidth: ringWidth + 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                if score != nil {
                    Circle()
                        .trim(from: 0, to: max(0.006, animatedProgress))
                        .stroke(
                            AngularGradient(
                                colors: [effectiveColor.opacity(0.58), effectiveColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    if overflowProgress > 0 {
                        Circle()
                            .trim(from: 0, to: overflowProgress)
                            .stroke(
                                VelaTheme.danger,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .padding(-6)
                    }
                }

                Text(valueText)
                    .font(valueFont)
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, ringWidth + 3)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)

            if showsLabel {
                Text(label)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear(perform: animateToCurrentScore)
        .onChange(of: score) { _, _ in animateToCurrentScore() }
    }

    private var ringWidth: CGFloat {
        max(5, (size * 0.065).rounded())
    }

    /// Semantic text styles keep score numerals responsive to Dynamic Type.
    /// The ring's fixed geometry remains the final constraint, with a small
    /// minimum scale factor preventing the value from colliding with its arc.
    private var valueFont: Font {
        if size <= VelaTheme.ringSm + 10 {
            return .system(.footnote, design: .default, weight: .semibold)
        }
        if size <= VelaTheme.ringMd + 6 {
            return .system(.title3, design: .default, weight: .semibold)
        }
        return .system(.title, design: .default, weight: .semibold)
    }

    private var effectiveColor: Color {
        accent ?? domain.color
    }

    private var accessibilitySummary: String {
        var parts = [label, score.map { "\(Int($0.rounded()))分" } ?? "暂无数据"]
        if let direction, !direction.isEmpty { parts.append(direction) }
        if let confidence, !confidence.isEmpty { parts.append(confidence) }
        if let dataState, !dataState.isEmpty { parts.append(dataState) }
        return parts.joined(separator: "，")
    }

    private func animateToCurrentScore() {
        if reduceMotion {
            animatedProgress = clampedProgress
        } else {
            withAnimation(VelaTheme.dataAnimation(reduceMotion: false)) {
                animatedProgress = clampedProgress
            }
        }
    }
}

// MARK: - Canonical stage and event timelines

struct VelaTimelineItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    var systemImage: String = "circle.fill"
    var domain: VelaMetricDomain = .neutral
}

struct VelaTimelineCard: View {
    let items: [VelaTimelineItem]
    var emptyMessage = "此期间没有记录到活动。"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: VelaDataPresentationState.empty.systemImage)
                        .foregroundStyle(VelaTheme.muted)
                        .accessibilityHidden(true)
                    Text(emptyMessage)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.fg2)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(emptyMessage)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VelaTimelineItemRow(
                        item: item,
                        showsConnector: index < items.count - 1
                    )
                }
            }
        }
        .padding(VelaTheme.compactCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }
}

private struct VelaTimelineItemRow: View {
    let item: VelaTimelineItem
    let showsConnector: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: item.systemImage)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(item.domain.color)
                    .frame(width: 32, height: 32)
                    .background(item.domain.color.opacity(0.10), in: Circle())

                if showsConnector {
                    Rectangle()
                        .fill(VelaTheme.rhythmMist)
                        .frame(width: 1.5)
                        .frame(minHeight: 18)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(item.subtitle)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title + "，" + item.subtitle)
    }
}

enum VelaStageKind: String {
    case awake
    case core
    case deep
    case rem

    var color: Color {
        switch self {
        case .awake: VelaTheme.warn
        case .core: VelaTheme.sleepColor.opacity(0.70)
        case .deep: VelaTheme.sleepColor
        case .rem: Color(uiColor: .systemCyan)
        }
    }
}

struct VelaStageInterval: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let stage: VelaStageKind
}

enum VelaStageTimelineLayout {
    static func normalizedRange(
        interval: VelaStageInterval,
        window: DateInterval
    ) -> ClosedRange<Double>? {
        guard window.duration > 0, interval.end > interval.start else { return nil }
        let lower = min(max(interval.start.timeIntervalSince(window.start) / window.duration, 0), 1)
        let upper = min(max(interval.end.timeIntervalSince(window.start) / window.duration, 0), 1)
        guard upper > lower else { return nil }
        return lower...upper
    }
}

struct VelaStageTimeline: View {
    let intervals: [VelaStageInterval]
    let window: DateInterval

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(VelaTheme.secondaryGroupedBackground)

                ForEach(intervals) { interval in
                    if let range = VelaStageTimelineLayout.normalizedRange(
                        interval: interval,
                        window: window
                    ) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(interval.stage.color)
                            .frame(width: max(2, geometry.size.width * (range.upperBound - range.lowerBound)))
                            .offset(x: geometry.size.width * range.lowerBound)
                    }
                }
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("睡眠阶段时间线")
        .accessibilityValue(intervals.isEmpty ? "暂无阶段数据" : "包含\(intervals.count)个真实阶段区间")
    }
}

// MARK: - ScoreRing (Ring progress view)

// MARK: - Bevel Score Ring (Bevel-style circular gauge)

struct BevelScoreRing: View {
    let score: Double // 0 to 1
    let color: Color
    var useGradient: Bool = false
    var size: CGFloat = 80
    let label: String
    let valueText: String

    var body: some View {
        VelaMetricScoreRing(
            score: valueText == "--" ? nil : score * 100,
            label: label,
            domain: .neutral,
            size: size,
            accent: color,
            showsLabel: !label.isEmpty
        )
    }
}

// MARK: - Dotted Circle Gauge (Bevel-style circular tick gauge)

struct DottedCircleGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let score: Double // 0 to 100
    let labelText: String // e.g. "低"
    var size: CGFloat = 72
    let color: Color

    @State private var animatedScore: Double = 0.0

    var body: some View {
        ZStack {
            // Dotted circle track
            Circle()
                .stroke(VelaTheme.rhythmMist, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [1.5, 4]))
                .frame(width: size, height: size)
            
            // Colored active dots matching score
            Circle()
                .trim(from: 0, to: max(0.02, animatedScore / 100.0))
                .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [1.5, 4]))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
            
            VStack(spacing: 1) {
                Text("\(Int(animatedScore))")
                    .font(.system(.title3, design: .default, weight: .semibold).monospacedDigit())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(labelText)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animatedScore = score
            }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animatedScore = newScore
            }
        }
    }
}

// MARK: - Segmented Battery Bar (Bevel-style segmented horizontal bar)

struct SegmentedBatteryBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let percentage: Double // 0 to 1
    var barCount: Int = 26
    let color: Color

    @State private var animatedPercentage: Double = 0.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { idx in
                let activeCount = Int(animatedPercentage * Double(barCount))
                RoundedRectangle(cornerRadius: 1)
                    .fill(idx < activeCount ? color : VelaTheme.rhythmMist)
                    .frame(width: 4, height: 14)
            }
        }
        .onAppear {
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animatedPercentage = percentage
            }
        }
        .onChange(of: percentage) { _, newPercentage in
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animatedPercentage = newPercentage
            }
        }
    }
}

// MARK: - Sparkline Line Graph (Bevel-style biomarker sparkline)

struct SparklineLineGraph: View {
    let data: [Double] // Normalized 0...1 values
    let color: Color
    var height: CGFloat = 36
    var width: CGFloat = 80

    var body: some View {
        if data.isEmpty {
            Color.clear.frame(width: width, height: height)
        } else {
            ZStack {
                // Shaded area
                Path { path in
                    guard data.count > 1 else { return }
                    let stepX = width / CGFloat(data.count - 1)
                    path.move(to: CGPoint(x: 0, y: height))
                    for idx in 0..<data.count {
                         let x = CGFloat(idx) * stepX
                         let y = height - (CGFloat(data[idx]) * (height - 6) + 3)
                         path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.12), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Line Path
                Path { path in
                    guard data.count > 1 else { return }
                    let stepX = width / CGFloat(data.count - 1)
                    for idx in 0..<data.count {
                        let x = CGFloat(idx) * stepX
                        let y = height - (CGFloat(data[idx]) * (height - 6) + 3)
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                
                // End Dot
                if data.count > 1, let lastVal = data.last {
                    let stepX = width / CGFloat(data.count - 1)
                    let x = CGFloat(data.count - 1) * stepX
                    let y = height - (CGFloat(lastVal) * (height - 6) + 3)
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .position(x: x, y: y)
                }
            }
            .frame(width: width, height: height)
        }
    }
}

// MARK: - DateAwareSparkline (U5: Truthful date-spaced sparkline preserving missing day gaps)

struct DateAwareSparkline: View {
    let points: [TrendsChartPoint]
    let color: Color
    var height: CGFloat = 36
    var width: CGFloat = 80

    var body: some View {
        let nonNilPoints = points.filter { $0.value != nil }
        if nonNilPoints.isEmpty {
            Capsule()
                .fill(VelaTheme.rhythmMist)
                .frame(width: width, height: 2)
        } else if nonNilPoints.count == 1, let single = nonNilPoints.first, let _ = single.value {
            // Single point: render a single distinct dot at normalized date position
            let xRatio: CGFloat = {
                guard let first = points.first?.date, let last = points.last?.date, last > first else { return 0.5 }
                return CGFloat(single.date.timeIntervalSince(first) / last.timeIntervalSince(first))
            }()
            let y = height * 0.5
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .position(x: max(3, min(width - 3, xRatio * width)), y: y)
                .frame(width: width, height: height)
        } else {
            let values = nonNilPoints.compactMap(\.value)
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 100
            let range = max(maxVal - minVal, 1.0)

            let firstDate = points.first?.date ?? Date()
            let lastDate = points.last?.date ?? Date()
            let totalSpan = max(lastDate.timeIntervalSince(firstDate), 1.0)

            let segments: [[TrendsChartPoint]] = {
                var segs: [[TrendsChartPoint]] = []
                var cur: [TrendsChartPoint] = []
                for pt in points {
                    if pt.value != nil {
                        cur.append(pt)
                    } else if !cur.isEmpty {
                        segs.append(cur)
                        cur = []
                    }
                }
                if !cur.isEmpty { segs.append(cur) }
                return segs
            }()

            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if seg.count == 1, let pt = seg.first, let v = pt.value {
                        let x = CGFloat(pt.date.timeIntervalSince(firstDate) / totalSpan) * width
                        let norm = (v - minVal) / range
                        let y = height - (CGFloat(norm) * (height - 8) + 4)
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .position(x: max(3, min(width - 3, x)), y: y)
                    } else if seg.count > 1 {
                        // Shaded area under this segment
                        Path { path in
                            guard let firstPt = seg.first, let firstV = firstPt.value else { return }
                            let firstX = CGFloat(firstPt.date.timeIntervalSince(firstDate) / totalSpan) * width
                            let firstNorm = (firstV - minVal) / range
                            let firstY = height - (CGFloat(firstNorm) * (height - 8) + 4)

                            path.move(to: CGPoint(x: firstX, y: height))
                            path.addLine(to: CGPoint(x: firstX, y: firstY))

                            for pt in seg.dropFirst() {
                                guard let v = pt.value else { continue }
                                let x = CGFloat(pt.date.timeIntervalSince(firstDate) / totalSpan) * width
                                let norm = (v - minVal) / range
                                let y = height - (CGFloat(norm) * (height - 8) + 4)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }

                            if let lastPt = seg.last {
                                let lastX = CGFloat(lastPt.date.timeIntervalSince(firstDate) / totalSpan) * width
                                path.addLine(to: CGPoint(x: lastX, y: height))
                            }
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.14), color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Line
                        Path { path in
                            for (idx, pt) in seg.enumerated() {
                                guard let v = pt.value else { continue }
                                let x = CGFloat(pt.date.timeIntervalSince(firstDate) / totalSpan) * width
                                let norm = (v - minVal) / range
                                let y = height - (CGFloat(norm) * (height - 8) + 4)
                                if idx == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(width: width, height: height)
        }
    }
}

// MARK: - TripleConcentricScoreRing (Concentric Recovery/Sleep/Strain activity-style rings)

struct TripleConcentricScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let recovery: Double // 0...1
    let sleep: Double    // 0...1
    let strain: Double   // 0...1
    
    @State private var animRecovery: Double = 0.0
    @State private var animSleep: Double = 0.0
    @State private var animStrain: Double = 0.0
    
    var body: some View {
        ZStack {
            // Blurred depth glow backing
            RadialGradient(
                colors: [
                    VelaTheme.recoveryColor.opacity(0.12),
                    VelaTheme.sleepColor.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 50
            )
            .frame(width: 100, height: 100)
            .blur(radius: 6)

            // Recovery (Outer)
            Circle()
                .stroke(VelaTheme.recoveryColor.opacity(0.12), lineWidth: 8.5)
                .frame(width: 100, height: 100)
            Circle()
                .trim(from: 0, to: max(0.01, animRecovery))
                .stroke(
                    VelaTheme.recoveryColor.gradient,
                    style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 100, height: 100)
                .shadow(color: VelaTheme.recoveryColor.opacity(0.25), radius: 2)
            
            // Sleep (Middle)
            Circle()
                .stroke(VelaTheme.sleepColor.opacity(0.12), lineWidth: 8.5)
                .frame(width: 78, height: 78)
            Circle()
                .trim(from: 0, to: max(0.01, animSleep))
                .stroke(
                    VelaTheme.sleepColor.gradient,
                    style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 78, height: 78)
                .shadow(color: VelaTheme.sleepColor.opacity(0.25), radius: 2)
            
            // Strain (Inner)
            Circle()
                .stroke(VelaTheme.strainColor.opacity(0.12), lineWidth: 8.5)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: max(0.01, animStrain))
                .stroke(
                    VelaTheme.strainColor.gradient,
                    style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
                .shadow(color: VelaTheme.strainColor.opacity(0.25), radius: 2)
        }
        .onAppear {
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animRecovery = recovery
                animSleep = sleep
                animStrain = strain
            }
        }
        .onChange(of: recovery) { _, newRecovery in
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) { animRecovery = newRecovery }
        }
        .onChange(of: sleep) { _, newSleep in
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) { animSleep = newSleep }
        }
        .onChange(of: strain) { _, newStrain in
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) { animStrain = newStrain }
        }
    }
}

// MARK: - MiniMetricRow (Row showing inline indicator bars for triple rings)

struct MiniMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double // 0...1
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(Circle().fill(color.opacity(0.12)))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label)
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                    Spacer()
                    Text(value)
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                // Capsule Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(VelaTheme.borderSoft)
                            .frame(height: 5)
                        
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(progress), height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.vertical, 3)
    }
}
