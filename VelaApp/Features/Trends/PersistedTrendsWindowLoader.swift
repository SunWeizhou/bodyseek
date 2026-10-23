import Foundation
import SwiftData
import SwiftUI

struct TrendsWindowLoad {
    var snapshots: [DailyHealthSnapshot]
    var errorMessage: String?
    var isPreview: Bool
    var rawCoverage: HistoricalCoverageSummary? = nil
}

/// Reads persisted daily summaries for one trend window and converts them to
/// value snapshots before they reach `TrendsStore`. The view does not fetch.
@MainActor
struct PersistedTrendsWindowLoader {
    let modelContext: ModelContext

    func load(horizon: HealthTrendHorizon, endingAt selectedDate: Date) -> TrendsWindowLoad {
        #if DEBUG
        if DailySummaryUseCase.isPreviewDashboardEnabled() {
            return TrendsWindowLoad(
                snapshots: PreviewDataFactory.makeTrendSnapshots(endingAt: selectedDate),
                errorMessage: nil,
                isPreview: true
            )
        }
        #endif
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let start = horizon.historyFetchStart(endingExclusive: end, calendar: calendar)
        do {
            let records = try SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
                .fetch(in: DateRangeQuery(start: start, end: end))
            return TrendsWindowLoad(
                snapshots: records.map(snapshot(from:)),
                errorMessage: nil,
                isPreview: false,
                rawCoverage: HistoricalCoverageSummary(snapshots: records.map(snapshot(from:)))
            )
        } catch {
            return TrendsWindowLoad(
                snapshots: [],
                errorMessage: L10n.t(
                    "Trend history could not be read. Retry to load it again.",
                    "趋势历史暂时无法读取，请重试后再查看。"
                ),
                isPreview: false
            )
        }
    }

    private func snapshot(from record: DailyHealthSummaryRecord) -> DailyHealthSnapshot {
        var snapshot = record.toSnapshot()
        // Trends sorts duplicate days by `createdAt` and keeps the last row.
        // `updatedAt` is the newest write, so that tie-break still prefers the
        // later summary.
        snapshot.createdAt = record.updatedAt
        return snapshot
    }
}

/// Composition adapter. Trends rendering does not read SwiftData or the
/// dashboard view model; the shell supplies the selected day, findings, and
/// persistence loader as values.
struct VelaTrendsHost: View {
    let selectedDate: Date
    let dashboard: DashboardSummary

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var appState = VelaAppState.shared

    var body: some View {
        VelaTrendsView(
            selectedDate: selectedDate,
            dashboard: dashboard,
            localDataRevision: appState.localDataRevision,
            loader: PersistedTrendsWindowLoader(modelContext: modelContext),
            onAskCoach: { question in
                appState.routeToCoach(question: question, surface: .trends)
            }
        )
    }
}
