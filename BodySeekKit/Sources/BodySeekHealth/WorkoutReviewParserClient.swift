import BodySeekCore
import Dependencies
import DependenciesMacros
import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

@DependencyClient
public struct WorkoutReviewParserClient: Sendable {
    public var parse: @Sendable (_ text: String) async -> WorkoutAnnotationProposal = { text in
        ChineseWorkoutLexiconParser.parse(text)
    }
}

extension WorkoutReviewParserClient: DependencyKey {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "WorkoutReviewParser")

    public static let liveValue = WorkoutReviewParserClient(
        parse: { text in
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let model = SystemLanguageModel.default
                switch model.availability {
                case .available:
                    do {
                        let parsed = try await parseWithFoundationModels(model: model, text: text)
                        return parsed
                    } catch {
                        let msg = "FoundationModels 解析失败，已降级中文词典：\(error.localizedDescription)"
                        logger.warning("\(msg, privacy: .public)")
                        var fallback = ChineseWorkoutLexiconParser.parse(text)
                        fallback.degradationReason = msg
                        return fallback
                    }
                case let .unavailable(reason):
                    let msg = "端侧 Apple Intelligence 不可用（\(String(describing: reason))），已降级中文词典"
                    logger.info("\(msg, privacy: .public)")
                    var fallback = ChineseWorkoutLexiconParser.parse(text)
                    fallback.degradationReason = msg
                    return fallback
                }
            }
            #endif

            let msg = "当前运行环境不支持 FoundationModels，使用离线中文词典解析"
            logger.info("\(msg, privacy: .public)")
            var fallback = ChineseWorkoutLexiconParser.parse(text)
            fallback.degradationReason = msg
            return fallback
        }
    )

    public static let previewValue = WorkoutReviewParserClient(
        parse: { text in
            ChineseWorkoutLexiconParser.parse(text)
        }
    )

    public static let testValue = previewValue

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedWorkoutReview {
        @Guide(description: "Primary muscle IDs from chest, upper-back, lower-back, deltoids, biceps, triceps, forearm, abs, obliques, quadriceps, hamstring, gluteal, calves, trapezius")
        var primaryMuscles: [String]

        @Guide(description: "Secondary muscle IDs from the same canonical list")
        var secondaryMuscles: [String]

        @Guide(description: "Subjective RPE 1 to 10 if mentioned, else nil")
        var rpe: Int?

        @Guide(description: "Canonical exercise names performed in Chinese")
        var exercises: [String]

        @Guide(description: "Body region with tightness/pain/discomfort if mentioned, e.g. 右肩 or 左膝")
        var signalRegion: String?

        @Guide(description: "Discomfort symptom if mentioned, e.g. 紧 or 微痛")
        var signalSymptom: String?
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func parseWithFoundationModels(
        model: SystemLanguageModel,
        text: String
    ) async throws -> WorkoutAnnotationProposal {
        let lexiconBaseline = ChineseWorkoutLexiconParser.parse(text)
        let session = LanguageModelSession(
            model: model,
            instructions: """
            你是健身训练复盘解析器。请严格从用户的一句话中提取主肌群、次肌群、RPE(1-10)、动作名和局部身体信号。
            如果某部位明确是否定（如“没练腿”），不要将其归入主次肌群。仅使用标准英文 muscle ID。
            """
        )
        let response = try await session.respond(to: text, generating: GeneratedWorkoutReview.self)
        let generated = response.content

        let primary = generated.primaryMuscles.compactMap { BodyRegionMuscle(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let secondary = generated.secondaryMuscles
            .compactMap { BodyRegionMuscle(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !primary.contains($0) }

        let resolvedPrimary = primary.isEmpty ? lexiconBaseline.primaryMuscles : primary
        let resolvedSecondary = primary.isEmpty ? lexiconBaseline.secondaryMuscles : secondary
        let resolvedRPE = generated.rpe.flatMap { (1...10).contains($0) ? $0 : nil } ?? lexiconBaseline.rpe
        let resolvedExercises = generated.exercises.isEmpty ? lexiconBaseline.exercises : generated.exercises

        var signals = lexiconBaseline.bodySignals
        if signals.isEmpty,
           let region = generated.signalRegion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !region.isEmpty,
           let symptom = generated.signalSymptom?.trimmingCharacters(in: .whitespacesAndNewlines),
           !symptom.isEmpty
        {
            signals.append(
                WorkoutBodySignal(
                    region: region,
                    symptom: symptom,
                    suggestedConstraint: "\(region)\(symptom)（练后复盘反馈，14天内注意降低该部位直接负荷与大角度压迫）",
                    defaultExpiryDays: 14,
                    includeAsMemory: true
                )
            )
        }

        return WorkoutAnnotationProposal(
            rawText: text,
            primaryMuscles: resolvedPrimary,
            secondaryMuscles: resolvedSecondary,
            rpe: resolvedRPE,
            exercises: resolvedExercises,
            bodySignals: signals,
            parserSource: .foundationModels,
            degradationReason: nil,
            parserVersion: .workoutParserV1
        )
    }
    #endif
}

public extension DependencyValues {
    var workoutReviewParserClient: WorkoutReviewParserClient {
        get { self[WorkoutReviewParserClient.self] }
        set { self[WorkoutReviewParserClient.self] = newValue }
    }
}
