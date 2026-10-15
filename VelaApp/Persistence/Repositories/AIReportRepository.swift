import Foundation
import SwiftData

protocol AIReportRepository {
    func save(_ report: AIReportRecord) throws
    func recent(type: String?, limit: Int) throws -> [AIReportRecord]
}

final class SwiftDataAIReportRepository: AIReportRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(_ report: AIReportRecord) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "AIReportRepository: save", modelContext: modelContext)
        modelContext.insert(report)
        try modelContext.save()
    }

    func recent(type: String? = nil, limit: Int = 20) throws -> [AIReportRecord] {
        var descriptor: FetchDescriptor<AIReportRecord>
        if let type {
            descriptor = FetchDescriptor<AIReportRecord>(
                predicate: #Predicate { $0.type == type },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<AIReportRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        }
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    /// Every report of one type. Callers that only need the newest row should use `recent(type:limit:)`.
    func fetch(type: String, newestFirst: Bool = true) throws -> [AIReportRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<AIReportRecord>(
            predicate: #Predicate { $0.type == type },
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }

    func fetchAllSortedByCreatedAt(newestFirst: Bool = true) throws -> [AIReportRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<AIReportRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }
}
