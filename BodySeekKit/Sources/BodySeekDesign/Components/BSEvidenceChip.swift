import SwiftUI

/// 数字溯源 chip：指标 · 日期 / 窗口 · 单位。点开后由调用方显示原始工具结果。
public struct BSEvidenceChip: View {
    private let label: String
    private let action: (() -> Void)?

    /// 创建证据 chip。
    /// - Parameters:
    ///   - label: 例如"HRV · 11月22日 · ms"。
    ///   - action: 点击动作（查看证据）；为 `nil` 时只展示。
    public init(_ label: String, action: (() -> Void)? = nil) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Text(label)
            .bsText(.caption)
            .lineLimit(1)
            .padding(.horizontal, BSSpace.xs)
            .padding(.vertical, BSSpace.xxs)
            .background(BSColor.surfaceInset, in: Capsule())
            .frame(minHeight: BSSize.hitTarget)
            .contentShape(.rect)
            .bsTappable(action)
    }
}
