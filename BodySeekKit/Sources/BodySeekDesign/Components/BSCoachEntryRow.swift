import SwiftUI

/// Coach 解读入口（UI v4 §2.2）：一行紧凑卡片，Coach 徽记 + 标题与生成时间 + 两行摘要 + 右侧标签。
///
/// 点开是 sheet（由调用方实现）。今日"今日建议"、健身"今天练什么"、营养"饮食建议"共用。
public struct BSCoachEntryRow: View {
    private let title: String
    private let meta: String?
    private let summary: String
    private let tag: String?
    private let identifier: String?
    private let action: () -> Void

    /// 创建入口行。
    /// - Parameters:
    ///   - title: 标题，例如"今日建议"。
    ///   - meta: 标题旁的灰色说明，例如生成时间。
    ///   - summary: 两行内截断的摘要。
    ///   - tag: 右侧标签，例如"3 条行动"。
    ///   - identifier: 按钮的无障碍标识。
    ///   - action: 点击动作（打开 sheet）。
    public init(
        title: String,
        meta: String? = nil,
        summary: String,
        tag: String? = nil,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.meta = meta
        self.summary = summary
        self.tag = tag
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            BSCard {
                HStack(spacing: BSSpace.s) {
                    BSIconBlock(systemImage: "sparkles", tint: BSColor.tint)
                    textColumn
                    Spacer(minLength: BSSpace.xxs)
                    trailing
                }
            }
        }
        .buttonStyle(.bsPressable)
        .accessibilityElement(children: .combine)
        .modifier(BSOptionalIdentifier(identifier: identifier))
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: BSSpace.xxs) {
            HStack(spacing: BSSpace.xs) {
                Text(title)
                    .bsText(.cardTitle)
                if let meta {
                    Text(meta)
                        .bsText(.caption)
                }
            }
            Text(summary)
                .bsText(.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: BSSpace.xxs) {
            if let tag {
                Text(tag)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSColor.tint)
                    .padding(.horizontal, BSSpace.xs)
                    .padding(.vertical, BSSpace.xxs)
                    .background(BSColor.tint.opacity(BSOpacity.faint), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .bsText(.caption)
        }
    }
}
