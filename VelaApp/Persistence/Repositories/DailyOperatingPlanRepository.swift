import Foundation
import SwiftData

/// One operating plan per health day. When more than one row exists, the
/// newest `generatedAt` is the plan the product surfaces.
final class DailyOperatingPlanRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchPlans(dayIdentifier: String) throws -> [DailyOperatingPlanRecord] {
        try modelContext.fetch(FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        ))
    }

    func fetchLatest(dayIdentifier: String) throws -> DailyOperatingPlanRecord? {
        var descriptor = FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchPlans(generatedOnOrAfter start: Date) throws -> [DailyOperatingPlanRecord] {
        try modelContext.fetch(FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate { $0.generatedAt >= start }
        ))
    }
}
