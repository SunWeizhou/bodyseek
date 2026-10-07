import Foundation
import SwiftData
import os.log

@MainActor
final class MorningBriefScheduler: ObservableObject {
    static let shared = MorningBriefScheduler()
    
    private let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "MorningBriefScheduler")
    
    private let keychain = KeychainService.shared
    private let apiKeyAccount = "deepseek_api_key"
    
    @Published var isGenerating = false
    
    private init() {}
    
    /// Checks if a morning brief needs to be run, and generates/saves it if so.
    /// - Parameters:
    ///   - modelContext: SwiftData modelContext to query and save records
    ///   - dashboard: The current dashboard summary
    ///   - force: If true, runs generation bypassing time window and date checks
    func runIfNeeded(modelContext: ModelContext, dashboard: DashboardSummary, force: Bool = false, services: VelaServices? = nil) async {
        logger.info("runIfNeeded called (force: \(force))")

        // 算法打通（深度专项批次 1）：force 只跳过时间窗/去重/新鲜度检查，
        // 绝不绕过后台与逐类别出网 consent。
        let outboundPolicy = AgentOutboundConsentPolicy.current
        guard AutoAgentConfig.shared.autoMorningBrief,
              outboundPolicy.canSendNetworkAI else {
            logger.info("Automated morning brief is not enabled by the user. Skipping.")
            return
        }
        
        // 1. If not forced, check time window (06:00 - 11:00)
        if !force {
            let hour = Calendar.current.component(.hour, from: Date())
            guard hour >= 6 && hour < 11 else {
                logger.info("Current hour \(hour) is outside morning window (6-11). Skipping.")
                return
            }
        }
        
        // 2. Check if a morning brief already exists for today's calendar day (unless forced)
        if !force {
            let descriptor = FetchDescriptor<AIReportRecord>(
                predicate: #Predicate<AIReportRecord> { $0.type == "morning_brief" },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            
            do {
                let reports = try modelContext.fetch(descriptor)
                if let latest = reports.first {
                    if Calendar.current.isDateInToday(latest.createdAt) {
                        logger.info("Morning brief already generated today at \(latest.createdAt). Skipping.")
                        return
                    }
                }
            } catch {
                logger.error("Failed to fetch existing morning briefs: \(error.localizedDescription)")
            }
        }
        
        // 2.5 数据新鲜度检查：今日快照未同步、或早于健康日 04:00 边界（大概率
        // 缺当夜睡眠数据）时不生成——此前只查「存在性」，00:30 的空快照可通过。
        if !force {
            let todayIdentifier = DailyHealthSummaryRecord.dayIdentifier(
                for: Date(),
                calendar: Calendar.current
            )
            let todayDescriptor = FetchDescriptor<DailyHealthSummaryRecord>(
                predicate: #Predicate<DailyHealthSummaryRecord> { $0.dayIdentifier == todayIdentifier }
            )
            guard let todayRecord = (try? modelContext.fetch(todayDescriptor))?.first else {
                logger.warning("Today's health snapshot is not yet synced. Skipping morning brief.")
                return
            }
            let healthDayBoundary = Calendar.current.date(bySettingHour: 4, minute: 0, second: 0, of: Date()) ?? Date()
            guard todayRecord.updatedAt >= healthDayBoundary else {
                logger.warning("Today's snapshot predates the 04:00 health-day boundary (likely missing sleep data). Skipping morning brief.")
                return
            }
        }

        // 3. Read API Key from Keychain
        guard let apiKey = try? keychain.read(account: apiKeyAccount), !apiKey.isEmpty else {
            logger.warning("DeepSeek API Key is not set in Keychain. Cannot generate morning brief.")
            return
        }
        
        logger.info("Starting automated Morning Brief generation...")
        isGenerating = true
        defer { isGenerating = false }

        let runRecord = AgentRunRecord(
            agentName: "morning_brief",
            startedAt: Date(),
            status: .running,
            reason: force ? "forced" : "scheduled",
            inputContextHash: "",
            outputSummary: ""
        )
        modelContext.insert(runRecord)
        try? modelContext.save()

        do {
            // 4. Load the same bounded fact set used by Coach and evening sync.
            let contextAsOf = Date()
            let input = AgentFactInputLoader().load(
                modelContext: modelContext,
                asOf: contextAsOf
            )

            // 5. Load Wiki data
            let wiki = WikiFileService.loadPopulatedDictionary()

            // 6. A6：晨报消费 v2 AgentFactSnapshot（与 Coach / 晚间同步同源），
            // 不再走 v1 AgentContextEnvelope 双序列化路径。
            let built = (services?.contextBuilder ?? AIContextBuilder()).buildFacts(
                dashboard: dashboard,
                journalEntries: input.journalContext,
                historicalReports: input.reportContext,
                userWiki: wiki,
                weeklyTrends: input.weeklyTrends,
                foodLogs: input.foodLogs,
                workoutEvents: input.workoutEvents,
                strengthWorkouts: input.strengthWorkouts,
                trainingResponses: input.trainingResponses,
                onboardingState: input.onboardingState,
                bodyState: input.bodyState(dashboard: dashboard),
                scoringContext: dashboard.scoringContext,
                dailyOperatingPlan: AIContextBuilder.compactDailyOperatingPlan(input.dailyOperatingPlan),
                activePlan: input.activePlan?.dto,
                generatedAt: contextAsOf
            )
            // Build locally from the canonical fact set, then enforce the
            // outbound boundary immediately before the provider call.  This
            // keeps local calculations complete while ensuring revoked
            // categories cannot be serialized into a request or report.
            let context = built.snapshot.redacted(for: outboundPolicy)
            var contextMeta = built.metadata
            contextMeta.hash = context.contextHash
            contextMeta.redactedFields = Self.redactedFields(for: outboundPolicy)
            
            // 7. Generate Report using ReportGenerator（带指数退避重试）
            let baseProvider = services?.deepSeekProvider(apiKey: apiKey) ?? DeepSeekProvider(apiKey: apiKey)
            let provider = RetryingLLMProvider(base: baseProvider)
            let generator = ReportGenerator(provider: provider, language: AppLanguage.stored)
            
            logger.info("Calling ReportGenerator for morning brief...")
            let generatedReport = try await generator.generate(type: .morningBrief, context: context)
            
            // 8. Persist back as a new AIReportRecord in SwiftData modelContext
            let newRecord = AIReportRecord(
                createdAt: generatedReport.createdAt,
                type: generatedReport.type.rawValue,
                title: generatedReport.title,
                markdownContent: generatedReport.markdownContent,
                serializedContextSnapshot: generatedReport.contextSnapshot,
                tags: ["morning_brief", "automated"]
            )
            
            try PersistenceWriteGate.shared.assertWritable(operation: "MorningBriefScheduler: save report", modelContext: modelContext)
            modelContext.insert(newRecord)
            try modelContext.save()
            logger.info("Successfully generated and saved Morning Brief report!")

            // 深度专项批次 4（管线 A）：附带生成「AI 今日解读」——严格 JSON、以本地
            // 决策为锚，落 AIReportRecord(type=daily_ai_insight) 供今日页展示；
            // 失败不影响晨报本身。
            do {
                // The local plan is a health-derived training action.  It is
                // only eligible for this second provider call when both source
                // categories are explicitly allowed.
                let planPayload = outboundPolicy.health && outboundPolicy.training
                    ? input.dailyOperatingPlan?.operatingPlanPayload
                    : nil
                let decisionText = planPayload?.decision.rawValue ?? "unavailable"
                let summaryText = planPayload?.summary ?? "The daily operating plan is not shared."
                let insight = try await generator.generateDailyInsight(
                    context: context,
                    localDecision: decisionText,
                    localSummary: summaryText
                )
                let insightJSON = (try? JSONEncoder().encode(insight))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                modelContext.insert(AIReportRecord(
                    createdAt: Date(),
                    type: ReportGenerator.dailyInsightReportType,
                    title: "今日 AI 解读",
                    markdownContent: insight.interpretation,
                    serializedContextSnapshot: insightJSON,
                    tags: ["daily_ai_insight", "automated"]
                ))
                try modelContext.save()
                logger.info("Daily AI insight generated and saved.")
            } catch {
                logger.warning("Daily AI insight generation failed (non-fatal): \(error.localizedDescription)")
            }

            // Update the run record
            runRecord.endedAt = Date()
            runRecord.status = AgentRunStatus.success.rawValue
            runRecord.inputContextHash = contextMeta.hash
            runRecord.outputSummary = String(generatedReport.markdownContent.prefix(300))
            try? modelContext.save()

            // Send notification that the morning brief is ready（PR11：带报告首行正文）
            let headline = generatedReport.markdownContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("|") }
            NotificationService.shared.scheduleMorningBriefCheck(headline: headline)

        } catch {
            logger.error("Failed to generate Morning Brief: \(error.localizedDescription)")
            runRecord.endedAt = Date()
            runRecord.status = AgentRunStatus.failed.rawValue
            runRecord.errorMessage = error.localizedDescription
            try? modelContext.save()
        }
    }

    private static func redactedFields(for policy: AgentOutboundConsentPolicy) -> [String] {
        AgentOutboundDataCategory.allCases.compactMap { policy.allows($0) ? nil : $0.rawValue }
    }
}
