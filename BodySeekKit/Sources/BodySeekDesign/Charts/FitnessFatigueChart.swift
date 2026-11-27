import BodySeekCore
import Charts
import SwiftUI

/// 体能-疲劳图：两条 2pt 折线——体能（负荷色）、疲劳（灰色），在线尾直接标名称，没有图例。
///
/// 选中某一天时画 1pt 实线竖线和两个焦点圆，并通过 `onSelect` 把那一天交给统计头显示；松开后回到 `nil`。
public struct FitnessFatigueChart: View {
    public let points: [FitnessFatiguePoint]
    public let onSelect: (@MainActor (FitnessFatiguePoint?) -> Void)?

    @State private var rawSelectedDate: Date?
    @State private var selectedPoint: FitnessFatiguePoint?

    /// 创建体能-疲劳图。
    /// - Parameters:
    ///   - points: 按日期升序的数据点；没有体能值的点不画。
    ///   - onSelect: 选中某一天（或清除选中）时的回调，统计头据此联动。
    public init(
        points: [FitnessFatiguePoint],
        onSelect: (@MainActor (FitnessFatiguePoint?) -> Void)? = nil
    ) {
        self.points = points
        self.onSelect = onSelect
    }

    private var drawable: [FitnessFatiguePoint] {
        points.filter { $0.fitness != nil && $0.fatigue != nil }
    }

    public var body: some View {
        let data = drawable
        if data.isEmpty {
            ChartEmptyPlaceholder(title: "还没有足够的训练负荷数据", height: BSSize.chartStandard)
        } else {
            chart(data)
        }
    }

    private func chart(_ data: [FitnessFatiguePoint]) -> some View {
        Chart {
            ForEach(data) { point in
                fitnessLine(point)
                fatigueLine(point)
            }
            selectionMarks
            endLabels(data)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: BSChartStroke.grid))
                    .foregroundStyle(BSColor.separator)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .onChange(of: rawSelectedDate) { _, newValue in
            select(near: newValue, in: data)
        }
        .bodyseekSelectionHaptic(trigger: selectedPoint?.id)
        .accessibilityLabel("体能与疲劳曲线")
        .accessibilityValue(summary(data))
    }

    @ChartContentBuilder
    private func fitnessLine(_ point: FitnessFatiguePoint) -> some ChartContent {
        if let fitness = point.fitness {
            LineMark(
                x: .value("日期", point.date),
                y: .value("体能", fitness),
                series: .value("系列", "体能")
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: BSChartStroke.data, lineCap: .round, lineJoin: .round))
            .foregroundStyle(BSColor.strain)
        }
    }

    @ChartContentBuilder
    private func fatigueLine(_ point: FitnessFatiguePoint) -> some ChartContent {
        if let fatigue = point.fatigue {
            LineMark(
                x: .value("日期", point.date),
                y: .value("疲劳", fatigue),
                series: .value("系列", "疲劳")
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: BSChartStroke.data, lineCap: .round, lineJoin: .round))
            .foregroundStyle(BSColor.dimmed)
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selectedPoint {
            RuleMark(x: .value("选中日", selectedPoint.date))
                .lineStyle(StrokeStyle(lineWidth: BSChartStroke.rule))
                .foregroundStyle(BSColor.separator)
            if let fitness = selectedPoint.fitness {
                PointMark(x: .value("选中日", selectedPoint.date), y: .value("体能", fitness))
                    .foregroundStyle(BSColor.strain)
            }
            if let fatigue = selectedPoint.fatigue {
                PointMark(x: .value("选中日", selectedPoint.date), y: .value("疲劳", fatigue))
                    .foregroundStyle(BSColor.dimmed)
            }
        }
    }

    @ChartContentBuilder
    private func endLabels(_ data: [FitnessFatiguePoint]) -> some ChartContent {
        if selectedPoint == nil, let last = data.last, let fitness = last.fitness, let fatigue = last.fatigue {
            let fitnessOnTop = fitness >= fatigue
            PointMark(x: .value("最新", last.date), y: .value("体能", fitness))
                .foregroundStyle(BSColor.strain)
                .annotation(position: fitnessOnTop ? .top : .bottom, spacing: BSSpace.xxs) {
                    Text("体能")
                        .bsText(.caption)
                }
            PointMark(x: .value("最新", last.date), y: .value("疲劳", fatigue))
                .foregroundStyle(BSColor.dimmed)
                .annotation(position: fitnessOnTop ? .bottom : .top, spacing: BSSpace.xxs) {
                    Text("疲劳")
                        .bsText(.caption)
                }
        }
    }

    private func select(near date: Date?, in data: [FitnessFatiguePoint]) {
        guard let date else {
            if selectedPoint != nil {
                selectedPoint = nil
                onSelect?(nil)
            }
            return
        }
        guard let nearest = data.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return }
        if selectedPoint?.id != nearest.id {
            selectedPoint = nearest
            onSelect?(nearest)
        }
    }

    private func summary(_ data: [FitnessFatiguePoint]) -> String {
        guard let last = data.last, let fitness = last.fitness, let fatigue = last.fatigue else { return "暂无数据" }
        let fitnessText = fitness.formatted(.number.precision(.fractionLength(0)))
        let fatigueText = fatigue.formatted(.number.precision(.fractionLength(0)))
        return "最新体能 \(fitnessText)，疲劳 \(fatigueText)"
    }
}
