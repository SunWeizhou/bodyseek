import SwiftUI

/// 区块：标题 + 可选的"全部"按钮 + 内容。
public struct BSSection<Content: View>: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let content: Content

    /// 创建区块。
    /// - Parameters:
    ///   - title: 区块标题，按内容命名（如"昨夜睡眠"），不用"概览"这类笼统的词。
    ///   - actionTitle: 右侧按钮标题；需要与 `action` 同时提供才显示。
    ///   - action: 右侧按钮动作。
    ///   - content: 区块内容，最多 3 张卡。
    public init(
        _ title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSSpace.s) {
            HStack {
                Text(title)
                    .bsText(.pageSection)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: BSSpace.xs)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline)
                        .buttonStyle(BSPressableStyle())
                        .frame(minHeight: BSSize.hitTarget)
                }
            }
            content
        }
    }
}
