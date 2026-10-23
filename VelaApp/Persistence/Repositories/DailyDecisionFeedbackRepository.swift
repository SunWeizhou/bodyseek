import Foundation
import SwiftData

/// Decision feedback is one row per health day.
final class DailyDecisionFeedbackRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [DailyDecisionFeedbackRecord] {
        try modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>())
    }

    func fetchAllSortedByCreatedAt(newestFirst: Bool = true) throws -> [DailyDecisionFeedbackRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }

    func fetchRecord(dayIdentifier: String) throws -> DailyDecisionFeedbackRecord? {
        try modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier }
        )).first
    }

    /// Feedback touched at or after `start`, including later updates.
    func fetchUpdated(onOrAfter start: Date) throws -> [DailyDecisionFeedbackRecord] {
        try modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>(
            predicate: #Predicate { $0.updatedAt >= start }
        ))
    }

    /// Update time is inside `[start, end]`, and the row was created at or before `createdThrough`.
    func fetchUpdated(
        from start: Date,
        through end: Date,
        createdAtOrBefore createdThrough: Date
    ) throws -> [DailyDecisionFeedbackRecord] {
        try modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>(
            predicate: #Predicate {
                $0.updatedAt >= start && $0.updatedAt <= end && $0.createdAt <= createdThrough
            }
        ))
    }
}
