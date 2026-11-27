import SwiftUI

private struct BSOpenSettingsKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

public extension EnvironmentValues {
    /// 一级页面标题栏头像的动作；由根视图注入，为 `nil` 时不显示头像。
    var bsOpenSettings: (@MainActor () -> Void)? {
        get { self[BSOpenSettingsKey.self] }
        set { self[BSOpenSettingsKey.self] = newValue }
    }
}

/// 一行式标题栏（UI v4 §1.1）：标题 + 同一行灰色副标题 + 右侧圆形按钮与头像。
///
/// 高度为 `BSSize.hitTarget`（44pt）。作为滚动内容的第一行使用，不依赖系统导航栏。
public struct BSPageHeader<Trailing: View>: View {
    @Environment(\.bsOpenSettings) private var openSettings

    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    /// 创建标题栏。
    /// - Parameters:
    ///   - title: 页面标题。
    ///   - subtitle: 同一行的灰色副标题，例如日期。
    ///   - trailing: 右侧按钮，最多两个，使用 `BSHeaderButton` 或 `BSHeaderMenu`。
    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BSSpace.xs) {
            titleText
            subtitleText
            Spacer(minLength: BSSpace.none)
            trailingButtons
        }
        .frame(minHeight: BSSize.hitTarget)
    }

    private var titleText: some View {
        Text(title)
            .font(.title2.bold())
            .lineLimit(1)
            .layoutPriority(1)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let subtitle {
            Text(subtitle)
                .bsText(.label)
                .lineLimit(1)
        }
    }

    private var trailingButtons: some View {
        HStack(spacing: BSSpace.xxs) {
            trailing
            if let openSettings {
                BSHeaderButton(systemImage: "person.crop.circle", label: "设置", identifier: "settings-button") {
                    openSettings()
                }
            }
        }
    }
}

public extension BSPageHeader where Trailing == EmptyView {
    /// 创建没有右侧按钮的标题栏。
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// 标题栏的圆形图标按钮：`BSSize.avatar` 圆底，点击区域 `BSSize.hitTarget`。
public struct BSHeaderButton: View {
    private let systemImage: String
    private let label: String
    private let identifier: String
    private let action: () -> Void

    /// 创建按钮。
    /// - Parameters:
    ///   - systemImage: SF Symbol 名称。
    ///   - label: 无障碍标签。
    ///   - identifier: `accessibilityIdentifier`。
    ///   - action: 点击动作。
    public init(systemImage: String, label: String, identifier: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            BSHeaderGlyph(systemImage: systemImage)
        }
        .buttonStyle(BSPressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// 标题栏的圆形菜单按钮，外观同 `BSHeaderButton`。
public struct BSHeaderMenu<Content: View>: View {
    private let systemImage: String
    private let label: String
    private let identifier: String
    private let content: Content

    /// 创建菜单按钮。
    public init(
        systemImage: String,
        label: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.label = label
        self.identifier = identifier
        self.content = content()
    }

    public var body: some View {
        Menu {
            content
        } label: {
            BSHeaderGlyph(systemImage: systemImage)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// 标题栏圆形图标的外观，供 `NavigationLink` 等自定义入口作为标签使用。
public struct BSHeaderGlyph: View {
    private let systemImage: String

    /// 创建圆形图标外观。
    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: BSSize.avatar, height: BSSize.avatar)
            .background(BSColor.surface, in: Circle())
            .frame(minWidth: BSSize.hitTarget, minHeight: BSSize.hitTarget)
    }
}
