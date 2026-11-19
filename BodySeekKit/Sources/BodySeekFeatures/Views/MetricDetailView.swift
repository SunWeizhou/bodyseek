import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct MetricDetailView: View {
    @Bindable var store: StoreOf<MetricDetailFeature>
    private let zoomNamespace: Namespace.ID?
    private let zoomPrefix: String

    public init(
        store: StoreOf<MetricDetailFeature>,
        zoomNamespace: Namespace.ID? = nil,
        zoomPrefix: String = "today-metric"
    ) {
        self.store = store
        self.zoomNamespace = zoomNamespace
        self.zoomPrefix = zoomPrefix
    }

    public var body: some View {
        let content = ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerCard

                horizonPicker

                detailBody

                provenanceCard

                Button {
                    store.send(.askCoachTapped)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("向 Coach 追问\(store.kind.title)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(BevelTheme.onBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityIdentifier("detail-ask-coach")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle(store.kind.title)
        .bodyseekNavigationBarInline()
        .bodyseekHideTabBar(!store.isSheet)
        .toolbar {
            if store.isSheet {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button {
                        store.send(.closeTapped)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("metric-detail-close")
                }
            }
        }

        if let zoomNamespace, !store.isSheet {
            content.bodyseekZoomTransition(sourceID: "\(zoomPrefix)-\(store.kind.rawValue)", in: zoomNamespace)
        } else {
            content
        }
    }

    private var headerCard: some View {
        let tint = BevelTheme.color(for: store.kind)
        return BevelCard {
            HStack(spacing: 16) {
                MetricRingView(score: store.currentScore, diameter: 86, lineWidth: 10)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(store.currentScore.badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.14), in: Capsule())

                        if let delta = store.currentScore.baselineDelta {
                            let sign = delta >= 0 ? "+" : ""
                            Text("较基线 \(sign)\(delta)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.deviationInk)
                        }
                    }

                    Text(store.kind.shortExplanation)
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var horizonPicker: some View {
        Picker("时间窗口", selection: Binding(
            get: { store.horizon },
            set: { store.send(.horizonChanged($0)) }
        )) {
            ForEach(TrendHorizon.allCases) { horizon in
                Text(horizon.title).tag(horizon)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("detail-horizon-picker")
    }

    @ViewBuilder
    private var detailBody: some View {
        let day = store.snapshot.today
        let snap = store.activeChartSnapshot
        let onSelect: @MainActor (Date?) -> Void = { date in
            store.send(.selectedDateChanged(date))
        }

        switch store.kind {
        case .recovery:
            RecoveryDetailView(
                day: day,
                historyDays: store.snapshot.historyDays,
                activeChartSnapshot: snap,
                score: store.currentScore,
                onSelectDate: onSelect
            )
        case .sleep:
            SleepDetailView(
                day: day,
                historyDays: store.snapshot.historyDays,
                activeChartSnapshot: snap,
                sleepGoalMinutes: store.sleepGoalMinutes,
                onSelectDate: onSelect
            )
        case .strain:
            StrainDetailView(
                day: day,
                trainingLoad: store.snapshot.trainingLoad,
                activeChartSnapshot: snap,
                onSelectDate: onSelect
            )
        case .stress:
            StressDetailView(
                day: day,
                activeChartSnapshot: snap,
                onSelectDate: onSelect
            )
        case .energy:
            EnergyDetailView(
                day: day,
                activeChartSnapshot: snap,
                onSelectDate: onSelect
            )
        }
    }

    private var provenanceCard: some View {
        let day = store.snapshot.today
        let sourcesText = day.raw.sourceNames.isEmpty ? store.snapshot.sourceLabel : day.raw.sourceNames.joined(separator: " · ")
        let covText = "\(store.activeChartSnapshot.coveredDays)/\(store.activeChartSnapshot.totalDays) 天"

        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("L3 数据溯源与算法边界")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                provenanceRow("算法版本", value: store.currentScore.algorithmVersion.description)
                provenanceRow("窗口样本覆盖", value: covText)
                provenanceRow("生理日切点", value: "\(day.dayKey.isoString)（04:00）")
                provenanceRow("数据来源", value: sourcesText)
                if let missingReason = store.currentScore.availability.reasonText {
                    provenanceRow("缺口说明", value: missingReason)
                }
            }
        }
    }

    private func provenanceRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}
