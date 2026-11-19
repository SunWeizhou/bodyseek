import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct RootTabView: View {
    @Bindable var store: StoreOf<AppFeature>
    @AppStorage("bodyseek.onboardingCompleted") private var persistedOnboardingCompleted = false
    @Namespace private var zoomNamespace

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasCompletedOnboarding || persistedOnboardingCompleted {
                mainTabView
            } else {
                OnboardingView(
                    onAuthorizeAndStart: {
                        persistedOnboardingCompleted = true
                        store.send(.onboardingAuthorizeTapped)
                    },
                    onStartDirectly: {
                        persistedOnboardingCompleted = true
                        store.send(.onboardingSkipTapped)
                    }
                )
            }
        }
        .tint(BevelTheme.brand)
        .onAppear {
            store.send(.onAppear)
        }
        .sheet(
            item: $store.scope(state: \.settings, action: \.settings)
        ) { settingsStore in
            SettingsView(store: settingsStore)
        }
        .sheet(
            isPresented: Binding(
                get: { store.isCheckInPresented },
                set: { store.send(.checkInPresented($0)) }
            )
        ) {
            CheckInSheetView(
                dayKey: store.snapshot.referenceDate.physiologicalDayKey(),
                initialCheckIn: store.today.todayCheckIn,
                fallbackEnergy: store.today.subjectiveFeeling,
                onSave: { checkIn in store.send(.checkInSaved(checkIn)) },
                onDismiss: { store.send(.checkInPresented(false)) }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var mainTabView: some View {
        TabView(
            selection: Binding(
                get: { store.selectedTab },
                set: { store.send(.tabSelected($0)) }
            )
        ) {
            Tab("今日", systemImage: "heart.text.square", value: AppFeature.AppTab.today) {
                NavigationStack(path: $store.scope(state: \.todayPath, action: \.todayPath)) {
                    TodayView(
                        store: store.scope(state: \.today, action: \.today),
                        zoomNamespace: zoomNamespace
                    )
                } destination: { detailStore in
                    MetricDetailView(
                        store: detailStore,
                        zoomNamespace: zoomNamespace,
                        zoomPrefix: "today-metric"
                    )
                }
            }

            Tab("健身", systemImage: "dumbbell.fill", value: AppFeature.AppTab.workout) {
                NavigationStack {
                    WorkoutView(store: store.scope(state: \.workout, action: \.workout))
                }
            }

            Tab("趋势", systemImage: "chart.xyaxis.line", value: AppFeature.AppTab.trends) {
                NavigationStack(path: $store.scope(state: \.trendsPath, action: \.trendsPath)) {
                    TrendsView(
                        store: store.scope(state: \.trends, action: \.trends),
                        zoomNamespace: zoomNamespace
                    )
                } destination: { detailStore in
                    MetricDetailView(
                        store: detailStore,
                        zoomNamespace: zoomNamespace,
                        zoomPrefix: "trends-metric"
                    )
                }
            }

            Tab("问身体", systemImage: "sparkles", value: AppFeature.AppTab.coach, role: .search) {
                NavigationStack {
                    CoachView(store: store.scope(state: \.coach, action: \.coach))
                }
            }
        }
        .bodyseekMinimizeTabBarOnScroll()
    }
}
