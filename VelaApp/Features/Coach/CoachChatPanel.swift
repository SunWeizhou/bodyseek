import SwiftData
import SwiftUI
import UIKit

// MARK: - Shared Types

// MARK: - CoachChatVM and helper structures have been moved to CoachChatVM.swift

// Note: CoachChatMessage, CoachRecoveryActionButton, and CoachDataCoverageStrip have been moved to CoachMessageBubble.swift

// MARK: - Mini Coach Panel (for MetricCoachCard sheets)

// Note: MessageSegment, parseMessageContent, AppleIntelligenceLoaderDots, MiniBubble, and MiniStreamingBubble have been moved to CoachMessageBubble.swift

// MARK: - Journal Correlation Tool

/// Queries how a specific journal tag correlates with health scores by running
/// the JournalCorrelationEngine against SwiftData records.
struct JournalCorrelationTool: AgentTool {
    let name = "journal_correlation"
    let description = "Query how a specific journal tag (e.g., caffeine, alcohol, meditation, late_meal) correlates with sleep, recovery, strain scores, HRV, and RHR. Returns real correlation data computed from the user's journal entries and daily health snapshots."

    let executionContext: ToolExecutionContext

    var parameters: [String: Value] {
        [
            "type": .string("object"),
            "properties": .object([
                "tag": .object([
                    "type": .string("string"),
                    "description": .string("The journal tag to analyze. Common tags: caffeine, alcohol, late_meal, heavy_meal, exercise, stressed, meditation, hydration, supplements, sick, travel, menstruation, sleep, recovery, training, mood."),
                ]),
            ]),
            "required": .array([.string("tag")]),
        ]
    }

    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag"] as? String else {
            return "Error: missing 'tag' argument."
        }
        return await MainActor.run {
            let modelContext = executionContext.modelContext
            // 行为-结果配对用三年窗口：回填后旧手记也能对上次日体征。
            let threeYearsAgo = Date().addingTimeInterval(-1095 * 24 * 3600)
            let journalEntries = (try? SwiftDataJournalRepository(modelContext: modelContext)
                .fetchEntries(onOrAfter: threeYearsAgo)) ?? []
            let healthRecords = (try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
                .fetchRecords(onOrAfter: threeYearsAgo)) ?? []
            let healthSnapshots = healthRecords.map { $0.toSnapshot() }

            // Run the correlation engine
            // T6：统一到 calculateInsights（点二列 + Benjamini-Hochberg FDR），
            // 与身体模型页同口径；旧 correlateTags 均值差路径不再用于 Coach。
            let engine = JournalCorrelationEngine()
            let allInsights = engine.calculateInsights(
                journalEntries: journalEntries,
                snapshots: healthSnapshots
            )

            // Extract results for the requested tag
            let matched = allInsights.filter { $0.habit.lowercased() == tag.lowercased() }
            guard !matched.isEmpty else {
                let availableTags = allInsights.prefix(8).map(\.habit).joined(separator: ", ")
                return availableTags.isEmpty
                    ? "No correlation data found. Need more journal entries and health snapshots (≥28 days with ≥8 exposed days) to compute behavior-impact relationships."
                    : "No correlation data for '\(tag)'. Available tags with correlations: \(availableTags)."
            }

            let formatted = engine.formatInsightsForAI(matched)
            return formatted.isEmpty ? "Correlation data computed but formatting produced empty output. Try a different tag." : formatted
        }
    }
}
