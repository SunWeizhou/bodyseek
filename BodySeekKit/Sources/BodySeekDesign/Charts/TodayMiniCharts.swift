import BodySeekCore
import SwiftUI

/// 折线 + 浅色面积 + 末端圆点的迷你图（恢复 7 天、能量曲线共用）。缺失值断开。
public struct MiniAreaLine: View {
    private let values: [Double?]
    private let tint: Color
    private let domain: ClosedRange<Double>?

    /// 创建迷你面积折线。
    /// - Parameters:
    ///   - values: 按时间排列的值；`nil` 表示缺失，线在此断开。
    ///   - tint: 领域色。
    ///   - domain: 固定纵轴范围；为 `nil` 时取数据的最小到最大。
    public init(values: [Double?], tint: Color, domain: ClosedRange<Double>? = nil) {
        self.values = values
        self.tint = tint
        self.domain = domain
    }

    public var body: some View {
        Canvas { context, size in
            let inset = BSSize.dot / 2
            let points = Self.points(values: values, domain: domain, size: size, inset: inset)
            for run in Self.runs(points) {
                draw(run, in: &context, height: size.height)
            }
            if let last = points.compactMap({ $0 }).last {
                let rect = CGRect(
                    x: last.x - inset, y: last.y - inset, width: BSSize.dot, height: BSSize.dot
                )
                context.fill(Path(ellipseIn: rect), with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ run: [CGPoint], in context: inout GraphicsContext, height: CGFloat) {
        guard let first = run.first, let last = run.last else { return }
        var line = Path()
        line.move(to: first)
        for point in run.dropFirst() {
            line.addLine(to: point)
        }
        if run.count >= 2 {
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: height))
            area.addLine(to: CGPoint(x: first.x, y: height))
            area.closeSubpath()
            context.fill(area, with: .color(tint.opacity(BSOpacity.faint)))
        }
        let style = StrokeStyle(lineWidth: BSChartStroke.data, lineCap: .round, lineJoin: .round)
        context.stroke(line, with: .color(tint), style: style)
    }

    static func points(
        values: [Double?], domain: ClosedRange<Double>?, size: CGSize, inset: CGFloat
    ) -> [CGPoint?] {
        let valid = values.compactMap { $0 }
        guard !valid.isEmpty else { return [] }
        let low = domain?.lowerBound ?? (valid.min() ?? 0)
        let high = domain?.upperBound ?? (valid.max() ?? 1)
        let span = high - low
        let step = values.count > 1 ? (size.width - inset * 2) / CGFloat(values.count - 1) : 0
        let usable = size.height - inset * 2
        return values.enumerated().map { index, value in
            guard let value else { return nil }
            let ratio = span > 0 ? (value - low) / span : 0.5
            let clamped = Swift.min(1, Swift.max(0, ratio))
            return CGPoint(x: inset + step * CGFloat(index), y: inset + usable * (1 - CGFloat(clamped)))
        }
    }

    static func runs(_ points: [CGPoint?]) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in points {
            if let point {
                current.append(point)
            } else if !current.isEmpty {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// 昨夜分期条：4 条泳道（深睡、核心、REM、清醒），睡眠色明度阶梯，清醒用灰色。
public struct SleepLanesMini: View {
    private let segments: [SleepStageSegment]
    private let tint: Color

    /// 创建分期条。
    public init(segments: [SleepStageSegment], tint: Color) {
        self.segments = segments
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            guard let start = segments.map(\.startDate).min(),
                  let end = segments.map(\.endDate).max(),
                  end > start
            else { return }
            let total = end.timeIntervalSince(start)
            let lane = size.height / CGFloat(Self.lanes.count)
            let gap = BSChartStroke.rule
            for segment in segments {
                guard let row = Self.lanes.firstIndex(of: segment.stage) else { continue }
                let x0 = size.width * CGFloat(segment.startDate.timeIntervalSince(start) / total)
                let x1 = size.width * CGFloat(segment.endDate.timeIntervalSince(start) / total)
                let rect = CGRect(
                    x: x0, y: lane * CGFloat(row) + gap,
                    width: Swift.max(BSChartStroke.data, x1 - x0), height: lane - gap * 2
                )
                let path = Path(roundedRect: rect, cornerRadius: lane / 2)
                context.fill(path, with: .color(color(for: segment.stage)))
            }
        }
        .accessibilityHidden(true)
    }

    private static let lanes: [SleepStage] = [.awake, .rem, .core, .deep]

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .deep: tint
        case .core: tint.opacity(BSOpacity.scrim)
        case .rem: tint.opacity(BSOpacity.disabled)
        case .awake: BSColor.dimmed
        }
    }
}

/// 近 7 天日负荷柱：今天实色，前几天领域色 × `BSOpacity.past`，0 值画小圆点，缺失不画。
public struct LoadWeekBarsMini: View {
    private let values: [Double?]
    private let tint: Color

    /// 创建 7 天负荷柱；`values` 最后一项是今天。
    public init(values: [Double?], tint: Color) {
        self.values = values
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            let count = Swift.max(1, values.count)
            let slot = size.width / CGFloat(count)
            let barWidth = slot - BSSpace.xs
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let color = index == values.count - 1 ? tint : tint.opacity(BSOpacity.past)
                let centerX = slot * (CGFloat(index) + 0.5)
                if value <= 0 {
                    let rect = CGRect(
                        x: centerX - BSSize.dot / 2, y: size.height - BSSize.dot,
                        width: BSSize.dot, height: BSSize.dot
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    continue
                }
                let height = Swift.max(BSSpace.xs, size.height * CGFloat(Swift.min(100, value) / 100))
                let rect = CGRect(
                    x: centerX - barWidth / 2, y: size.height - height, width: barWidth, height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: BSChartStroke.data), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 今日按小时的压力柱：训练屏蔽时段画中性灰块，未来时段不画。
public struct StressHoursMini: View {
    private let bins: [StressTimelineBin]
    private let excludedHours: Set<Int>
    private let currentHour: Int
    private let tint: Color

    /// 创建按小时压力柱。
    public init(bins: [StressTimelineBin], excludedHours: Set<Int>, currentHour: Int, tint: Color) {
        self.bins = bins
        self.excludedHours = excludedHours
        self.currentHour = currentHour
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            let hours = 24
            let slot = size.width / CGFloat(hours)
            let barWidth = Swift.max(BSChartStroke.data, slot - BSChartStroke.rule)
            let byHour = Self.valuesByHour(bins)
            for hour in 0...Swift.min(23, Swift.max(0, currentHour)) {
                let centerX = slot * (CGFloat(hour) + 0.5)
                if excludedHours.contains(hour) {
                    let rect = CGRect(x: centerX - barWidth / 2, y: 0, width: barWidth, height: size.height)
                    context.fill(Path(rect), with: .color(Color.secondary.opacity(BSOpacity.muted)))
                    continue
                }
                guard let value = byHour[hour] else { continue }
                let height = Swift.max(BSChartStroke.data, size.height * CGFloat(Swift.min(100, Swift.max(0, value)) / 100))
                let rect = CGRect(
                    x: centerX - barWidth / 2, y: size.height - height, width: barWidth, height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
            }
        }
        .accessibilityHidden(true)
    }

    static func valuesByHour(_ bins: [StressTimelineBin]) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for bin in bins {
            for offset in 0..<Swift.max(1, bin.spanHours) {
                result[bin.hour + offset] = Double(bin.value)
            }
        }
        return result
    }
}

/// 今日电量曲线：折线 + 浅色面积 + 末端圆点。
public struct EnergyCurveMini: View {
    private let points: [EnergyCurvePoint]
    private let tint: Color

    /// 创建电量迷你曲线；只画已发生的点（非估算），没有已发生的点时画全部。
    public init(points: [EnergyCurvePoint], tint: Color) {
        self.points = points
        self.tint = tint
    }

    public var body: some View {
        MiniAreaLine(values: values, tint: tint, domain: 0...100)
    }

    private var values: [Double?] {
        let observed = points.filter { !$0.isEstimated }
        let source = observed.isEmpty ? points : observed
        return source.sorted { $0.hour < $1.hour }.map { Double($0.value) }
    }
}
