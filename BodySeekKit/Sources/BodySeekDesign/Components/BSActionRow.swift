import SwiftUI

/// 动作执行状态。
public enum BSActionStatus: Sendable, Hashable, CaseIterable {
    /// 待执行。
    case idle
    /// 执行中。
    case running
    /// 已完成。
    case done
    /// 已撤销。
    case undone
    /// 失败。
    case failed
}

/// 动作回执的授权级别（设计系统 4.3、ADR 0020）：C 级必须确认，不产生回执。
public enum BSActionLevel: Sendable, Hashable, CaseIterable {
    /// A 级：自动执行，回执里给出撤销按钮。
    case automatic
    /// B 级：自动执行并突出提示，展示改动前后对比，24 小时内可撤销。
    case highlighted
}

/// 触觉反馈：成功、失败、撤销各一次，与回执出现在同一个状态变化上。仅 iOS。
///
/// 三种反馈拆成三个小修饰符，避免 iOS 的类型检查器在一条长修饰符链上超时。
struct BSOutcomeFeedback: ViewModifier {
    let status: BSActionStatus

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .modifier(BSDoneFeedback(status: status))
            .modifier(BSFailedFeedback(status: status))
            .modifier(BSUndoneFeedback(status: status))
        #else
        content
        #endif
    }
}

#if os(iOS)
private struct BSDoneFeedback: ViewModifier {
    let status: BSActionStatus

    func body(content: Content) -> some View {
        content.sensoryFeedback(.success, trigger: status) { _, new in new == .done }
    }
}

private struct BSFailedFeedback: ViewModifier {
    let status: BSActionStatus

    func body(content: Content) -> some View {
        content.sensoryFeedback(.error, trigger: status) { _, new in new == .failed }
    }
}

private struct BSUndoneFeedback: ViewModifier {
    let status: BSActionStatus

    func body(content: Content) -> some View {
        content.sensoryFeedback(.impact(weight: .light), trigger: status) { _, new in new == .undone }
    }
}
#endif

/// 一条行动建议：标题 + 依据 + "执行"按钮；执行后变成回执状态。
public struct BSActionRow: View {
    private let title: String
    private let basis: String
    private let status: BSActionStatus
    private let actionTitle: String
    private let onExecute: (() -> Void)?
    private let onUndo: (() -> Void)?

    /// 创建行动行。
    /// - Parameters:
    ///   - title: 建议标题。
    ///   - basis: 依据（来自简报的证据）。
    ///   - status: 当前状态。
    ///   - actionTitle: 执行按钮标题。
    ///   - onExecute: 执行动作；为 `nil` 时不显示按钮。
    ///   - onUndo: 撤销动作；完成状态下显示。
    public init(
        title: String,
        basis: String,
        status: BSActionStatus = .idle,
        actionTitle: String = "执行",
        onExecute: (() -> Void)? = nil,
        onUndo: (() -> Void)? = nil
    ) {
        self.title = title
        self.basis = basis
        self.status = status
        self.actionTitle = actionTitle
        self.onExecute = onExecute
        self.onUndo = onUndo
    }

    public var body: some View {
        BSCard {
            HStack(spacing: BSSpace.s) {
                VStack(alignment: .leading, spacing: BSSpace.xxs) {
                    Text(title)
                        .bsText(.cardTitle)
                    Text(basis)
                        .bsText(.label)
                }
                Spacer(minLength: BSSpace.xs)
                trailing
            }
        }
        .modifier(BSOutcomeFeedback(status: status))
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .idle:
            if let onExecute {
                Button(actionTitle, action: onExecute)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(BSColor.tint)
                    .frame(minHeight: BSSize.hitTarget)
            }
        case .running:
            ProgressView()
        case .done:
            HStack(spacing: BSSpace.xs) {
                Label("已完成", systemImage: "checkmark.circle.fill")
                    .bsText(.label)
                if let onUndo {
                    Button("撤销", action: onUndo)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(minHeight: BSSize.hitTarget)
                }
            }
        case .undone:
            Label("已撤销", systemImage: "arrow.uturn.backward.circle")
                .bsText(.label)
        case .failed:
            Label("失败", systemImage: "exclamationmark.circle")
                .bsText(.label)
        }
    }
}

/// 动作回执：改了什么、改在哪一天、撤销按钮。B 级额外显示改动前后对比。
public struct BSReceipt: View {
    private let title: String
    private let detail: String
    private let level: BSActionLevel
    private let status: BSActionStatus
    private let before: String?
    private let after: String?
    private let failureReason: String?
    private let onUndo: (() -> Void)?
    private let undoIdentifier: String

    /// 创建回执。
    /// - Parameters:
    ///   - title: 做了什么，例如"已记录午餐"。
    ///   - detail: 改在哪一天、改了哪里。
    ///   - level: A 或 B 级。
    ///   - status: 完成、已撤销或失败。
    ///   - before: B 级：改动前的值。
    ///   - after: B 级：改动后的值。
    ///   - failureReason: 失败时显示的原因。
    ///   - onUndo: 撤销动作；仅在完成状态下显示按钮。
    ///   - undoIdentifier: 撤销按钮的无障碍标识，便于 UI 测试单独点击。
    public init(
        title: String,
        detail: String,
        level: BSActionLevel = .automatic,
        status: BSActionStatus = .done,
        before: String? = nil,
        after: String? = nil,
        failureReason: String? = nil,
        onUndo: (() -> Void)? = nil,
        undoIdentifier: String = "bs-receipt-undo"
    ) {
        self.title = title
        self.detail = detail
        self.level = level
        self.status = status
        self.before = before
        self.after = after
        self.failureReason = failureReason
        self.onUndo = onUndo
        self.undoIdentifier = undoIdentifier
    }

    public var body: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                HStack(spacing: BSSpace.xs) {
                    Label(title, systemImage: statusImage)
                        .bsText(.cardTitle)
                    Spacer(minLength: BSSpace.xs)
                    if status == .done, let onUndo {
                        Button("撤销", action: onUndo)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(minHeight: BSSize.hitTarget)
                            .accessibilityIdentifier(undoIdentifier)
                    }
                }
                Text(status == .failed ? (failureReason ?? detail) : detail)
                    .bsText(.label)
                if level == .highlighted, let before, let after {
                    HStack(spacing: BSSpace.xs) {
                        Text(before)
                            .bsText(.label)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(after)
                            .bsText(.number)
                    }
                }
                Text(footnote)
                    .bsText(.caption)
            }
        }
        .modifier(BSOutcomeFeedback(status: status))
        // 用 contain 而不是 combine：撤销按钮要能被单独点击。
        .accessibilityElement(children: .contain)
    }

    private var statusImage: String {
        switch status {
        case .idle, .running, .done: "checkmark.circle.fill"
        case .undone: "arrow.uturn.backward.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    private var footnote: String {
        switch level {
        case .automatic: "自动执行，可撤销"
        case .highlighted: "已自动修改，24 小时内可撤销"
        }
    }
}
