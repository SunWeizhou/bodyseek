import BodySeekCore
import SwiftUI

/// 宏量营养素进度。
public struct BSMacroProgress: Identifiable, Hashable, Sendable {
    /// 名称，例如"蛋白质"。
    public let name: String
    /// 已摄入量；缺失时为 `nil`。
    public let value: Double?
    /// 目标量；未设置时为 `nil`。
    public let target: Double?
    /// 单位，例如 `g`。
    public let unit: String

    public var id: String { name }

    /// 创建一项宏量营养素进度。
    public init(name: String, value: Double?, target: Double?, unit: String = "g") {
        self.name = name
        self.value = value
        self.target = target
        self.unit = unit
    }

    var fraction: Double {
        guard let value, let target, target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }

    var text: String {
        guard let value else { return "--" }
        if let target { return "\(bsFormat(value)) / \(bsFormat(target)) \(unit)" }
        return "\(bsFormat(value)) \(unit)"
    }
}

/// 营养页 L0：热量环 + 三条宏量营养素胶囊进度条。数据统一使用全局强调色 `tint`。
///
/// `isEstimate` 为 `true` 时进度条填充降为 `BSOpacity.muted`，表示估算（`dataEstimate`）。
public struct BSIntakeRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calories: Double?
    private let target: Double?
    private let availability: MetricAvailability
    private let isEstimate: Bool
    private let macros: [BSMacroProgress]
    private let isLoading: Bool

    private static let startAngle: Double = -90
    private static let minimumTextScale: CGFloat = 0.5

    /// 创建摄入环。
    /// - Parameters:
    ///   - calories: 今日已摄入热量（kcal）；缺失时为 `nil`。
    ///   - target: 热量目标（kcal）。
    ///   - availability: 四态可用性。
    ///   - isEstimate: 是否包含估算值。
    ///   - macros: 宏量营养素进度，通常 3 项。
    ///   - isLoading: 为 `true` 时显示骨架。
    public init(
        calories: Double?,
        target: Double?,
        availability: MetricAvailability = .available,
        isEstimate: Bool = false,
        macros: [BSMacroProgress],
        isLoading: Bool = false
    ) {
        self.calories = calories
        self.target = target
        self.availability = availability
        self.isEstimate = isEstimate
        self.macros = macros
        self.isLoading = isLoading
    }

    public var body: some View {
        BSCard {
            HStack(spacing: BSSpace.m) {
                ring
                VStack(spacing: BSSpace.s) {
                    ForEach(macros) { macro in
                        BSMacroBar(macro: macro, isEstimate: isEstimate)
                    }
                }
            }
            .redacted(reason: isLoading ? .placeholder : [])
        }
        .accessibilityElement(children: .combine)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(BSColor.surfaceInset, lineWidth: BSChartStroke.ringL)
                .padding(BSChartStroke.ringL / 2)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        BSColor.tint,
                        style: StrokeStyle(lineWidth: BSChartStroke.ringL, lineCap: .round)
                    )
                    .rotationEffect(.degrees(Self.startAngle))
                    .padding(BSChartStroke.ringL / 2)
            }
            VStack(spacing: BSSpace.none) {
                Text(valueText)
                    .bsText(.heroNumber)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.minimumTextScale)
                Text(captionText)
                    .bsText(.caption)
            }
            .padding(BSChartStroke.ringL)
        }
        .frame(width: BSSize.ringL, height: BSSize.ringL)
        .animation(BSMotion.animation(BSMotion.standard, reduceMotion: reduceMotion), value: fraction)
    }

    private var fraction: Double {
        guard availability.isAvailable, let calories, let target, target > 0 else { return 0 }
        return min(max(calories / target, 0), 1)
    }

    private var valueText: String {
        switch availability {
        case .available:
            if let calories { return bsFormat(calories) }
            return "--"
        case .knownZero:
            return "0"
        case .missing, .excluded:
            return "--"
        }
    }

    private var captionText: String {
        if let reason = availability.reasonText { return reason }
        if let target { return "目标 \(bsFormat(target)) kcal" }
        return "kcal"
    }
}

private struct BSMacroBar: View {
    let macro: BSMacroProgress
    let isEstimate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpace.xxs) {
            HStack {
                Text(macro.name)
                    .bsText(.label)
                Spacer(minLength: BSSpace.xs)
                Text(macro.text)
                    .bsText(.caption)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BSColor.surfaceInset)
                    Capsule()
                        .fill(isEstimate ? BSColor.tint.opacity(BSOpacity.muted) : BSColor.tint)
                        .frame(width: proxy.size.width * CGFloat(macro.fraction))
                }
            }
            .frame(height: BSSpace.xs)
        }
    }
}
