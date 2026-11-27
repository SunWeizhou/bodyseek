import SwiftUI

/// 页面骨架：背景色、滚动、页面边距、区块间距、下拉刷新、底部留白、加载骨架。
///
/// 按设计系统第 3 章组织为 L0（`hero`）、L1（`note`）、L2（`sections`）、L3（`links`）。
/// 本组件不包含 `NavigationStack`，由调用方提供；大标题使用系统导航标题。
public struct BSPage<Hero: View, Note: View, Sections: View, Links: View>: View {
    private let title: String
    private let isLoading: Bool
    private let onRefresh: (@Sendable () async -> Void)?
    private let hero: Hero
    private let note: Note
    private let sections: Sections
    private let links: Links
    private var header: BSPageHeaderConfig?

    /// 创建完整页面骨架。
    /// - Parameters:
    ///   - title: 系统大标题。
    ///   - isLoading: 为 `true` 时整页显示骨架。
    ///   - onRefresh: 下拉刷新；为 `nil` 时不启用。
    ///   - hero: L0，每页唯一的最重元素。
    ///   - note: L1，Coach 一句话解读。
    ///   - sections: L2，若干 `BSSection`。
    ///   - links: L3，二级页入口。
    public init(
        _ title: String,
        isLoading: Bool = false,
        onRefresh: (@Sendable () async -> Void)? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder note: () -> Note,
        @ViewBuilder sections: () -> Sections,
        @ViewBuilder links: () -> Links
    ) {
        self.title = title
        self.isLoading = isLoading
        self.onRefresh = onRefresh
        self.hero = hero()
        self.note = note()
        self.sections = sections()
        self.links = links()
    }

    /// 改用一行式标题栏（UI v4 §1.1）：隐藏系统导航栏，标题与副标题同一行，右侧放按钮。
    /// - Parameters:
    ///   - subtitle: 同一行的灰色副标题。
    ///   - trailing: 右侧按钮（`BSHeaderButton` / `BSHeaderMenu`）。
    public func oneLineHeader<Trailing: View>(
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> BSPage {
        var copy = self
        copy.header = BSPageHeaderConfig(subtitle: subtitle, trailing: AnyView(trailing()))
        return copy
    }

    /// 改用一行式标题栏，右侧没有按钮。
    public func oneLineHeader(subtitle: String? = nil) -> BSPage {
        oneLineHeader(subtitle: subtitle) { EmptyView() }
    }

    public var body: some View {
        ScrollViewReader { reader in
            scrollContent
                .environment(\.bsScrollTo, scrollAction(reader))
        }
    }

    private func scrollAction(_ reader: ScrollViewProxy) -> @MainActor (String) -> Void {
        { id in
            withAnimation(.spring(BSMotion.standard)) {
                reader.scrollTo(id, anchor: .top)
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                headerRow
                VStack(alignment: .leading, spacing: BSSpace.l) {
                    hero
                        .frame(maxWidth: .infinity)
                    note
                    sections
                    links
                }
            }
            .padding(.horizontal, BSSpace.m)
            .padding(.top, header == nil ? BSSpace.xs : BSSpace.none)
            .padding(.bottom, BSSpace.xl)
            .redacted(reason: isLoading ? .placeholder : [])
        }
        .background(BSColor.canvas.ignoresSafeArea())
        .modifier(BSRefreshModifier(action: onRefresh))
        .navigationTitle(title)
        .modifier(BSPageChromeModifier(usesHeader: header != nil))
        .bodyseekScrollEdgeEffect()
    }

    @ViewBuilder
    private var headerRow: some View {
        if let header {
            BSPageHeader(title, subtitle: header.subtitle) {
                header.trailing
            }
        }
    }
}

private struct BSScrollToKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String) -> Void)? = nil
}

public extension EnvironmentValues {
    /// 页面内滚动到带 `.id(_:)` 的位置；由 `BSPage` 注入，页面外为 `nil`。
    var bsScrollTo: (@MainActor (String) -> Void)? {
        get { self[BSScrollToKey.self] }
        set { self[BSScrollToKey.self] = newValue }
    }
}

private struct BSPageHeaderConfig {
    let subtitle: String?
    let trailing: AnyView
}

private struct BSPageChromeModifier: ViewModifier {
    let usesHeader: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if usesHeader {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.navigationBarTitleDisplayMode(.large)
        }
        #else
        content
        #endif
    }
}

public extension BSPage where Note == EmptyView, Links == EmptyView {
    /// 创建只有 L0 和 L2 的页面骨架。
    init(
        _ title: String,
        isLoading: Bool = false,
        onRefresh: (@Sendable () async -> Void)? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder sections: () -> Sections
    ) {
        self.init(
            title,
            isLoading: isLoading,
            onRefresh: onRefresh,
            hero: hero,
            note: { EmptyView() },
            sections: sections,
            links: { EmptyView() }
        )
    }
}

private struct BSRefreshModifier: ViewModifier {
    let action: (@Sendable () async -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}
