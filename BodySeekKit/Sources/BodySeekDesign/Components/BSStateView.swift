import SwiftUI

/// `BSStateView` 的状态类型。
public enum BSStateKind: Sendable, Hashable, CaseIterable {
    /// 数据缺失。
    case missing
    /// 未授权。
    case unauthorized
    /// 空数据。
    case empty
    /// 出错。
    case error

    var systemImage: String {
        switch self {
        case .missing: "minus.circle"
        case .unauthorized: "lock"
        case .empty: "tray"
        case .error: "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .missing: "数据缺失"
        case .unauthorized: "未授权"
        case .empty: "暂无数据"
        case .error: "出错了"
        }
    }
}

/// 统一的状态视图：图标 + 一句原因 + 一个操作按钮。
public struct BSStateView: View {
    private let kind: BSStateKind
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// 创建状态视图。
    /// - Parameters:
    ///   - kind: 状态类型，决定图标和标题。
    ///   - message: 一句原因。
    ///   - actionTitle: 操作按钮标题；需要与 `action` 同时提供才显示。
    ///   - action: 操作按钮动作（例如"去授权"）。
    public init(
        _ kind: BSStateKind,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: BSSpace.xs) {
            Image(systemName: kind.systemImage)
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text(kind.title)
                .bsText(.cardTitle)
            Text(message)
                .bsText(.label)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .frame(minHeight: BSSize.hitTarget)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(BSSpace.m)
        .accessibilityElement(children: .contain)
    }
}
