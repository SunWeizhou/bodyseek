import Foundation
import SwiftData

public final class PipelineDiagnosticsLogger {
    /// Logs a health pipeline operation outcome as an auditable log entry.
    /// This integrates directly with the existing Trust Center UI.
    public static func log(
        modelContext: ModelContext,
        stage: String,
        isSuccess: Bool,
        summary: String,
        error: Error? = nil
    ) {
        let record = AgentRunRecord(
            id: UUID(),
            agentName: "health_pipeline",
            startedAt: Date(),
            endedAt: Date(),
            status: isSuccess ? .success : .failed,
            reason: stage,
            inputContextHash: "",
            outputSummary: summary,
            toolCallsJSON: "[]",
            errorMessage: error?.localizedDescription
        )
        modelContext.insert(record)
        try? modelContext.save()
    }
}

public struct DiagnosticHealthReport: Sendable, Equatable {
    public var isHealthy: Bool
    public var totalEventsLogged: Int
    public var recentErrorsCount: Int
    public var issuesFound: [String]

    public init(
        isHealthy: Bool,
        totalEventsLogged: Int,
        recentErrorsCount: Int,
        issuesFound: [String]
    ) {
        self.isHealthy = isHealthy
        self.totalEventsLogged = totalEventsLogged
        self.recentErrorsCount = recentErrorsCount
        self.issuesFound = issuesFound
    }
}

extension PipelineDiagnosticsLogger {
    @MainActor
    public static func performSelfCheck(modelContext: ModelContext) -> DiagnosticHealthReport {
        let records = (try? AgentRunRepository(modelContext: modelContext).fetchAllSortedByStartedAt()) ?? []

        let recentFailures = records.prefix(50).filter { $0.status == AgentRunStatus.failed.rawValue }
        var issues: [String] = []

        if !recentFailures.isEmpty {
            issues.append("检测到过去 50 次任务运行中有 \(recentFailures.count) 次异常记录。")
        }

        let events = (try? VelaEventRepository(modelContext: modelContext).fetchAll()) ?? []
        let isHealthy = recentFailures.count < 5

        return DiagnosticHealthReport(
            isHealthy: isHealthy,
            totalEventsLogged: events.count,
            recentErrorsCount: recentFailures.count,
            issuesFound: issues
        )
    }
}

