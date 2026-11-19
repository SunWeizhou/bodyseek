import BodySeekCore
import Foundation
import GRDB
import os

public struct LegacyImportPayload: Sendable, Codable {
    public let templates: [WorkoutTemplate]
    public let sessions: [LoggedWorkoutSession]
    public let memories: [AthleteMemoryItem]
    public let messages: [CoachMessage]
    public let checkIns: [DailyCheckIn]

    public init(
        templates: [WorkoutTemplate] = [],
        sessions: [LoggedWorkoutSession] = [],
        memories: [AthleteMemoryItem] = [],
        messages: [CoachMessage] = [],
        checkIns: [DailyCheckIn] = []
    ) {
        self.templates = templates
        self.sessions = sessions
        self.memories = memories
        self.messages = messages
        self.checkIns = checkIns
    }
}

public struct LegacyImportReport: Equatable, Hashable, Sendable, Codable {
    public let alreadyImported: Bool
    public let templatesImported: Int
    public let sessionsImported: Int
    public let memoriesImported: Int
    public let messagesImported: Int
    public let checkInsImported: Int
    public let completedAt: Date

    public init(
        alreadyImported: Bool,
        templatesImported: Int,
        sessionsImported: Int,
        memoriesImported: Int,
        messagesImported: Int,
        checkInsImported: Int,
        completedAt: Date = Date()
    ) {
        self.alreadyImported = alreadyImported
        self.templatesImported = templatesImported
        self.sessionsImported = sessionsImported
        self.memoriesImported = memoriesImported
        self.messagesImported = messagesImported
        self.checkInsImported = checkInsImported
        self.completedAt = completedAt
    }

    public var totalImported: Int {
        templatesImported + sessionsImported + memoriesImported + messagesImported + checkInsImported
    }
}

/// Idempotent one-time importer from legacy SwiftData/JSON stores into GRDB Schema v1.
public enum LegacyDataImporter {
    public static let anchorKey = "legacy_import_v3"
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "LegacyDataImporter")

    private struct MemoryScope: Codable {
        let category: AthleteMemoryCategory
    }

    public static func importIfNeeded(
        into repository: BodySeekRepository,
        now: Date = Date(),
        payloadProvider: @Sendable () throws -> LegacyImportPayload?
    ) async throws -> LegacyImportReport {
        if let existingAnchor = try await repository.loadSyncAnchor(type: anchorKey) {
            return LegacyImportReport(
                alreadyImported: true,
                templatesImported: 0,
                sessionsImported: 0,
                memoriesImported: 0,
                messagesImported: 0,
                checkInsImported: 0,
                completedAt: existingAnchor.updatedAt
            )
        }

        let payload = try payloadProvider() ?? LegacyImportPayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let report: LegacyImportReport = try await repository.database.writer.write { db in
            if try BodySeekRepository.loadSyncAnchorSync(db: db, type: anchorKey) != nil {
                return LegacyImportReport(
                    alreadyImported: true,
                    templatesImported: 0,
                    sessionsImported: 0,
                    memoriesImported: 0,
                    messagesImported: 0,
                    checkInsImported: 0,
                    completedAt: now
                )
            }

            let nowEpoch = now.timeIntervalSince1970

            for (idx, template) in payload.templates.enumerated() {
                let data = try encoder.encode(template)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO workout_template (id, sort_order, updated_at, payload)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [template.id.uuidString, idx, nowEpoch, data]
                )
            }

            for session in payload.sessions {
                let data = try encoder.encode(session)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO logged_workout_session (id, completed_at, payload)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [session.id.uuidString, session.completedAt.timeIntervalSince1970, data]
                )
            }

            for memory in payload.memories {
                let tier: MemoryTier = (memory.category == .injury) ? .activeConstraint : .profile
                let expiresAt: Date? = (memory.category == .injury)
                    ? memory.updatedAt.addingTimeInterval(14 * 86_400)
                    : nil
                let scopeData = try encoder.encode(MemoryScope(category: memory.category))
                let scopeJSON = String(data: scopeData, encoding: .utf8) ?? "{}"
                let record = TieredMemoryRecord(
                    id: memory.id,
                    tier: tier,
                    content: memory.content,
                    scopeJSON: scopeJSON,
                    confidence: 1.0,
                    expiresAt: expiresAt,
                    confirmedAt: memory.updatedAt,
                    retiredAt: nil
                )
                try BodySeekRepository.saveTieredMemorySync(db: db, record: record)
            }

            for message in payload.messages {
                let proposalJSON: String? = if let proposal = message.workoutProposal {
                    String(data: try encoder.encode(proposal), encoding: .utf8)
                } else {
                    nil
                }
                try BodySeekRepository.appendMessageSync(
                    db: db,
                    message: message,
                    proposalJSON: proposalJSON,
                    threadID: "default"
                )
            }

            for checkIn in payload.checkIns {
                try BodySeekRepository.saveCheckInSync(db: db, checkIn: checkIn)
            }

            let result = LegacyImportReport(
                alreadyImported: false,
                templatesImported: payload.templates.count,
                sessionsImported: payload.sessions.count,
                memoriesImported: payload.memories.count,
                messagesImported: payload.messages.count,
                checkInsImported: payload.checkIns.count,
                completedAt: now
            )

            let markerData = try encoder.encode(result)
            try BodySeekRepository.saveSyncAnchorSync(
                db: db,
                state: SyncAnchorState(
                    type: anchorKey,
                    anchorData: markerData,
                    backfillCursor: nil,
                    updatedAt: now
                )
            )
            return result
        }

        logger.info("LegacyDataImporter finished: alreadyImported=\(report.alreadyImported, privacy: .public), total=\(report.totalImported, privacy: .public)")
        return report
    }
}
