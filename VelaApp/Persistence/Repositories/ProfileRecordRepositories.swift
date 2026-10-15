import Foundation
import SwiftData

/// The current onboarding profile. When more than one row exists, the newest
/// update is the profile the product reads.
final class OnboardingRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchLatest() throws -> OnboardingState? {
        var descriptor = FetchDescriptor<OnboardingState>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

/// Coach artifacts. Windowed reads are inclusive and newest first.
final class CoachArtifactRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [CoachArtifactRecord] {
        try modelContext.fetch(FetchDescriptor<CoachArtifactRecord>())
    }

    func fetchArtifacts(from start: Date, through end: Date) throws -> [CoachArtifactRecord] {
        try modelContext.fetch(FetchDescriptor<CoachArtifactRecord>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt <= end },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    func fetchArtifact(id: UUID) throws -> CoachArtifactRecord? {
        try modelContext.fetch(FetchDescriptor<CoachArtifactRecord>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    func fetchArtifacts(sourceContextHash: String) throws -> [CoachArtifactRecord] {
        try modelContext.fetch(FetchDescriptor<CoachArtifactRecord>(
            predicate: #Predicate { $0.sourceContextHash == sourceContextHash }
        ))
    }
}

/// Generated agent artifacts, newest first.
final class AgentArtifactRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllSortedByCreatedAt(newestFirst: Bool = true) throws -> [AgentArtifactRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<AgentArtifactRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }

    /// Artifacts of one type written from the same source context. Callers that
    /// update a plan take the first stored row.
    func fetch(type: String, sourceContextHash: String) throws -> [AgentArtifactRecord] {
        try modelContext.fetch(FetchDescriptor<AgentArtifactRecord>(
            predicate: #Predicate { $0.type == type && $0.sourceContextHash == sourceContextHash }
        ))
    }
}

/// Lab and body-composition markers. Newest measurement comes first unless a
/// caller is writing an export in chronological order.
final class BiomarkerRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllSortedByDate(newestFirst: Bool = true, limit: Int? = nil) throws -> [BiomarkerRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        var descriptor = FetchDescriptor<BiomarkerRecord>(
            sortBy: [SortDescriptor(\.date, order: order)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }
}

/// Agent runs, newest start first. A successful-run lookup is how evening sync
/// decides whether it already finished today.
final class AgentRunRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllSortedByStartedAt(newestFirst: Bool = true) throws -> [AgentRunRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<AgentRunRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: order)]
        ))
    }

    func fetchSuccessful(agentName: String) throws -> [AgentRunRecord] {
        try modelContext.fetch(FetchDescriptor<AgentRunRecord>(
            predicate: #Predicate { $0.agentName == agentName && $0.status == "success" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
    }
}

/// Product events. Quality snapshots use an inclusive time window, newest
/// first. Diagnostics read the whole table.
final class VelaEventRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [VelaEventRecord] {
        try modelContext.fetch(FetchDescriptor<VelaEventRecord>())
    }

    func fetch(from start: Date, through end: Date) throws -> [VelaEventRecord] {
        try modelContext.fetch(FetchDescriptor<VelaEventRecord>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))
    }
}

/// Local wiki rows. Sync walks the whole table. The archive shows the newest
/// update first.
final class UserWikiDocumentRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [UserWikiDocumentRecord] {
        try modelContext.fetch(FetchDescriptor<UserWikiDocumentRecord>())
    }

    func fetchAllSortedByUpdatedAt(newestFirst: Bool = true) throws -> [UserWikiDocumentRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<UserWikiDocumentRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: order)]
        ))
    }
}

/// Coach conversations that are still in the history drawer. Archived sessions
/// stay out, and the newest update is first.
final class CoachSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchUnarchived() throws -> [CoachSessionRecord] {
        try modelContext.fetch(FetchDescriptor<CoachSessionRecord>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }
}
