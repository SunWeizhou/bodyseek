import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "MemoryLedger")

enum MemoryLedgerError: LocalizedError {
    case invalidTargetFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidTargetFile(let file):
            return "Memory proposal rejected: '\(file)' is not an allowed wiki file."
        }
    }
}

/// Manages the memory proposal lifecycle: create, confirm, reject, rollback.
/// Stores proposals as MemoryEventRecord in SwiftData and writes confirmed
/// entries to wiki markdown files.
@MainActor
final class MemoryLedger {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create Proposal

    func createProposal(
        targetFile: String,
        memoryType: MemoryType,
        content: String,
        evidence: String,
        confidence: Double,
        source: String,
        linkedAgentRunId: String? = nil
    ) throws -> MemoryEventRecord {
        // 文件名必须命中 Wiki 白名单：LLM 提供的任意文件名会在用户确认提案时
        // 被拼进 user_wiki 目录读取（previousContent），未校验的 "../" 可穿越
        // 目录读取应用容器内其它文件。写入侧已有同款白名单，提案入口补齐。
        guard WikiFileService.allowedFilenames.contains(targetFile) else {
            throw MemoryLedgerError.invalidTargetFile(targetFile)
        }
        // M4：baselines.md 由引擎自动生成（每次刷新以 .replace 覆盖），
        // 确认写入的基线记忆会在下一次刷新被静默抹掉——拒绝把提案指向该文件。
        guard targetFile != "baselines.md" else {
            throw MemoryLedgerError.invalidTargetFile(targetFile)
        }
        try PersistenceWriteGate.shared.assertWritable(operation: "MemoryLedger: createProposal", modelContext: modelContext)

        // PR4：跨源去重——同一稳定事实可被 evening_wiki_sync / coach_tool /
        // coach legacy 三通道重复提案，待确认收件箱此前被稀释。
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allRecords = (try? modelContext.fetch(FetchDescriptor<MemoryEventRecord>())) ?? []
        if let duplicate = allRecords.first(where: { record in
            (record.status == MemoryProposalStatus.proposed.rawValue
                || record.status == MemoryProposalStatus.accepted.rawValue)
                && record.targetFile == targetFile
                && (record.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedContent
                    || WikiFileService.textSimilarity(record.content, content) > 0.85)
        }) {
            logger.info("Memory proposal deduplicated across sources: \(targetFile)")
            return duplicate
        }

        let record = MemoryEventRecord(
            source: source,
            targetFile: targetFile,
            memoryType: memoryType,
            operation: "propose",
            content: content,
            evidence: evidence,
            confidence: confidence,
            status: .proposed,
            linkedAgentRunId: linkedAgentRunId
        )
        modelContext.insert(record)
        try modelContext.save()
        logger.info("Memory proposal created: \(targetFile) [\(memoryType.rawValue)]")
        return record
    }

    // MARK: - Confirm (accept proposal → write to wiki)

    func editProposal(_ proposalId: UUID, content: String, userNote: String? = nil) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "MemoryLedger: editProposal", modelContext: modelContext)
        let descriptor = FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.id == proposalId }
        )
        guard let record = try modelContext.fetch(descriptor).first,
              record.status == MemoryProposalStatus.proposed.rawValue else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.content = trimmed
        record.userNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        record.operation = "edit_proposal"
        try modelContext.save()
        logger.info("Memory proposal edited before confirmation: \(proposalId)")
    }

    func confirmProposal(_ proposalId: UUID) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "MemoryLedger: confirmProposal", modelContext: modelContext)
        let descriptor = FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.id == proposalId }
        )
        guard let record = try modelContext.fetch(descriptor).first else {
            logger.warning("Proposal \(proposalId) not found for confirmation.")
            return
        }

        guard record.status == MemoryProposalStatus.proposed.rawValue else {
            logger.warning("Proposal \(proposalId) is not in 'proposed' status.")
            return
        }

        // Write to wiki markdown file
        let previousContent = (try? String(contentsOf: WikiFileService.localURL(for: record.targetFile), encoding: .utf8)) ?? ""
        record.previousContent = previousContent
        record.previousContentHash = ContentHash.hash(previousContent)

        let wroteContent = try WikiFileService.updateSection(
            filename: record.targetFile,
            content: record.content,
            mode: .merge
        )

        WikiSyncManager.sync(modelContext: modelContext)

        let newContent = (try? String(contentsOf: WikiFileService.localURL(for: record.targetFile), encoding: .utf8)) ?? ""
        record.newContentHash = ContentHash.hash(newContent)
        record.operation = "apply"
        if !wroteContent {
            // The update did not actually change the wiki (unwritable file, or every
            // paragraph was deduplicated out). Do NOT mark accepted — that would show
            // the user a "saved" memory that never reached the wiki (silent data loss).
            // Mark rejected so the user can recall/retry instead of believing it stuck.
            record.status = MemoryProposalStatus.rejected.rawValue
            record.userNote = "写入 wiki 未生效（目标文件不可写或内容为重复），已拒绝以便重试。"
            logger.warning("Proposal \(proposalId) confirmed but wiki unchanged → marked rejected: \(record.targetFile)")
            try modelContext.save()
            return
        }
        record.status = MemoryProposalStatus.accepted.rawValue
        try modelContext.save()

        logger.info("Memory proposal confirmed and written: \(record.targetFile)")
    }

    // MARK: - Reject Proposal

    func rejectProposal(_ proposalId: UUID, reason: String? = nil) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "MemoryLedger: rejectProposal", modelContext: modelContext)
        let descriptor = FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.id == proposalId }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.status = MemoryProposalStatus.rejected.rawValue
        record.userNote = reason
        record.operation = "reject"
        try modelContext.save()
        logger.info("Memory proposal rejected: \(proposalId)")
    }

    // MARK: - Rollback (revert a confirmed memory)

    func rollback(recordId: UUID) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "MemoryLedger: rollback", modelContext: modelContext)
        let descriptor = FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.id == recordId }
        )
        guard let record = try modelContext.fetch(descriptor).first,
              record.status == MemoryProposalStatus.accepted.rawValue else {
            logger.warning("Cannot rollback: record \(recordId) is not in accepted state.")
            return
        }

        guard let previousContent = record.previousContent else {
            logger.warning("Cannot rollback legacy memory \(recordId): previous markdown was not captured.")
            return
        }

        let currentURL = WikiFileService.localURL(for: record.targetFile)
        let currentContent = (try? String(contentsOf: currentURL, encoding: .utf8)) ?? ""
        if let appliedHash = record.newContentHash,
           ContentHash.hash(currentContent) != appliedHash {
            // M5：文件被二次改动后无法安全回滚——不再静默无操作，
            // 把原因写进 userNote 让用户可见，状态保持 accepted。
            record.userNote = "文件已被后续修改，无法安全回滚。"
            try? modelContext.save()
            logger.warning("Cannot rollback memory \(recordId): wiki changed after this memory was applied.")
            return
        }

        try WikiFileService.updateSection(
            filename: record.targetFile,
            content: previousContent,
            mode: .replace
        )
        WikiSyncManager.sync(modelContext: modelContext)

        record.status = MemoryProposalStatus.superseded.rawValue
        record.operation = "rollback"
        try modelContext.save()
        logger.info("Memory record rolled back: \(recordId)")
    }

    // MARK: - Query

    func fetchAcceptedObservations() throws -> [MemoryEventRecord] {
        try modelContext.fetch(FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.memoryTypeRaw == "observation" && $0.status == "accepted" }
        ))
    }

    func fetch(source: String) throws -> [MemoryEventRecord] {
        try modelContext.fetch(FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.source == source }
        ))
    }

    func fetchNewest(source: String) throws -> [MemoryEventRecord] {
        try modelContext.fetch(FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.source == source },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    func pendingProposals() -> [MemoryEventRecord] {
        let descriptor = FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.status == "proposed" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func history(for filename: String, limit: Int = 50) -> [MemoryEventRecord] {
        var descriptor = FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate { $0.targetFile == filename },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allRecords(limit: Int = 100) -> [MemoryEventRecord] {
        var descriptor = FetchDescriptor<MemoryEventRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Cleanup (auto-expire old pending proposals)

    func expireOldPendingProposals(olderThan days: Int = 14) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "MemoryLedger: expireOldPendingProposals", modelContext: modelContext)
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let pending = pendingProposals()
        for record in pending where record.createdAt < cutoff {
            record.status = MemoryProposalStatus.expired.rawValue
        }
        try modelContext.save()
        logger.info("Expired \(pending.filter { $0.createdAt < cutoff }.count) old pending proposals.")
    }
}

// MARK: - Content Hash Helper

enum ContentHash {
    /// Computes a stable content hash for deduplication and change detection.
    static func hash(_ string: String) -> String {
        let input = string.data(using: .utf8) ?? Data()
        // FNV-1a 64-bit hash — fast, stable, no external dependencies
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in input {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        // Mix in the length for extra spread
        hash ^= UInt64(input.count)
        return String(format: "%016llx", hash)
    }
}

// MARK: - Automatic Memory Extractor

@MainActor
final class AutomaticMemoryExtractor: Sendable {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Extracts health constraints, preferences, or symptoms from user text (e.g. journal entry or chat message).
    /// Creates memory proposals via MemoryLedger if explicit health signals are detected.
    @discardableResult
    func extract(from text: String, source: String = "User Text") throws -> [MemoryEventRecord] {
        var createdRecords: [MemoryEventRecord] = []
        let ledger = MemoryLedger(modelContext: modelContext)

        let lower = text.lowercased()

        // 1. Injury / Pain signals
        if lower.contains("痛") || lower.contains("拉伤") || lower.contains("不适") || lower.contains("受伤") || lower.contains("pain") || lower.contains("injured") {
            let record = try ledger.createProposal(
                targetFile: "profile.md",
                memoryType: .constraint,
                content: "- 【伤病/不适记录】: \(text)",
                evidence: "从用户输入中自动提炼伤病不适信号: \"\(text)\"",
                confidence: 0.85,
                source: source
            )
            createdRecords.append(record)
        }

        // 2. Dietary preferences
        if lower.contains("咖啡因") || lower.contains("低碳水") || lower.contains("过敏") || lower.contains("caffeine") || lower.contains("allergic") {
            let record = try ledger.createProposal(
                targetFile: "profile.md",
                memoryType: .preference,
                content: "- 【饮食偏好/禁忌】: \(text)",
                evidence: "从用户输入中自动提炼饮食偏好信号: \"\(text)\"",
                confidence: 0.80,
                source: source
            )
            createdRecords.append(record)
        }

        return createdRecords
    }
}
