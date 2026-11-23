import BodySeekCore
import SwiftUI

/// 宏量营养素一行：已录入与 AI 估算分开计量（UI v4 §4.1）。
public struct BSMacroSplit: Identifiable, Hashable, Sendable {
    /// 名称，例如"蛋白质"。
    public let name: String
    /// 已录入量（非估算）。
    public let recorded: Double
    /// AI 估算量。
    public let estimated: Double
    /// 目标量；未设置为 `nil`。
    public let target: Double?
    /// 单位。
    public let unit: String

    public var id: String { name }

    /// 创建一行宏量营养素。
    public init(name: String, recorded: Double, estimated: Double, target: Double?, unit: String = "g") {
        self.name = name
        self.recorded = recorded
        self.estimated = estimated
        self.target = target
        self.unit = unit
    }
}

/// 进度条：已录入实色 + AI 估算斜纹（`BSStripeFill`），不用环。
public struct BSStripedProgressBar: View {
    private let recorded: Double
    private let estimated: Double
    private let target: Double?
    private let tint: Color

    /// 创建进度条。`recorded`、`estimated` 与 `target` 同单位；没有目标时按总量占满。
    public init(recorded: Double, estimated: Double, target: Double?, tint: Color = BSColor.tint) {
        self.recorded = recorded
        self.estimated = estimated
        self.target = target
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let solid = width * recordedFraction
            let stripe = width * estimatedFraction
            ZStack(alignment: .leading) {
                Capsule().fill(BSColor.surfaceInset)
                Rectangle()
                    .fill(tint)
                    .frame(width: solid)
                BSStripeFill(color: tint)
                    .frame(width: stripe)
                    .offset(x: solid)
            }
            .clipShape(Capsule())
        }
        .frame(height: BSSize.dot)
        .accessibilityHidden(true)
    }

    private var scale: Double {
        let total = recorded + estimated
        let base = target ?? total
        return Swift.max(base, total, 1)
    }

    private var recordedFraction: CGFloat {
        CGFloat(Swift.min(1, Swift.max(0, recorded / scale)))
    }

    private var estimatedFraction: CGFloat {
        let remaining = 1 - Double(recordedFraction)
        return CGFloat(Swift.min(remaining, Swift.max(0, estimated / scale)))
    }
}

/// 营养页今日热量卡（UI v4 §4.1，不用环）：大数字（含估算加"≈"）+ 一行说明 + 热量进度条 + 日目标 +
/// 三行宏量营养素 + 图例。
public struct BSCalorieCard: View {
    private let title: String
    private let recordedKcal: Double
    private let estimatedKcal: Double
    private let pendingMeals: Int
    private let targetKcal: Double?
    private let availability: MetricAvailability
    private let macros: [BSMacroSplit]

    /// 创建热量卡。
    /// - Parameters:
    ///   - title: 卡片标题，例如"11月23日摄入 · 今天"。
    ///   - recordedKcal: 已录入热量（非估算）。
    ///   - estimatedKcal: AI 估算热量。
    ///   - pendingMeals: 缺热量的餐数。
    ///   - targetKcal: 日目标；未设置为 `nil`。
    ///   - availability: 四态可用性；缺失显示 `--` 与原因。
    ///   - macros: 宏量营养素，通常 3 项。
    public init(
        title: String,
        recordedKcal: Double,
        estimatedKcal: Double,
        pendingMeals: Int,
        targetKcal: Double?,
        availability: MetricAvailability = .available,
        macros: [BSMacroSplit]
    ) {
        self.title = title
        self.recordedKcal = recordedKcal
        self.estimatedKcal = estimatedKcal
        self.pendingMeals = pendingMeals
        self.targetKcal = targetKcal
        self.availability = availability
        self.macros = macros
    }

    public var body: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text(title)
                    .bsText(.cardTitle)
                bigNumber
                Text(detailLine)
                    .bsText(.caption)
                BSStripedProgressBar(recorded: recordedKcal, estimated: estimatedKcal, target: targetKcal)
                if let targetKcal {
                    Text("日目标 \(bsGrouped(targetKcal)) kcal")
                        .bsText(.caption)
                }
                if !macros.isEmpty {
                    VStack(spacing: BSSpace.xs) {
                        ForEach(macros) { macro in
                            macroRow(macro)
                        }
                    }
                }
                legend
            }
        }
    }

    private var bigNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: BSSpace.xxs) {
            Text(numberText)
                .bsText(.heroNumber)
            Text(verbatim: "kcal")
                .bsText(.label)
        }
    }

    private var numberText: String {
        switch availability {
        case .available, .knownZero:
            let prefix = estimatedKcal > 0 ? "≈" : ""
            return prefix + bsGrouped(recordedKcal + estimatedKcal)
        case .missing, .excluded:
            return "--"
        }
    }

    private var detailLine: String {
        if let reason = availability.reasonText { return reason }
        var parts = ["已录入 \(bsGrouped(recordedKcal)) kcal"]
        if estimatedKcal > 0 { parts.append("AI 估算 \(bsGrouped(estimatedKcal)) kcal") }
        if pendingMeals > 0 { parts.append("\(pendingMeals) 餐待补热量") }
        return parts.joined(separator: " · ")
    }

    private func macroRow(_ macro: BSMacroSplit) -> some View {
        VStack(spacing: BSSpace.xxs) {
            HStack {
                Text(macro.name)
                    .bsText(.label)
                Spacer(minLength: BSSpace.xs)
                Text(macroText(macro))
                    .bsText(.caption)
            }
            BSStripedProgressBar(recorded: macro.recorded, estimated: macro.estimated, target: macro.target)
        }
        .accessibilityElement(children: .combine)
    }

    private func macroText(_ macro: BSMacroSplit) -> String {
        let total = macro.recorded + macro.estimated
        let prefix = macro.estimated > 0 ? "≈" : ""
        let current = prefix + bsGrouped(total)
        if let target = macro.target { return "\(current) / \(bsGrouped(target)) \(macro.unit)" }
        return "\(current) \(macro.unit)"
    }

    private var legend: some View {
        HStack(spacing: BSSpace.m) {
            HStack(spacing: BSSpace.xxs) {
                Capsule()
                    .fill(BSColor.tint)
                    .frame(width: BSSpace.m, height: BSSize.dot)
                Text("已录入")
            }
            HStack(spacing: BSSpace.xxs) {
                BSStripeFill(color: BSColor.tint)
                    .frame(width: BSSpace.m, height: BSSize.dot)
                    .clipShape(Capsule())
                Text("AI 估算")
            }
        }
        .bsText(.caption)
        .accessibilityHidden(true)
    }
}

func bsGrouped(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}
