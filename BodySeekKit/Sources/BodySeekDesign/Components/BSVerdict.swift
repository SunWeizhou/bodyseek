import SwiftUI

/// 周期走向。颜色沿用设计系统 2.3：变强 = 恢复色，稳定 = 二级灰，透支 = 负荷色，恢复中 = 睡眠色，数据不足 = 三级灰。
/// 不使用红色报警。
public enum BSVerdict: Sendable, Hashable, CaseIterable {
    /// 变强。
    case stronger
    /// 稳定。
    case stable
    /// 透支。
    case overreaching
    /// 恢复中。
    case recovering
    /// 数据不足。
    case insufficient

    var title: String {
        switch self {
        case .stronger: "变强"
        case .stable: "稳定"
        case .overreaching: "透支"
        case .recovering: "恢复中"
        case .insufficient: "数据不足"
        }
    }

    var systemImage: String {
        switch self {
        case .stronger: "arrow.up.right"
        case .stable: "equal"
        case .overreaching: "arrow.down.right"
        case .recovering: "bed.double"
        case .insufficient: "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .stronger: BSColor.recovery
        case .stable: Color.secondary
        case .overreaching: BSColor.strain
        case .recovering: BSColor.sleep
        case .insufficient: BSColor.dimmed
        }
    }
}

/// 周期走向标签：图标 + 文字，颜色之外始终带文字，满足"区分颜色"。
public struct BSVerdictChip: View {
    private let verdict: BSVerdict

    /// 创建走向标签。
    public init(_ verdict: BSVerdict) {
        self.verdict = verdict
    }

    public var body: some View {
        HStack(spacing: BSSpace.xxs) {
            Image(systemName: verdict.systemImage)
                .foregroundStyle(verdict.color)
            Text(verdict.title)
                .bsText(.label)
        }
        .padding(.horizontal, BSSpace.xs)
        .padding(.vertical, BSSpace.xxs)
        .background(verdict.color.opacity(BSOpacity.faint), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// 走向表中的一行：一条轴。
public struct BSVerdictRow: Identifiable, Hashable, Sendable {
    /// 稳定标识，点击时回传。
    public let id: String
    /// 轴名称，例如"睡眠"。
    public let name: String
    /// 一行依据，例如"实睡 7 小时 12 分，较前 12 周 +18 分钟"。
    public let basis: String
    /// 走向。
    public let verdict: BSVerdict
    /// 约 12 周的迷你折线数据。
    public let trend: [Double]

    /// 创建一行。
    public init(id: String, name: String, basis: String, verdict: BSVerdict, trend: [Double] = []) {
        self.id = id
        self.name = name
        self.basis = basis
        self.verdict = verdict
        self.trend = trend
    }
}

/// 趋势页 L0：每条轴一行——名称、依据、走向标签、迷你折线（灰色，末端点用走向色）。
public struct BSVerdictGrid: View {
    private let rows: [BSVerdictRow]
    private let isLoading: Bool
    private let onSelect: ((String) -> Void)?

    /// 创建走向表。
    /// - Parameters:
    ///   - rows: 各条轴。
    ///   - isLoading: 为 `true` 时显示骨架。
    ///   - onSelect: 点击某行时回传 `BSVerdictRow.id`（进入该轴的趋势图）。
    public init(rows: [BSVerdictRow], isLoading: Bool = false, onSelect: ((String) -> Void)? = nil) {
        self.rows = rows
        self.isLoading = isLoading
        self.onSelect = onSelect
    }

    public var body: some View {
        BSCard {
            VStack(spacing: BSSpace.s) {
                ForEach(rows) { row in
                    rowView(row)
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
            .redacted(reason: isLoading ? .placeholder : [])
        }
    }

    private func rowView(_ row: BSVerdictRow) -> some View {
        HStack(spacing: BSSpace.s) {
            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                Text(row.name)
                    .bsText(.cardTitle)
                Text(row.basis)
                    .bsText(.caption)
            }
            Spacer(minLength: BSSpace.xs)
            if row.trend.count >= 2 {
                BSMiniLine(points: row.trend, color: BSColor.dimmed, endDotColor: row.verdict.color)
                    .frame(width: BSSize.ringM, height: BSSize.chartMicro)
            }
            BSVerdictChip(row.verdict)
        }
        .frame(minHeight: BSSize.hitTarget)
        .contentShape(.rect)
        .bsTappable(action(for: row))
    }

    private func action(for row: BSVerdictRow) -> (() -> Void)? {
        guard let onSelect else { return nil }
        return { onSelect(row.id) }
    }
}
