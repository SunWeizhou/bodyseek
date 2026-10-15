import Foundation
import SwiftData

/// Active training plans. Every reader uses this query so the newest update
/// wins when more than one plan is marked active.
final class TrainingPlanRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchActivePlans() throws -> [TrainingPlanRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    /// Every plan, including inactive ones. Callers that walk plan days do not
    /// depend on order.
    func fetchAll() throws -> [TrainingPlanRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingPlanRecord>())
    }

    func fetchAllSortedByUpdatedAt(newestFirst: Bool = true) throws -> [TrainingPlanRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: order)]
        ))
    }

    func fetch(id: UUID) throws -> [TrainingPlanRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    func fetch(idempotencyKey: String) throws -> [TrainingPlanRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate { $0.idempotencyKey == idempotencyKey }
        ))
    }
}

/// Proposed plan changes. Newest creation time comes first.
final class TrainingPlanAdaptationRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [TrainingPlanAdaptationRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>())
    }

    func fetchProposed(newestFirst: Bool = true) throws -> [TrainingPlanAdaptationRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>(
            predicate: #Predicate { $0.status == "proposed" },
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }

    func fetchProposed(planId: UUID) throws -> [TrainingPlanAdaptationRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>(
            predicate: #Predicate { $0.planId == planId && $0.status == "proposed" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    /// Newest proposals only. Callers that match a run ID must keep this cap,
    /// so an older run outside the window is treated as unseen.
    func fetchRecent(limit: Int = 100) throws -> [TrainingPlanAdaptationRecord] {
        var descriptor = FetchDescriptor<TrainingPlanAdaptationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
}
