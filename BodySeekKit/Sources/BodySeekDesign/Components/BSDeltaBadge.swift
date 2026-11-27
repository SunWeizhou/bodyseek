import SwiftUI

/// 与基线比较：箭头 + 变化量 + "vs 28 天"。永远使用二级文字色，不用红绿着色
/// （HRV 升高不一定是"好"，颜色会误导）。
public struct BSDeltaBadge: View {
    private let delta: Double?
    private let unit: String
    private let comparison: String
    private let fractionDigits: Int

    /// 创建变化标记。
    /// - Parameters:
    ///   - delta: 与基线的差值；`nil` 显示 `--`。
    ///   - unit: 单位，例如 `ms`。
    ///   - comparison: 比较对象说明，例如 `vs 28 天`。
    ///   - fractionDigits: 小数位数。
    public init(
        delta: Double?,
        unit: String = "",
        comparison: String = "vs 28 天",
        fractionDigits: Int = 0
    ) {
        self.delta = delta
        self.unit = unit
        self.comparison = comparison
        self.fractionDigits = fractionDigits
    }

    public var body: some View {
        HStack(spacing: BSSpace.xxs) {
            Image(systemName: symbolName)
                .imageScale(.small)
            Text(valueText)
            Text(comparison)
        }
        .bsText(.label)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        guard let delta else { return "minus" }
        if delta > 0 { return "arrow.up" }
        if delta < 0 { return "arrow.down" }
        return "arrow.right"
    }

    private var valueText: String {
        guard let delta else { return "--" }
        let number = bsFormat(abs(delta), digits: fractionDigits)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
