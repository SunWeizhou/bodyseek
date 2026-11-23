import Charts
import SwiftUI

/// 摄入柱图里的一天。
public struct IntakeBarPoint: Identifiable, Hashable, Sendable {
    /// 稳定标识（通常是日期）。
    public let id: String
    /// X 轴标签（日）。
    public let label: String
    /// 当天已记录热量；没有记录时为 `nil`（缺失，不画柱）。
    public let kcal: Double?
    /// 是否是页面当前选中的那一天。
    public let isSelected: Bool

    /// 创建一天的数据。
    public init(id: String, label: String, kcal: Double?, isSelected: Bool) {
        self.id = id
        self.label = label
        self.kcal = kcal
        self.isSelected = isSelected
    }
}

/// 每日热量摄入柱图：单色柱，选中那天保持强调色，其余降为 `BSOpacity.disabled`；目标用 1pt 实线表示。
public struct IntakeBarChart: View {
    public let points: [IntakeBarPoint]
    public let target: Double?
    public let onSelect: ((String) -> Void)?

    @State private var rawSelectedLabel: String?

    /// 创建摄入柱图。
    /// - Parameters:
    ///   - points: 按日期升序的每日数据。
    ///   - target: 热量目标（kcal）；为 `nil` 时不画目标线。
    ///   - onSelect: 点选某一天时回调该点的 `id`。
    public init(points: [IntakeBarPoint], target: Double? = nil, onSelect: ((String) -> Void)? = nil) {
        self.points = points
        self.target = target
        self.onSelect = onSelect
    }

    public var body: some View {
        Chart {
            ForEach(points) { point in
                bar(point)
            }
            if let target {
                RuleMark(y: .value("目标", target))
                    .lineStyle(StrokeStyle(lineWidth: BSChartStroke.rule))
                    .foregroundStyle(BSColor.separator)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: BSChartStroke.grid))
                    .foregroundStyle(BSColor.separator)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $rawSelectedLabel)
        .onChange(of: rawSelectedLabel) { _, newValue in
            guard let newValue, let point = points.first(where: { $0.label == newValue }) else { return }
            onSelect?(point.id)
        }
        .accessibilityLabel("每日热量摄入")
        .accessibilityValue(summary)
    }

    @ChartContentBuilder
    private func bar(_ point: IntakeBarPoint) -> some ChartContent {
        if let kcal = point.kcal {
            BarMark(x: .value("日", point.label), y: .value("kcal", kcal))
                .cornerRadius(BSRadius.s)
                .foregroundStyle(point.isSelected ? BSColor.tint : BSColor.tint.opacity(BSOpacity.disabled))
        }
    }

    private var summary: String {
        let recorded = points.compactMap(\.kcal)
        guard !recorded.isEmpty else { return "没有已记录的天数" }
        let average = recorded.reduce(0, +) / Double(recorded.count)
        return "已记录 \(recorded.count) 天，日均 \(average.formatted(.number.precision(.fractionLength(0)))) kcal"
    }
}
