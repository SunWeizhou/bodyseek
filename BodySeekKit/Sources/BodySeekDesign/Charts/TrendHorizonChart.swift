import BodySeekCore
import SwiftUI

/// 统一的趋势图组件：快照带胶囊数据时渲染分周期胶囊
/// （7 天按日 / 30 天与 6 个月按周 / 3 年按月），
/// 没有胶囊数据的历史缓存快照退回日线图。
public struct TrendHorizonChart: View {
    public let snapshot: ChartSeriesSnapshot
    public let tint: Color
    public let unitLabel: String
    public let height: CGFloat
    public let onSelectDate: (@MainActor (Date?) -> Void)?
    public let onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)?

    public init(
        snapshot: ChartSeriesSnapshot,
        tint: Color,
        unitLabel: String = "分",
        height: CGFloat = 208,
        onSelectDate: (@MainActor (Date?) -> Void)? = nil,
        onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.tint = tint
        self.unitLabel = unitLabel
        self.height = height
        self.onSelectDate = onSelectDate
        self.onSelectBucket = onSelectBucket
    }

    public var body: some View {
        if snapshot.capsules.isEmpty {
            TrendLineChart(
                snapshot: snapshot,
                tint: tint,
                unitLabel: unitLabel,
                height: height,
                onSelectDate: onSelectDate
            )
        } else {
            RangeCapsuleChart(
                snapshot: snapshot,
                tint: tint,
                unitLabel: unitLabel,
                height: height,
                onSelectBucket: onSelectBucket
            )
        }
    }
}
