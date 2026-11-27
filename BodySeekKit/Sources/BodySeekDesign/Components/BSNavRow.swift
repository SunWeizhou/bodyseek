import SwiftUI

/// 跳转行：图标 + 标题 + 次要值 + 箭头。基于系统 `NavigationLink`，需要放在 `NavigationStack` 里。
public struct BSNavRow<Destination: View>: View {
    private let title: String
    private let systemImage: String?
    private let value: String?
    private let badge: String?
    private let destination: Destination

    /// 创建跳转行。
    /// - Parameters:
    ///   - title: 标题。
    ///   - systemImage: 前置图标（SF Symbols）。
    ///   - value: 右侧次要值。
    ///   - badge: 标题后的小标签，例如"实验"。
    ///   - destination: 目标页面。
    public init(
        _ title: String,
        systemImage: String? = nil,
        value: String? = nil,
        badge: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.badge = badge
        self.destination = destination()
    }

    public var body: some View {
        NavigationLink {
            destination
        } label: {
            rowLabel
        }
        .buttonStyle(BSPressableStyle())
    }

    private var rowLabel: some View {
        HStack(spacing: BSSpace.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .bsText(.body)
            if let badge {
                Text(badge)
                    .bsText(.caption)
                    .padding(.horizontal, BSSpace.xs)
                    .padding(.vertical, BSSpace.xxs)
                    .background(BSColor.surfaceInset, in: Capsule())
            }
            Spacer(minLength: BSSpace.xs)
            if let value {
                Text(value)
                    .bsText(.label)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: BSSize.hitTarget)
        .contentShape(.rect)
    }
}

/// 实验室入口行：一个带"实验"标签的 `BSNavRow`，点进去是二级页。默认应放在页面最下方。
public struct BSLabEntry<Destination: View>: View {
    private let title: String
    private let value: String?
    private let destination: Destination

    /// 创建实验室入口行。
    /// - Parameters:
    ///   - title: 标题，例如"明日预测"。
    ///   - value: 右侧次要值。
    ///   - destination: 目标页面。
    public init(
        _ title: String,
        value: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.value = value
        self.destination = destination()
    }

    public var body: some View {
        BSNavRow(title, systemImage: "testtube.2", value: value, badge: "实验") {
            destination
        }
    }
}
