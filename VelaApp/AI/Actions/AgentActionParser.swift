import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "AgentActionParser")

enum AgentActionType: String, Codable, Hashable, CaseIterable {
    case updateWiki = "update_wiki"
    case createDailyLog = "create_daily_log"
}

struct AgentAction: Identifiable, Hashable {
    let id = UUID()
    var type: AgentActionType
    var target: String
    var content: String
    var timestamp: Date = Date()
}

struct AgentParsedResponse: Hashable {
    var displayText: String
    var actions: [AgentAction]
}

enum CoachArtifactType: String, Codable, Hashable, CaseIterable, Identifiable {
    case morningBrief = "morning_brief"
    case workoutReadiness = "workout_readiness"
    case trainingAdjustment = "training_adjustment"
    case postWorkoutReview = "post_workout_review"
    case eveningReview = "evening_review"
    case weeklyReview = "weekly_review"
    case wikiUpdateProposal = "wiki_update_proposal"
    case askCoachAnswer = "ask_coach_answer"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .morningBrief: L10n.t("Morning Brief", "今日简报")
        case .workoutReadiness: L10n.t("Workout Readiness", "训练准备度")
        case .trainingAdjustment: L10n.t("Training Adjustment", "训练调整")
        case .postWorkoutReview: L10n.t("Post-Workout Review", "训练后复盘")
        case .eveningReview: L10n.t("Evening Review", "晚间回顾")
        case .weeklyReview: L10n.t("Weekly Review", "周度回顾")
        case .wikiUpdateProposal: L10n.t("Wiki Update", "档案更新")
        case .askCoachAnswer: L10n.t("Ask Coach", "教练回复")
        }
    }
}

enum CoachArtifactStatus: String, Codable, Hashable, CaseIterable {
    case created
    case presented
    case acted
    case dismissed
}

struct CoachArtifactReason: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var signal: String
    var value: String
    var explanation: String

    enum CodingKeys: String, CodingKey {
        case signal, value, explanation
    }
}

struct CoachArtifactAction: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var type: String
    var label: String
    var payload: [String: String]

    init(id: UUID = UUID(), type: String, label: String, payload: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.label = label
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case type, label, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        type = try container.decode(String.self, forKey: .type)
        label = try container.decode(String.self, forKey: .label)
        payload = (try? container.decode([String: String].self, forKey: .payload)) ?? [:]
    }
}

struct CoachArtifact: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var type: CoachArtifactType
    var title: String
    var summary: String
    var createdAt: Date
    var relatedDate: Date?
    var decision: String?
    var confidence: Double
    var reasons: [CoachArtifactReason]
    var actions: [CoachArtifactAction]
    var sourceContextHash: String
    var userFeedback: String?
    var status: CoachArtifactStatus
    var followUpQuestion: String?

    init(
        id: UUID = UUID(),
        type: CoachArtifactType,
        title: String,
        summary: String,
        createdAt: Date = Date(),
        relatedDate: Date? = nil,
        decision: String? = nil,
        confidence: Double,
        reasons: [CoachArtifactReason],
        actions: [CoachArtifactAction],
        sourceContextHash: String,
        userFeedback: String? = nil,
        status: CoachArtifactStatus = .created,
        followUpQuestion: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.relatedDate = relatedDate
        self.decision = decision
        self.confidence = min(1, max(0, confidence))
        self.reasons = reasons
        self.actions = actions
        self.sourceContextHash = sourceContextHash
        self.userFeedback = userFeedback
        self.status = status
        self.followUpQuestion = followUpQuestion
    }

    static func postWorkoutReview(
        workout: StrengthWorkoutRecord,
        summary: StrengthWorkoutAnalysis,
        readinessDecision: String?,
        sourceContextHash: String,
        createdAt: Date = Date()
    ) -> CoachArtifact {
        let volume = Int(summary.totalVolumeKg.rounded())
        let muscleText = summary.muscleGroupSets
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value) sets" }
            .joined(separator: ", ")
        let prText = summary.personalRecords.isEmpty
            ? "No PR detected yet."
            : summary.personalRecords.map(\.summary).joined(separator: " ")

        return CoachArtifact(
            type: .postWorkoutReview,
            title: "训练后复盘",
            summary: "\(workout.title): \(summary.completedSets)/\(summary.plannedSets) 组完成，\(summary.effectiveSets) 个有效组，总容量 \(volume) kg。",
            createdAt: createdAt,
            relatedDate: workout.startedAt,
            decision: readinessDecision,
            confidence: 0.82,
            reasons: [
                CoachArtifactReason(signal: "volume", value: "\(volume)kg", explanation: "本次训练总容量用于评估训练刺激。"),
                CoachArtifactReason(signal: "effective_sets", value: "\(summary.effectiveSets)", explanation: "仅完成且达到有效强度的组计入恢复负荷。"),
                CoachArtifactReason(signal: "muscle_groups", value: muscleText.isEmpty ? "未记录" : muscleText, explanation: "肌群分布用于回顾本次训练刺激，并辅助安排下一次训练。")
            ],
            actions: [
                CoachArtifactAction(type: "open_training_summary", label: "查看训练总结", payload: ["workout_id": workout.id.uuidString]),
                CoachArtifactAction(type: "start_check_in", label: "记录训练后感受", payload: ["workout_id": workout.id.uuidString]),
                CoachArtifactAction(type: "open_recovery_detail", label: "查看恢复影响", payload: ["workout_id": workout.id.uuidString])
            ],
            sourceContextHash: sourceContextHash,
            followUpQuestion: prText
        )
    }
}

enum CoachArtifactParser {
    private struct ArtifactEnvelope: Decodable {
        var artifactType: CoachArtifactType
        var title: String
        var summary: String
        var decision: String?
        var confidence: Double?
        var reasons: [CoachArtifactReason]?
        var actions: [CoachArtifactAction]?
        var followUpQuestion: String?
    }

    static func parse(
        _ raw: String,
        sourceContextHash: String,
        createdAt: Date = Date(),
        relatedDate: Date? = nil
    ) throws -> CoachArtifact {
        let json = extractJSONObject(from: raw)
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ArtifactEnvelope.self, from: data)
        return CoachArtifact(
            type: decoded.artifactType,
            title: decoded.title,
            summary: decoded.summary,
            createdAt: createdAt,
            relatedDate: relatedDate,
            decision: decoded.decision,
            confidence: decoded.confidence ?? 0.55,
            reasons: decoded.reasons ?? [],
            actions: decoded.actions ?? [],
            sourceContextHash: sourceContextHash,
            followUpQuestion: decoded.followUpQuestion
        )
    }

    static func fallback(
        from text: String,
        type: CoachArtifactType,
        sourceContextHash: String,
        createdAt: Date = Date()
    ) -> CoachArtifact {
        let summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CoachArtifact(
            type: type,
            title: type.displayTitle,
            summary: summary.isEmpty ? "Vela 暂时无法生成结构化输出，但可以继续给出保守建议。" : summary,
            createdAt: createdAt,
            decision: nil,
            confidence: 0.35,
            reasons: [
                CoachArtifactReason(signal: "parser", value: "fallback", explanation: "AI 输出不是有效 JSON，已降级为本地安全卡片。")
            ],
            actions: [
                CoachArtifactAction(type: "start_check_in", label: "记录当前感受"),
                CoachArtifactAction(type: "ask_coach", label: "继续追问 Coach")
            ],
            sourceContextHash: sourceContextHash
        )
    }

    private static func extractJSONObject(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}

enum AgentActionParser {
    private static let actionPattern = try? NSRegularExpression(
        pattern: "\\[ACTION:(\\w+)\\]\\s*(.*?)\\s*\\[/ACTION\\]",
        options: [.dotMatchesLineSeparators]
    )

    private static let wikiFilePattern = try? NSRegularExpression(
        pattern: "^(?:file|File|FILE|文件):\\s*([\\w.\\-/]+)",
        options: [.anchorsMatchLines]
    )

    static func parse(_ rawResponse: String) -> AgentParsedResponse {
        guard let actionPattern else {
            logger.error("Agent action regex unavailable; returning raw response without extracted actions.")
            return AgentParsedResponse(
                displayText: rawResponse.trimmingCharacters(in: .whitespacesAndNewlines),
                actions: []
            )
        }

        let range = NSRange(rawResponse.startIndex..<rawResponse.endIndex, in: rawResponse)
        let matches = actionPattern.matches(in: rawResponse, options: [], range: range)

        var actions: [AgentAction] = []
        var cleanedText = rawResponse

        for match in matches.reversed() {
            guard let typeRange = Range(match.range(at: 1), in: rawResponse),
                  let bodyRange = Range(match.range(at: 2), in: rawResponse) else { continue }

            let typeString = String(rawResponse[typeRange])
            guard let type = AgentActionType(rawValue: typeString) else { continue }

            let body = String(rawResponse[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            let parsed = parseActionBody(body, type: type)
            actions.append(AgentAction(type: type, target: parsed.target, content: parsed.content))

            // Remove the action block from display text
            if let matchRange = Range(match.range, in: rawResponse) {
                cleanedText = cleanedText.replacingOccurrences(of: String(rawResponse[matchRange]), with: "")
            }
        }

        actions.reverse()

        logger.info("Parsed \(actions.count) actions from response (\(rawResponse.count) chars)")
        for action in actions {
            logger.info("  Action: \(action.type.rawValue) → \(action.target)")
        }

        return AgentParsedResponse(
            displayText: cleanedText.trimmingCharacters(in: .whitespacesAndNewlines),
            actions: actions
        )
    }

    private static func parseActionBody(_ body: String, type: AgentActionType) -> (target: String, content: String) {
        switch type {
        case .updateWiki:
            guard let filePattern = wikiFilePattern else {
                logger.error("Wiki action file regex unavailable; using default notes.md target.")
                return ("notes.md", body)
            }
            let fileRange = NSRange(body.startIndex..<body.endIndex, in: body)
            var target = "notes.md"
            var content = body

            if let match = filePattern.firstMatch(in: body, options: [], range: fileRange),
               let capRange = Range(match.range(at: 1), in: body),
               let matchRange = Range(match.range, in: body) {
                target = String(body[capRange])
                content = body.replacingOccurrences(of: String(body[matchRange]), with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return (target, content)

        case .createDailyLog:
            return ("daily", body)
        }
    }
}

// MARK: - Artifact Generator Tool

enum ArtifactGeneratorTool {
    @MainActor
    static func createArtifact(
        type: CoachArtifactType,
        title: String,
        summary: String,
        reasons: [CoachArtifactReason] = [],
        actions: [CoachArtifactAction] = [],
        confidence: Double = 0,
        sourceContextHash: String = "unavailable",
        modelContext: ModelContext
    ) -> CoachArtifact {
        let artifact = CoachArtifact(
            id: UUID(),
            type: type,
            title: title,
            summary: summary,
            createdAt: Date(),
            relatedDate: Date(),
            confidence: confidence,
            reasons: reasons,
            actions: actions,
            sourceContextHash: sourceContextHash
        )

        let payloadJSON = (try? JSONEncoder().encode(artifact))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let record = AgentArtifactRecord(
            id: artifact.id,
            type: artifact.type.rawValue,
            title: artifact.title,
            createdAt: artifact.createdAt,
            payloadJSON: payloadJSON,
            sourceContextHash: artifact.sourceContextHash,
            status: artifact.status.rawValue,
            confidence: artifact.confidence,
            source: "artifact_generator"
        )

        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            PipelineDiagnosticsLogger.log(
                modelContext: modelContext,
                stage: "AgentActionParser.persistArtifact",
                isSuccess: false,
                summary: "保存 Coach artifact 失败。",
                error: error
            )
        }
        return artifact
    }
}
