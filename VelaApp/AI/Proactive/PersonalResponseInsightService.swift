import Foundation
import SwiftData

/// Orchestrates personal response pattern discovery and feeds results into Memory Inbox.
/// Runs during Evening Review or on manual trigger.
@MainActor
struct PersonalResponseInsightService {

    private let model: PersonalResponseModel

    init() {
        self.model = PersonalResponseModel()
    }

    /// Full pipeline: discover rules → dedup → MemoryProposal → Inbox.
    /// Returns the number of new proposals created.
    func scanAndPropose(
        modelContext: ModelContext,
        snapshots: [DailyHealthSnapshot],
        journalEntries: [JournalEntryRecord],
        foodLogs: [FoodLogRecord],
        existingRules: [MemoryEventRecord] = []
    ) throws -> Int {
        // 1. Discover rules
        let discovered = model.discoverRules(
            snapshots: snapshots,
            journalEntries: journalEntries,
            foodLogs: foodLogs
        )

        guard !discovered.isEmpty else { return 0 }

        // 2. Dedup against existing confirmed rules
        let existingRuleNames = Set(existingRules
            .filter { $0.status != MemoryProposalStatus.expired.rawValue }
            .compactMap { extractRuleName(from: $0.content) }
        )

        let newRules = discovered.filter { rule in
            !existingRuleNames.contains(rule.name)
        }

        // 3. Generate MemoryProposals via MemoryLedger
        let ledger = MemoryLedger(modelContext: modelContext)
        var created = 0
        for rule in newRules {
            let content = buildProposalContent(from: rule)
            let evidence = rule.evidenceSummary
            if let _ = try? ledger.createProposal(
                targetFile: "observations.md",
                memoryType: .observation,
                content: content,
                evidence: evidence,
                confidence: rule.confidence,
                source: "personal_response_model",
                linkedAgentRunId: nil
            ) {
                created += 1
            }
        }

        // 4. Expire old pending proposals
        try? ledger.expireOldPendingProposals(olderThan: 30)

        return created
    }

    // MARK: - Helpers

    private func extractRuleName(from content: String) -> String? {
        let range = content.range(of: "**规律**: ") ?? content.range(of: "**Rule**: ")
        guard let range else { return nil }
        let after = content[range.upperBound...]
        return after.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces)
    }

    private func buildProposalContent(from rule: PersonalResponseModel.PersonalRule) -> String {
        let lang = AppLanguage.stored
        if lang.isChinese {
            return """
            **规律**: \(rule.name)
            **触发条件**: \(rule.trigger)
            **效果**: \(rule.effect)
            **置信度**: \(String(format: "%.0f", rule.confidence * 100))%
            **观察次数**: \(rule.occurrenceCount) 次
            **证据**: \(rule.evidenceSummary)
            """
        }
        return """
        **Rule**: \(rule.name)
        **Trigger**: \(rule.trigger)
        **Effect**: \(rule.effect)
        **Confidence**: \(String(format: "%.0f", rule.confidence * 100))%
        **Occurrences**: \(rule.occurrenceCount)
        **Evidence**: \(rule.evidenceSummary)
        """
    }
}

struct WeeklyBodyReport: Codable, Hashable {
    var generatedAt: Date
    var markdown: String
    var trainingSessions: Int
    var averageRecoveryScore: Double?
    var averageSleepScore: Double?
    var trainingResponseCount: Int
}

struct MonthlyBodyReport: Codable, Hashable {
    var generatedAt: Date
    var markdown: String
    var observedDays: Int
    var averageRecoveryScore: Double?
    var averageSleepScore: Double?
    var trainingSessions: Int
}

/// Builds the local training-response loop independently from the LLM pipeline.
/// Stable patterns enter Memory Inbox as proposals and require user confirmation.
@MainActor
struct TrainingResponseInsightService {
    func captureTrainingResponses(
        modelContext: ModelContext,
        snapshots: [DailyHealthSnapshot],
        workouts: [StrengthWorkoutRecord],
        calendar: Calendar = .current
    ) throws -> Int {
        let existing = try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>())
        let existingByWorkout = Dictionary(
            existing.map { ($0.workoutId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let snapshotsByDay = Dictionary(uniqueKeysWithValues: snapshots.map {
            (DailyHealthSummaryRecord.dayIdentifier(for: $0.date, calendar: calendar), $0)
        })
        var created = 0
        var backfilled = 0

        for workout in workouts {
            let workoutDay = calendar.startOfDay(for: workout.startedAt)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: workoutDay) else { continue }
            let todayID = DailyHealthSummaryRecord.dayIdentifier(for: workoutDay, calendar: calendar)
            let nextDayID = DailyHealthSummaryRecord.dayIdentifier(for: nextDay, calendar: calendar)
            guard let today = snapshotsByDay[todayID], let following = snapshotsByDay[nextDayID] else { continue }

            let analysis = TrainingAnalyticsService().summarizeWorkout(workout.dto)
            let setRPEs = workout.exercises.flatMap(\.sets).compactMap(\.rpe)
            let sessionRPE = workout.sessionRPE ?? average(setRPEs)

            if let record = existingByWorkout[workout.id] {
                // T1 修复：手动记录路径（upsertTrainingResponseRecord）创建时
                // 次日增量留空，且从未有代码回填——导致内核「恢复响应欠佳」分支
                // 与 TrainingResponseCalibrator 对主路径永远拿到空输入。
                // 此处对已存在记录回填缺失增量（仅填 nil 字段且快照有值，不覆盖已有值）。
                var changed = false
                if record.nextDayRecoveryDelta == nil,
                   let recovery = delta(following.recoveryScore, today.recoveryScore) {
                    record.nextDayRecoveryDelta = recovery
                    changed = true
                }
                if record.nextDayHRVDelta == nil,
                   let hrv = delta(following.hrvAverage, today.hrvAverage) {
                    record.nextDayHRVDelta = hrv
                    changed = true
                }
                if record.nextDayRHRDelta == nil,
                   let rhr = delta(following.restingHeartRate, today.restingHeartRate) {
                    record.nextDayRHRDelta = rhr
                    changed = true
                }
                if record.nextDaySleepScore == nil, let sleep = following.sleepScore {
                    record.nextDaySleepScore = sleep
                    changed = true
                }
                if changed { backfilled += 1 }
                continue
            }

            let response = TrainingResponseRecord(
                workoutId: workout.id,
                date: workoutDay,
                nextDayDate: nextDay,
                primaryMuscleGroups: analysis.muscleGroupSets.keys.sorted(),
                totalEffectiveSets: analysis.effectiveSets,
                totalVolumeKg: analysis.totalVolumeKg,
                sessionRPE: sessionRPE,
                nextDayRecoveryDelta: delta(following.recoveryScore, today.recoveryScore),
                nextDayHRVDelta: delta(following.hrvAverage, today.hrvAverage),
                nextDayRHRDelta: delta(following.restingHeartRate, today.restingHeartRate),
                nextDaySleepScore: following.sleepScore
            )
            modelContext.insert(response)
            created += 1
        }

        if created > 0 || backfilled > 0 {
            try PersistenceWriteGate.shared.assertWritable(
                operation: "TrainingResponseInsightService: capture responses",
                modelContext: modelContext
            )
            try modelContext.save()
        }
        return created + backfilled
    }

    func buildWeeklyBodyReport(
        snapshots: [DailyHealthSnapshot],
        foodLogs: [FoodLogRecord],
        journalEntries: [JournalEntryRecord],
        strengthWorkouts: [StrengthWorkoutRecord],
        trainingResponses: [TrainingResponseRecord],
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyBodyReport {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-7 * 86_400)
        let weekSnapshots = snapshots.filter { $0.date >= start && $0.date < end }
        let weekWorkouts = strengthWorkouts.filter { $0.startedAt >= start && $0.startedAt < end }
        let weekResponses = trainingResponses.filter { $0.nextDayDate >= start && $0.nextDayDate < end }
        let weekFoodLogs = foodLogs.filter { $0.createdAt >= start && $0.createdAt < end }
        let weekJournalEntries = journalEntries.filter { $0.createdAt >= start && $0.createdAt < end }
        let recoveryAverage = average(
            weekSnapshots
                .filter(hasRecoverySourceData)
                .compactMap(\.recoveryScore)
        )
        let sleepAverage = average(
            weekSnapshots
                .filter(hasSleepSourceData)
                .compactMap(\.sleepScore)
        )
        
        let responseSummary = weekResponses.isEmpty
            ? "暂无足够的训练后次日数据。"
            : weekResponses.map {
                let muscles = $0.primaryMuscleGroups.isEmpty ? "未分类肌群" : $0.primaryMuscleGroups.joined(separator: "/")
                return "\(muscles)：恢复 \(formattedDelta($0.nextDayRecoveryDelta))，HRV \(formattedDelta($0.nextDayHRVDelta))，RHR \(formattedDelta($0.nextDayRHRDelta))"
            }.joined(separator: "\n")
            
        let workoutTitles = weekWorkouts.isEmpty ? "暂无力量训练" : weekWorkouts.map(\.title).joined(separator: "、")
        let journalTags = Set(weekJournalEntries.flatMap(\.tags)).sorted().joined(separator: "、")
        
        // --- 1. 睡眠-训练表现分析 (Sleep vs Performance) ---
        var sleepPerformanceAnalysis = "样本不足（需要至少 6 次带前一晚睡眠分的力量训练，且高、低睡眠组各至少 3 次）"
        if weekWorkouts.count >= 6 {
            var sleepScoresWithRPE: [(sleep: Double, rpe: Double)] = []
            for workout in weekWorkouts {
                let workoutDay = calendar.startOfDay(for: workout.startedAt)
                let previousDay = calendar.date(byAdding: .day, value: -1, to: workoutDay) ?? workoutDay
                let prevDayID = DailyHealthSummaryRecord.dayIdentifier(for: previousDay, calendar: calendar)
                
                if let snap = snapshots.first(where: { DailyHealthSummaryRecord.dayIdentifier(for: $0.date, calendar: calendar) == prevDayID }),
                   let sleep = snap.sleepScore {
                    let setRPEs = workout.exercises.flatMap(\.sets).compactMap(\.rpe)
                    let rpe = workout.sessionRPE ?? average(setRPEs) ?? 7.0
                    sleepScoresWithRPE.append((sleep, rpe))
                }
            }
            
            if sleepScoresWithRPE.count >= 6 {
                let highSleep = sleepScoresWithRPE.filter { $0.sleep >= 75 }
                let lowSleep = sleepScoresWithRPE.filter { $0.sleep < 75 }
                
                if highSleep.count >= 3 && lowSleep.count >= 3 {
                    let avgRPEHigh = highSleep.map(\.rpe).reduce(0, +) / Double(highSleep.count)
                    let avgRPELow = lowSleep.map(\.rpe).reduce(0, +) / Double(lowSleep.count)
                    let diff = avgRPELow - avgRPEHigh
                    if diff > 0 {
                        sleepPerformanceAnalysis = "本周记录中，高睡眠组（n=\(highSleep.count)）的训练主观疲劳 RPE 平均低 \(String(format: "%.1f", diff)) 分，低睡眠组为 n=\(lowSleep.count)。这只是观察到的组间差异，不代表睡眠是唯一原因。"
                    } else {
                        sleepPerformanceAnalysis = "本周高、低睡眠组（分别 n=\(highSleep.count) / n=\(lowSleep.count)）的训练主观疲劳 RPE 未见明确平均差异。"
                    }
                } else {
                    let avgSleep = sleepScoresWithRPE.map(\.sleep).reduce(0, +) / Double(sleepScoresWithRPE.count)
                    sleepPerformanceAnalysis = "训练日前一晚的睡眠分分布较为单一（平均 \(String(format: "%.0f", avgSleep)) 分），无法形成平衡的组间观察。"
                }
            }
        }
        
        // --- 2. 饮食-恢复分析 (Diet vs Recovery) ---
        var dietRecoveryAnalysis = "样本不足（需要至少 2 个有餐食记录日和 2 个无餐食记录日，且均有恢复分）"
        if weekFoodLogs.count >= 3 {
            var daysWithFoodLogs = Set<String>()
            for log in weekFoodLogs {
                daysWithFoodLogs.insert(DailyHealthSummaryRecord.dayIdentifier(for: log.createdAt, calendar: calendar))
            }
            
            var recoveryWithFood: [Double] = []
            var recoveryWithoutFood: [Double] = []
            
            for snap in weekSnapshots {
                let dayID = DailyHealthSummaryRecord.dayIdentifier(for: snap.date, calendar: calendar)
                if let rec = snap.recoveryScore {
                    if daysWithFoodLogs.contains(dayID) {
                        recoveryWithFood.append(rec)
                    } else {
                        recoveryWithoutFood.append(rec)
                    }
                }
            }
            
            if recoveryWithFood.count >= 2 && recoveryWithoutFood.count >= 2 {
                let avgWith = recoveryWithFood.reduce(0, +) / Double(recoveryWithFood.count)
                let avgWithout = recoveryWithoutFood.reduce(0, +) / Double(recoveryWithoutFood.count)
                let diff = avgWith - avgWithout
                if diff > 0 {
                    dietRecoveryAnalysis = "本周有餐食记录日（n=\(recoveryWithFood.count)）的恢复分平均比无记录日（n=\(recoveryWithoutFood.count)）高 \(String(format: "%.1f", diff)) 分。这是记录状态的观察差异，不代表记录或进食本身造成了恢复变化。"
                } else {
                    dietRecoveryAnalysis = "本周有餐食记录日（n=\(recoveryWithFood.count)）与无记录日（n=\(recoveryWithoutFood.count)）的恢复分未见明确平均差异。"
                }
            } else {
                dietRecoveryAnalysis = "本周餐食记录或恢复分的分布不足，暂不做饮食与恢复的关联解读。"
            }
        }
        
        // --- 3. 生理压力源相关分析 (咖啡因/压力/熬夜/酒精) ---
        var stressorAnalysis = "样本不足（近一周需要至少 2 条带压力源标签的日志记录以分析关联）"
        if weekJournalEntries.count >= 2 {
            var caffeineImpact: [Double] = []
            var stressImpact: [Double] = []
            var lateImpact: [Double] = []
            var alcoholImpact: [Double] = []
            
            for entry in weekJournalEntries {
                let dayID = DailyHealthSummaryRecord.dayIdentifier(for: entry.createdAt, calendar: calendar)
                guard let snap = weekSnapshots.first(where: { DailyHealthSummaryRecord.dayIdentifier(for: $0.date, calendar: calendar) == dayID }),
                      let recovery = snap.recoveryScore else { continue }
                
                let tags = entry.tags.map { $0.lowercased() }
                if tags.contains(where: { $0.contains("caffeine") || $0.contains("coffee") || $0.contains("咖啡") }) {
                    caffeineImpact.append(recovery)
                }
                if tags.contains(where: { $0.contains("stress") || $0.contains("压力") || $0.contains("焦虑") }) {
                    stressImpact.append(recovery)
                }
                if tags.contains(where: { $0.contains("late") || $0.contains("熬夜") || $0.contains("晚睡") }) {
                    lateImpact.append(recovery)
                }
                if tags.contains(where: { $0.contains("alcohol") || $0.contains("酒") || $0.contains("啤酒") || $0.contains("饮酒") }) {
                    alcoholImpact.append(recovery)
                }
            }
            
            var findings: [String] = []
            let normalRecovery = recoveryAverage ?? 70.0
            
            if lateImpact.count >= 2 {
                let avg = lateImpact.reduce(0, +) / Double(lateImpact.count)
                let diff = avg - normalRecovery
                findings.append("熬夜标签日（n=\(lateImpact.count)）平均恢复分为 \(String(format: "%.1f", avg))（相对本周平均 \(String(format: "%+.1f", diff))）")
            }
            if alcoholImpact.count >= 2 {
                let avg = alcoholImpact.reduce(0, +) / Double(alcoholImpact.count)
                let diff = avg - normalRecovery
                findings.append("饮酒标签日（n=\(alcoholImpact.count)）平均恢复分为 \(String(format: "%.1f", avg))（相对本周平均 \(String(format: "%+.1f", diff))）")
            }
            if stressImpact.count >= 2 {
                let avg = stressImpact.reduce(0, +) / Double(stressImpact.count)
                let diff = avg - normalRecovery
                findings.append("高压力标签日（n=\(stressImpact.count)）平均恢复分为 \(String(format: "%.1f", avg))（相对本周平均 \(String(format: "%+.1f", diff))）")
            }
            if caffeineImpact.count >= 2 {
                let avg = caffeineImpact.reduce(0, +) / Double(caffeineImpact.count)
                let diff = avg - normalRecovery
                findings.append("咖啡因标签日（n=\(caffeineImpact.count)）平均恢复分为 \(String(format: "%.1f", avg))（相对本周平均 \(String(format: "%+.1f", diff))）")
            }
            
            if !findings.isEmpty {
                stressorAnalysis = "以下为本周记录的观察值，不代表因果关系：\n- " + findings.joined(separator: "\n- ")
            } else {
                stressorAnalysis = "可识别的压力源标签样本不足，暂不做关联解读。"
            }
        }

        let markdown: String
        if AppLanguage.stored.isChinese {
        markdown = """
        # 每周身体报告

        ## 训练
        - 力量训练：\(weekWorkouts.count) 次（\(workoutTitles)）
        - 训练后次日反应记录：\(weekResponses.count) 条

        ## 恢复与睡眠
        - 平均恢复分：\(formatted(recoveryAverage))
        - 平均睡眠分：\(formatted(sleepAverage))

        ## 饮食与习惯
        - 饮食记录：\(weekFoodLogs.count) 条
        - 日志标签：\(journalTags.isEmpty ? "暂无" : journalTags)

        ## 训练后次日反应
        \(responseSummary)

        ## 进阶关联分析

        ### 睡眠与训练表现关联
        \(sleepPerformanceAnalysis)

        ### 饮食与恢复关联
        \(dietRecoveryAnalysis)

        ### 生理压力源相关分析（咖啡因/压力/熬夜/酒精与生理恢复）
        \(stressorAnalysis)
        """
        } else {
        markdown = """
        # Weekly Body Report

        ## Training
        - Strength sessions: \(weekWorkouts.count) (\(workoutTitles))
        - Next-day response records: \(weekResponses.count)

        ## Recovery & Sleep
        - Average recovery: \(formatted(recoveryAverage))
        - Average sleep: \(formatted(sleepAverage))

        ## Nutrition & Habits
        - Food logs: \(weekFoodLogs.count)
        - Journal tags: \(journalTags.isEmpty ? "none" : journalTags)

        ## Next-Day Training Responses
        \(responseSummary)

        ## Correlation Analysis

        ### Sleep & Training Performance
        \(sleepPerformanceAnalysis)

        ### Nutrition & Recovery
        \(dietRecoveryAnalysis)

        ### Physiological Stressors (caffeine/stress/late nights/alcohol)
        \(stressorAnalysis)
        """
        }
        
        return WeeklyBodyReport(
            generatedAt: endDate,
            markdown: markdown,
            trainingSessions: weekWorkouts.count,
            averageRecoveryScore: recoveryAverage,
            averageSleepScore: sleepAverage,
            trainingResponseCount: weekResponses.count
        )
    }

    @discardableResult
    func persistWeeklyBodyReportIfNeeded(
        modelContext: ModelContext,
        snapshots: [DailyHealthSnapshot],
        foodLogs: [FoodLogRecord],
        journalEntries: [JournalEntryRecord],
        strengthWorkouts: [StrengthWorkoutRecord],
        trainingResponses: [TrainingResponseRecord],
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> AIReportRecord? {
        let reports = try modelContext.fetch(FetchDescriptor<AIReportRecord>(
            predicate: #Predicate<AIReportRecord> { $0.type == "weekly_body_report" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        if let latest = reports.first,
           calendar.isDate(latest.createdAt, equalTo: endDate, toGranularity: .weekOfYear) {
            return nil
        }
        let report = buildWeeklyBodyReport(
            snapshots: snapshots,
            foodLogs: foodLogs,
            journalEntries: journalEntries,
            strengthWorkouts: strengthWorkouts,
            trainingResponses: trainingResponses,
            endingAt: endDate,
            calendar: calendar
        )
        try PersistenceWriteGate.shared.assertWritable(
            operation: "TrainingResponseInsightService: persist weekly report",
            modelContext: modelContext
        )
        let record = AIReportRecord(
            createdAt: endDate,
            type: "weekly_body_report",
            title: AppLanguage.stored.isChinese ? "每周身体报告" : "Weekly Body Report",
            markdownContent: report.markdown,
            serializedContextSnapshot: "{}",
            tags: ["weekly_body_report", "training_intelligence"]
        )
        modelContext.insert(record)
        try modelContext.save()
        return record
    }

    /// Builds a deterministic 30-day review from locally persisted facts. A trend is
    /// shown only when both 15-day windows contain at least five sourced samples.
    func buildMonthlyBodyReport(
        snapshots: [DailyHealthSnapshot],
        foodLogs: [FoodLogRecord],
        journalEntries: [JournalEntryRecord],
        strengthWorkouts: [StrengthWorkoutRecord],
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyBodyReport {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end.addingTimeInterval(-30 * 86_400)
        let midpoint = calendar.date(byAdding: .day, value: -15, to: end) ?? end.addingTimeInterval(-15 * 86_400)
        let monthSnapshots = snapshots.filter { $0.date >= start && $0.date < end }
        let sourcedRecovery = monthSnapshots.filter(hasRecoverySourceData)
        let sourcedSleep = monthSnapshots.filter(hasSleepSourceData)
        let monthWorkouts = strengthWorkouts.filter { $0.startedAt >= start && $0.startedAt < end }
        let monthFoodLogs = foodLogs.filter { $0.createdAt >= start && $0.createdAt < end }
        let monthJournalEntries = journalEntries.filter { $0.createdAt >= start && $0.createdAt < end }

        let recoveryAverage = average(sourcedRecovery.compactMap(\.recoveryScore))
        let sleepAverage = average(sourcedSleep.compactMap(\.sleepScore))
        let recoveryTrend = monthlyTrend(
            label: "恢复分",
            older: sourcedRecovery.filter { $0.date < midpoint }.compactMap(\.recoveryScore),
            recent: sourcedRecovery.filter { $0.date >= midpoint }.compactMap(\.recoveryScore)
        )
        let sleepTrend = monthlyTrend(
            label: "睡眠分",
            older: sourcedSleep.filter { $0.date < midpoint }.compactMap(\.sleepScore),
            recent: sourcedSleep.filter { $0.date >= midpoint }.compactMap(\.sleepScore)
        )
        let hrvTrend = monthlyTrend(
            label: "HRV",
            older: monthSnapshots.filter { $0.date < midpoint }.compactMap(\.hrvAverage),
            recent: monthSnapshots.filter { $0.date >= midpoint }.compactMap(\.hrvAverage),
            unit: " ms"
        )
        let rhrTrend = monthlyTrend(
            label: "静息心率",
            older: monthSnapshots.filter { $0.date < midpoint }.compactMap(\.restingHeartRate),
            recent: monthSnapshots.filter { $0.date >= midpoint }.compactMap(\.restingHeartRate),
            unit: " bpm"
        )

        let groupedTags: [String: [String]] = Dictionary(
            grouping: monthJournalEntries.flatMap(\.tags),
            by: { $0 }
        )
        let tagCountPairs: [(key: String, value: Int)] = groupedTags.map { key, values in
            (key: key, value: values.count)
        }
        let topTags = tagCountPairs
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(5)
        let tagCounts = topTags
            .map { pair in "\(pair.key)（\(pair.value) 次）" }
            .joined(separator: "、")
        let coveredDayIDs = Set(monthSnapshots.map {
            DailyHealthSummaryRecord.dayIdentifier(for: $0.date, calendar: calendar)
        })

        let markdown: String
        if AppLanguage.stored.isChinese {
        markdown = """
        # 月度身体总结

        ## 数据覆盖
        - 观察窗口：最近 30 天
        - 有健康快照：\(coveredDayIDs.count) / 30 天
        - 有恢复来源：\(sourcedRecovery.count) 天
        - 有睡眠来源：\(sourcedSleep.count) 天

        ## 本月概览
        - 平均恢复分：\(formatted(recoveryAverage))
        - 平均睡眠分：\(formatted(sleepAverage))
        - 力量训练：\(monthWorkouts.count) 次
        - 餐食记录：\(monthFoodLogs.count) 条
        - 日志记录：\(monthJournalEntries.count) 条
        - 常见日志标签：\(tagCounts.isEmpty ? "暂无" : tagCounts)

        ## 前后半月趋势
        - \(recoveryTrend)
        - \(sleepTrend)
        - \(hrvTrend)
        - \(rhrTrend)

        ## 解读边界
        趋势只比较两个 15 天窗口的已记录均值；每个窗口少于 5 个有效样本时不显示方向。观察到的同步变化不代表因果关系，也不构成医疗诊断。
        """
        } else {
        markdown = """
        # Monthly Body Summary

        ## Data Coverage
        - Window: last 30 days
        - Days with health snapshots: \(coveredDayIDs.count) / 30
        - Days with recovery source: \(sourcedRecovery.count)
        - Days with sleep source: \(sourcedSleep.count)

        ## Overview
        - Average recovery: \(formatted(recoveryAverage))
        - Average sleep: \(formatted(sleepAverage))
        - Strength sessions: \(monthWorkouts.count)
        - Food logs: \(monthFoodLogs.count)
        - Journal entries: \(monthJournalEntries.count)
        - Common tags: \(tagCounts.isEmpty ? "none" : tagCounts)

        ## First vs Second Half Trends
        - \(recoveryTrend)
        - \(sleepTrend)
        - \(hrvTrend)
        - \(rhrTrend)

        ## Interpretation Boundary
        Trends only compare recorded means of the two 15-day windows; a direction is shown only when each window has at least 5 valid samples. Observed co-movement does not imply causation and is not medical diagnosis.
        """
        }

        return MonthlyBodyReport(
            generatedAt: endDate,
            markdown: markdown,
            observedDays: coveredDayIDs.count,
            averageRecoveryScore: recoveryAverage,
            averageSleepScore: sleepAverage,
            trainingSessions: monthWorkouts.count
        )
    }

    @discardableResult
    func persistMonthlyBodyReportIfNeeded(
        modelContext: ModelContext,
        snapshots: [DailyHealthSnapshot],
        foodLogs: [FoodLogRecord],
        journalEntries: [JournalEntryRecord],
        strengthWorkouts: [StrengthWorkoutRecord],
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> AIReportRecord? {
        let reports = try modelContext.fetch(FetchDescriptor<AIReportRecord>(
            predicate: #Predicate<AIReportRecord> { $0.type == "monthly_body_report" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        if let latest = reports.first,
           calendar.isDate(latest.createdAt, equalTo: endDate, toGranularity: .month) {
            return nil
        }
        let report = buildMonthlyBodyReport(
            snapshots: snapshots,
            foodLogs: foodLogs,
            journalEntries: journalEntries,
            strengthWorkouts: strengthWorkouts,
            endingAt: endDate,
            calendar: calendar
        )
        try PersistenceWriteGate.shared.assertWritable(
            operation: "TrainingResponseInsightService: persist monthly report",
            modelContext: modelContext
        )
        let record = AIReportRecord(
            createdAt: endDate,
            type: "monthly_body_report",
            title: AppLanguage.stored.isChinese ? "月度身体总结" : "Monthly Body Review",
            markdownContent: report.markdown,
            serializedContextSnapshot: "{}",
            tags: ["monthly_body_report", "training_intelligence", "local_only"]
        )
        modelContext.insert(record)
        try modelContext.save()
        return record
    }

    func proposeStableTrainingResponses(
        modelContext: ModelContext,
        responses: [TrainingResponseRecord]
    ) throws -> Int {
        let existing = try modelContext.fetch(FetchDescriptor<MemoryEventRecord>(
            predicate: #Predicate<MemoryEventRecord> { $0.source == "training_response_model" }
        ))
        let grouped = Dictionary(grouping: responses.flatMap { response in
            response.primaryMuscleGroups.map { ($0, response) }
        }, by: \.0)
        let ledger = MemoryLedger(modelContext: modelContext)
        var created = 0

        for (muscle, pairs) in grouped {
            let records = pairs.map(\.1)
            let recoveryDeltas = records.compactMap(\.nextDayRecoveryDelta)
            guard records.count >= 8,
                  recoveryDeltas.count >= 6,
                  let recoveryDelta = average(recoveryDeltas),
                  abs(recoveryDelta) >= 5,
                  !existing.contains(where: { $0.content.contains("**肌群**: \(muscle)") || $0.content.contains("**Muscle group**: \(muscle)") }) else {
                continue
            }
            let hrvDelta = average(records.compactMap(\.nextDayHRVDelta))
            let rhrDelta = average(records.compactMap(\.nextDayRHRDelta))
            let content = """
            **肌群**: \(muscle)
            **规律**: \(muscle) 训练后次日恢复平均变化 \(formattedDelta(recoveryDelta))
            **HRV 变化**: \(formattedDelta(hrvDelta))
            **静息心率变化**: \(formattedDelta(rhrDelta))
            **观察次数**: \(records.count)
            """
            _ = try ledger.createProposal(
                targetFile: "training_history.md",
                memoryType: .observation,
                content: content,
                evidence: "\(records.count) 次训练后次日恢复记录",
                confidence: min(0.9, 0.50 + Double(recoveryDeltas.count) * 0.035),
                source: "training_response_model"
            )
            created += 1
        }
        return created
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func hasRecoverySourceData(_ snapshot: DailyHealthSnapshot) -> Bool {
        snapshot.hrvAverage != nil
            || snapshot.restingHeartRate != nil
            || hasSleepSourceData(snapshot)
    }

    private func hasSleepSourceData(_ snapshot: DailyHealthSnapshot) -> Bool {
        snapshot.sleepHours.map { $0 > 0 } == true
            || snapshot.deepSleepMinutes.map { $0 > 0 } == true
            || snapshot.remSleepMinutes.map { $0 > 0 } == true
    }

    private func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    private func formatted(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "暂无"
    }

    private func formattedDelta(_ value: Double?) -> String {
        value.map { String(format: "%+.1f", $0) } ?? "暂无"
    }

    private func monthlyTrend(
        label: String,
        older: [Double],
        recent: [Double],
        unit: String = " 分"
    ) -> String {
        guard older.count >= 5, recent.count >= 5,
              let olderAverage = average(older), let recentAverage = average(recent) else {
            return "\(label)：样本不足（前、后半月各需至少 5 个有效样本）"
        }
        let difference = recentAverage - olderAverage
        let direction = abs(difference) < 0.5 ? "基本稳定" : (difference > 0 ? "后半月较高" : "后半月较低")
        return "\(label)：\(direction) \(String(format: "%+.1f", difference))\(unit)（n=\(older.count) / \(recent.count)）"
    }
}
