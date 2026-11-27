import BodySeekCore
import SwiftUI

/// 宏量营养素一行：已录入与 AI 估算分开计量（UI v4 §4.1）。
///
/// `recorded` / `estimated` / `target` / `targetUpper` 必须同单位。供能比目标（DRIs 的 AMDR，如碳水 45–65% 能量）
/// 用 `%E`：读数是供能占比，`amountText` 是用户熟悉的克数。目标项的 `unit` 就是 `%E`，
/// 以前直接把它的下限当克数显示（"317 / 45 g"），会读成超标七倍，其实只占能量四成。
public struct BSMacroSplit: Identifiable, Hashable, Sendable {
    /// 名称，例如"蛋白质"。
    public let name: String
    /// 已录入量（非估算），单位同 `unit`。
    public let recorded: Double
    /// AI 估算量，单位同 `unit`。
    public let estimated: Double
    /// 目标下限；`max` 型目标是上限，单位同 `unit`。
    public let target: Double?
    /// 区间型目标才有：目标上限。
    public let targetUpper: Double?
    /// 单位：`"g"` 或 `"%E"`。
    public let unit: String
    /// `unit` 是 `%E` 时显示的克数文字，例如"≈317 g"；为 `nil` 时按 `recorded + estimated` 和 `unit` 生成。
    public let amountText: String?

    public var id: String { name }

    /// 是否含 AI 估算。
    public var hasEstimate: Bool { estimated > 0 }

    /// 创建一行宏量营养素（单一目标或下限，单位克）。
    public init(name: String, recorded: Double, estimated: Double, target: Double?, unit: String = "g") {
        self.init(name: name, recorded: recorded, estimated: estimated, target: target, targetUpper: nil, unit: unit, amountText: nil)
    }

    /// 创建一行宏量营养素（完整参数）。
    public init(
        name: String,
        recorded: Double,
        estimated: Double,
        target: Double?,
        targetUpper: Double?,
        unit: String,
        amountText: String? = nil
    ) {
        self.name = name
        self.recorded = recorded
        self.estimated = estimated
        self.target = target
        self.targetUpper = targetUpper
        self.unit = unit
        self.amountText = amountText
    }

    /// 目标文字，例如"45–65%"或"≥82 g"；没有目标时为 `nil`。
    public var targetText: String? {
        guard target != nil || targetUpper != nil else { return nil }
        return NutritionTargetText.bounds(NutritionTargetBounds(lower: target, upper: targetUpper), unit: unit)
    }
}

/// 进度条：已录入实色 + AI 估算斜纹（`BSStripeFill`），不用环。
///
/// 轨道长度取"目标上限"与"当前总量"里较大的那个，所以在目标以内时条按目标量度；超过目标时条占满，
/// 目标位置留一道竖向刻度作参照，一眼能看出超了多少。区间型目标在轨道上铺一层浅色带标出范围。
public struct BSStripedProgressBar: View {
    private let recordedFraction: Double
    private let estimatedFraction: Double
    private let targetLowerFraction: Double?
    private let targetUpperFraction: Double?
    private let tint: Color

    /// 创建进度条。`recorded`、`estimated` 与 `target` 同单位；没有目标时按总量占满。
    public init(recorded: Double, estimated: Double, target: Double?, tint: Color = BSColor.tint) {
        self.init(recorded: recorded, estimated: estimated, target: target, targetUpper: nil, tint: tint)
    }

    /// 创建进度条，支持区间型目标。
    public init(recorded: Double, estimated: Double, target: Double?, targetUpper: Double?, tint: Color = BSColor.tint) {
        let total = recorded + estimated
        let scale = Swift.max(targetUpper ?? target ?? 0, total, 1)
        let lowerFraction = target.map { Swift.min(1, Swift.max(0, $0 / scale)) }
        let upperFraction = targetUpper.map { Swift.min(1, Swift.max(0, $0 / scale)) }
        self.init(
            recordedFraction: Swift.min(1, Swift.max(0, recorded / scale)),
            estimatedFraction: Swift.min(Swift.max(0, 1 - recorded / scale), Swift.max(0, estimated / scale)),
            targetLowerFraction: lowerFraction,
            targetUpperFraction: upperFraction,
            tint: tint
        )
    }

    /// 创建进度条，直接给出 0–1 的占比（读数单位与轨道刻度不同时用，例如供能比占 0–100% 轨道）。
    public init(
        recordedFraction: Double,
        estimatedFraction: Double,
        targetLowerFraction: Double?,
        targetUpperFraction: Double?,
        tint: Color = BSColor.tint
    ) {
        let clampedRecorded = Swift.min(1, Swift.max(0, recordedFraction))
        self.recordedFraction = clampedRecorded
        self.estimatedFraction = Swift.min(1 - clampedRecorded, Swift.max(0, estimatedFraction))
        self.targetLowerFraction = targetLowerFraction.map { Swift.min(1, Swift.max(0, $0)) }
        self.targetUpperFraction = targetUpperFraction.map { Swift.min(1, Swift.max(0, $0)) }
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let solid = width * recordedFraction
            let stripe = width * estimatedFraction
            ZStack(alignment: .leading) {
                Capsule().fill(BSColor.surfaceInset)
                if let targetLowerFraction, let targetUpperFraction, targetUpperFraction > targetLowerFraction {
                    // 区间型目标：整段范围铺一层浅色带。
                    Capsule()
                        .fill(tint.opacity(BSOpacity.faint))
                        .frame(width: width * (targetUpperFraction - targetLowerFraction))
                        .offset(x: width * targetLowerFraction)
                }
                Rectangle()
                    .fill(tint)
                    .frame(width: solid)
                BSStripeFill(color: tint)
                    .frame(width: stripe)
                    .offset(x: solid)
                // 超过目标后条占满，在目标上限（没有上限时用下限）的位置留一道刻度作参照。
                if solid + stripe >= width, let mark = targetUpperFraction ?? targetLowerFraction, mark > 0, mark < 1 {
                    Rectangle()
                        .fill(BSColor.surface)
                        .frame(width: BSChartStroke.rule, height: BSSize.dot)
                        .offset(x: width * mark - BSChartStroke.rule / 2)
                }
            }
            .frame(height: BSSize.dot)
            .clipShape(Capsule())
        }
        .frame(height: BSSize.dot)
        .accessibilityHidden(true)
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
    private let targetKcalUpper: Double?
    private let availability: MetricAvailability
    private let macros: [BSMacroSplit]

    /// 创建热量卡。
    /// - Parameters:
    ///   - title: 卡片标题，例如"11月23日摄入 · 今天"。
    ///   - recordedKcal: 已录入热量（非估算）。
    ///   - estimatedKcal: AI 估算热量。
    ///   - pendingMeals: 缺热量的餐数。
    ///   - targetKcal: 日目标下限（`max` 型目标是上限）；未设置为 `nil`。
    ///   - targetKcalUpper: 区间型目标的日目标上限；没有时为 `nil`。
    ///   - availability: 四态可用性；缺失显示 `--` 与原因。
    ///   - macros: 宏量营养素，通常 3 项。
    public init(
        title: String,
        recordedKcal: Double,
        estimatedKcal: Double,
        pendingMeals: Int,
        targetKcal: Double?,
        targetKcalUpper: Double? = nil,
        availability: MetricAvailability = .available,
        macros: [BSMacroSplit]
    ) {
        self.title = title
        self.recordedKcal = recordedKcal
        self.estimatedKcal = estimatedKcal
        self.pendingMeals = pendingMeals
        self.targetKcal = targetKcal
        self.targetKcalUpper = targetKcalUpper
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
                BSStripedProgressBar(
                    recorded: recordedKcal,
                    estimated: estimatedKcal,
                    target: targetKcal,
                    targetUpper: targetKcalUpper
                )
                if let targetLine {
                    Text(targetLine)
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

    private var totalKcal: Double { recordedKcal + estimatedKcal }

    private var showsValue: Bool {
        switch availability {
        case .available, .knownZero: true
        case .missing, .excluded: false
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
        guard showsValue else { return "--" }
        let prefix = estimatedKcal > 0 ? "≈" : ""
        return prefix + bsGrouped(totalKcal)
    }

    private var detailLine: String {
        if let reason = availability.reasonText { return reason }
        var parts = ["已录入 \(bsGrouped(recordedKcal)) kcal"]
        if estimatedKcal > 0 { parts.append("AI 估算 \(bsGrouped(estimatedKcal)) kcal") }
        if pendingMeals > 0 { parts.append("\(pendingMeals) 餐待补热量") }
        return parts.joined(separator: " · ")
    }

    /// 日目标一行：区间型目标写出整个范围，不只写下限；超出上限时补一句超出多少。
    private var targetLine: String? {
        guard targetKcal != nil || targetKcalUpper != nil else { return nil }
        var line = "日目标"
        if let lower = targetKcal, let upper = targetKcalUpper, upper > lower {
            line += " \(bsGrouped(lower))–\(bsGrouped(upper)) kcal"
        } else if let single = targetKcalUpper ?? targetKcal {
            line += " \(bsGrouped(single)) kcal"
        }
        if showsValue, let upper = targetKcalUpper ?? targetKcal, totalKcal > upper {
            line += " · 已超出 \(bsGrouped(totalKcal - upper)) kcal"
        }
        return line
    }

    private func macroRow(_ macro: BSMacroSplit) -> some View {
        VStack(spacing: BSSpace.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.name)
                    .bsText(.label)
                Spacer(minLength: BSSpace.xs)
                Text(macroText(macro))
                    .bsText(.caption)
                    .multilineTextAlignment(.trailing)
            }
            macroBar(macro)
        }
        .accessibilityElement(children: .combine)
    }

    private func macroBar(_ macro: BSMacroSplit) -> some View {
        if macro.unit == "%E" {
            // 供能比：轨道是 0–100% 能量，目标区间铺在轨道上。
            BSStripedProgressBar(
                recordedFraction: macro.recorded / 100,
                estimatedFraction: macro.estimated / 100,
                targetLowerFraction: macro.target.map { $0 / 100 },
                targetUpperFraction: macro.targetUpper.map { $0 / 100 },
                tint: BSColor.tint
            )
        } else {
            BSStripedProgressBar(
                recorded: macro.recorded,
                estimated: macro.estimated,
                target: macro.target,
                targetUpper: macro.targetUpper
            )
        }
    }

    private func macroText(_ macro: BSMacroSplit) -> String {
        let prefix = macro.hasEstimate ? "≈" : ""
        let amount: String
        if let provided = macro.amountText {
            amount = provided
        } else {
            amount = prefix + bsGrouped(macro.recorded + macro.estimated) + (macro.unit == "%E" ? "%" : " \(macro.unit)")
        }
        guard let targetText = macro.targetText else { return amount }
        let targetLabel = macro.unit == "%E" ? "目标 \(targetText) 能量" : "目标 \(targetText)"
        return "\(amount) · \(targetLabel)"
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
