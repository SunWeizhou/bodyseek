import BodySeekCore
import SwiftUI

/// 分数环尺寸。
public enum BSScoreRingSize: Sendable, Hashable, CaseIterable {
    /// L：`BSSize.ringL`，L0 主分数环。
    case large
    /// M：`BSSize.ringM`，五项分数里的次级环。
    case medium
    /// S：`BSSize.ringS`，列表行和 chip 里的小环（不显示数字和文字）。
    case small

    var diameter: CGFloat {
        switch self {
        case .large: BSSize.ringL
        case .medium: BSSize.ringM
        case .small: BSSize.ringS
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .large: BSChartStroke.ringL
        case .medium: BSChartStroke.ringM
        case .small: BSChartStroke.ringS
        }
    }
}

/// 分数环排布里的一项。
public struct BSScoreItem: Identifiable, Hashable, Sendable {
    /// 指标种类。
    public let kind: MetricKind
    /// 0–100 的分数；缺失时为 `nil`。
    public let value: Int?
    /// 四态可用性。
    public let availability: MetricAvailability
    /// 状态词，例如"充沛 / 平时 / 偏疲劳"。
    public let statusText: String?

    public var id: MetricKind { kind }

    /// 创建一项分数。
    public init(
        kind: MetricKind,
        value: Int?,
        availability: MetricAvailability = .available,
        statusText: String? = nil
    ) {
        self.kind = kind
        self.value = value
        self.availability = availability
        self.statusText = statusText
    }
}

/// 0–100 分数环：环 + 数字 + 指标名 + 状态词。
///
/// 四态画法（沿用 dataviz §4.1）：有数据正常绘制；已知为零只画轨道，中间写 `0`，下方写原因；
/// 缺失和排除只画轨道，中间写 `--`，下方写原因。提供 `action` 时整环可点，并带按压反馈。
public struct BSScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private let kind: MetricKind
    private let value: Int?
    private let availability: MetricAvailability
    private let statusText: String?
    private let size: BSScoreRingSize
    private let isLoading: Bool
    private let action: (() -> Void)?

    private static let maxScore: Double = 100
    private static let startAngle: Double = -90
    private static let minimumTextScale: CGFloat = 0.5

    /// 创建分数环。
    /// - Parameters:
    ///   - kind: 指标种类，决定领域色和名称。
    ///   - value: 0–100 的分数；缺失时传 `nil`。
    ///   - availability: 四态可用性。
    ///   - statusText: 状态词；非"有数据"状态下会被原因文字取代。
    ///   - size: 环的尺寸。
    ///   - isLoading: 为 `true` 时显示骨架。
    ///   - action: 点击动作（通常进入详情）；为 `nil` 时不可点。
    public init(
        kind: MetricKind,
        value: Int?,
        availability: MetricAvailability = .available,
        statusText: String? = nil,
        size: BSScoreRingSize = .large,
        isLoading: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.value = value
        self.availability = availability
        self.statusText = statusText
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        content
            .bsTappable(action)
    }

    private var content: some View {
        VStack(spacing: BSSpace.xxs) {
            ring
            if size != .small {
                captions
            }
        }
        .redacted(reason: isLoading ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(BSColor.surfaceInset, lineWidth: size.lineWidth)
                .padding(size.lineWidth / 2)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        BSColor.domain(kind),
                        style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(Self.startAngle))
                    .padding(size.lineWidth / 2)
            }
            if size != .small {
                Text(valueText)
                    .bsText(size == .large ? .heroNumber : .number)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.minimumTextScale)
                    .padding(size.lineWidth)
            }
        }
        .frame(width: size.diameter, height: size.diameter)
        .animation(BSMotion.animation(BSMotion.standard, reduceMotion: reduceMotion), value: fraction)
        .animation(BSMotion.animation(BSMotion.standard, reduceMotion: reduceMotion), value: valueText)
    }

    private var captions: some View {
        VStack(spacing: 0) {
            nameLabel
            if let detail = detailText {
                Text(detail)
                    .bsText(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if differentiateWithoutColor {
            Label(kind.title, systemImage: kind.systemImage)
                .bsText(.label)
        } else {
            Text(kind.title)
                .bsText(.label)
        }
    }

    private var fraction: Double {
        guard availability.isAvailable, let value else { return 0 }
        return min(max(Double(value) / Self.maxScore, 0), 1)
    }

    private var valueText: String {
        switch availability {
        case .available:
            if let value { return String(value) }
            return "--"
        case .knownZero:
            return "0"
        case .missing, .excluded:
            return "--"
        }
    }

    private var detailText: String? {
        availability.reasonText ?? statusText
    }

    private var accessibilityText: String {
        var parts = [kind.title, valueText]
        if let detail = detailText { parts.append(detail) }
        return parts.joined(separator: "，")
    }
}

/// 五项分数的固定排布：首项为大环，其余四项为中环，2×2 排列。
public struct BSScoreRingGroup: View {
    private let items: [BSScoreItem]
    private let isLoading: Bool
    private let onSelect: ((MetricKind) -> Void)?

    private static let columnCount = 2

    fileprivate init(items: [BSScoreItem], isLoading: Bool, onSelect: ((MetricKind) -> Void)?) {
        self.items = items
        self.isLoading = isLoading
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: BSSpace.l) {
            if let first = items.first {
                ring(first, size: .large)
            }
            LazyVGrid(columns: columns, spacing: BSSpace.m) {
                ForEach(Array(items.dropFirst())) { item in
                    ring(item, size: .medium)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: BSSpace.m), count: Self.columnCount)
    }

    private func ring(_ item: BSScoreItem, size: BSScoreRingSize) -> some View {
        BSScoreRing(
            kind: item.kind,
            value: item.value,
            availability: item.availability,
            statusText: item.statusText,
            size: size,
            isLoading: isLoading,
            action: action(for: item)
        )
        .frame(maxWidth: .infinity)
    }

    private func action(for item: BSScoreItem) -> (() -> Void)? {
        guard let onSelect else { return nil }
        return { onSelect(item.kind) }
    }
}

public extension BSScoreRing {
    /// 五项分数的固定排布（首项大环，其余四项中环 2×2）。
    /// - Parameters:
    ///   - items: 五项分数，顺序即显示顺序。
    ///   - isLoading: 为 `true` 时显示骨架。
    ///   - onSelect: 点击某一环时的回调（通常进入该项详情）。
    static func group(
        _ items: [BSScoreItem],
        isLoading: Bool = false,
        onSelect: ((MetricKind) -> Void)? = nil
    ) -> BSScoreRingGroup {
        BSScoreRingGroup(items: items, isLoading: isLoading, onSelect: onSelect)
    }
}
