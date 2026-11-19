import SwiftUI

public extension ToolbarItemPlacement {
    static var bodyseekLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var bodyseekTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

public extension View {
    @ViewBuilder
    func bodyseekNavigationBarInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekTransparentNavigationBar() -> some View {
        #if os(iOS)
        self.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekHideTabBar(_ hidden: Bool) -> some View {
        #if os(iOS)
        self.toolbar(hidden ? .hidden : .automatic, for: .tabBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekMinimizeTabBarOnScroll() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekZoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func bodyseekSelectionHaptic<V: Equatable>(trigger: V) -> some View {
        #if os(iOS)
        self.sensoryFeedback(.selection, trigger: trigger)
        #else
        self
        #endif
    }
}
