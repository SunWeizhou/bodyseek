import Foundation
import SwiftData

/// Core engine that translates raw multi-system health data into a structured
/// BodyInterpretation with fatigue analysis, limiter identification, training
/// window assessment, risk flags, and evidence-backed recommendations.
struct BodyInterpreterEngine {

    static let schemaVersion = "v3.0-beta"

    // MARK: - Entry Point

    func interpret(
        dashboard: DashboardSummary,
        wiki: [String: String],
        activePlan: TrainingPlanRecord?,
        weeklyTrends: [String: String] = [:],
        foodLogs: [FoodLogRecord] = [],
        journalEntries: [JournalEntryRecord] = [],
        healthSnapshots: [DailyHealthSnapshot] = []
    ) -> BodyInterpretation {
        var confidence: [String: DataConfidence] = [:]

        // ── 1. Analyze fatigue sources ──
        let fatigueResult = analyzeFatigue(dashboard: dashboard, confidence: &confidence)
        let fatigueSources = fatigueResult.sources
        let totalFatigue = fatigueResult.rawTotal
        let fatigueLevel = classifyFatigueLevel(totalFatigue)

        // ── 2. Identify primary limiter ──
        let primaryLimiter = identifyPrimaryLimiter(
            dashboard: dashboard,
            fatigueSources: fatigueSources,
            confidence: &confidence
        )
        let secondaryLimiters = identifySecondaryLimiters(
            dashboard: dashboard,
            primary: primaryLimiter
        )

        // ── 3. Assess training window ──
        let trainingWindow = assessTrainingWindow(
            dashboard: dashboard,
            fatigueLevel: fatigueLevel,
            primaryLimiter: primaryLimiter,
            wiki: wiki
        )

        // ── 4. Generate recovery tasks ──
        let recoveryTasks = generateRecoveryTasks(
            dashboard: dashboard,
            fatigueSources: fatigueSources,
            primaryLimiter: primaryLimiter,
            wiki: wiki
        )

        // ── 5. Identify risk flags ──
        let riskFlags = identifyRiskFlags(
            dashboard: dashboard,
            fatigueLevel: fatigueLevel,
            primaryLimiter: primaryLimiter,
            weeklyTrends: weeklyTrends
        )

        // ── 6. Build readiness narrative ──
        let readinessNarrative = buildNarrative(
            dashboard: dashboard,
            fatigueLevel: fatigueLevel,
            primaryLimiter: primaryLimiter,
            fatigueSources: fatigueSources,
            trainingWindow: trainingWindow
        )

        // ── 7. Build recommended action ──
        let recommendedAction = buildRecommendedAction(
            dashboard: dashboard,
            fatigueLevel: fatigueLevel,
            primaryLimiter: primaryLimiter,
            trainingWindow: trainingWindow,
            wiki: wiki
        )

        // ── 8. Determine daily state ──
        let dailyState = computeDailyState(
            dashboard: dashboard,
            fatigueLevel: fatigueLevel,
            trainingWindow: trainingWindow
        )

        let readinessScore = computeReadiness(dashboard: dashboard, fatigueLevel: fatigueLevel)

        let interpretation = BodyInterpretation(
            generatedAt: Date(),
            contextHash: "",
            dailyState: dailyState,
            fatigueLevel: fatigueLevel,
            readinessScore: readinessScore,
            fatigueSources: fatigueSources,
            primaryLimiter: primaryLimiter,
            secondaryLimiters: secondaryLimiters,
            readinessNarrative: readinessNarrative,
            trainingWindow: trainingWindow,
            recoveryTasks: recoveryTasks,
            riskFlags: riskFlags,
            recommendedAction: recommendedAction,
            alternativeActions: buildAlternativeActions(
                dashboard: dashboard,
                primary: recommendedAction,
                wiki: wiki
            ),
            overallConfidence: computeOverallConfidence(confidence),
            confidenceBreakdown: confidence
        )

        var withHash = interpretation
        if let data = try? JSONEncoder().encode(interpretation),
           let json = String(data: data, encoding: .utf8) {
            withHash.contextHash = ContentHash.hash(json)
        }
        return withHash
    }

    // MARK: - Fatigue Analysis

    private func analyzeFatigue(
        dashboard: DashboardSummary,
        confidence: inout [String: DataConfidence]
    ) -> (sources: [FatigueSource], rawTotal: Double) {
        var sources: [FatigueSource] = []

        let hrvMs = dashboard.recoveryMetrics.hrvMilliseconds
        let rhrBpm = dashboard.recoveryMetrics.restingHeartRate
        let hrvZScore = dashboard.recovery.metrics["hrv_z_score"] ?? 0
        let sleepScore = dashboard.sleepScore.value
        let sleepEfficiency = dashboard.sleepScore.metrics["sleep_efficiency"]
        let strainScore = dashboard.strain.score
        let stressIndex = dashboard.stress.stressIndex

        // Autonomic fatigue: HRV suppressed + RHR elevated
        var autonomicContribution = 0.0
        var autonomicEvidence: [String] = []
        var autonomicMetrics: [String: Double] = [:]

        if let hrvMs, hrvMs > 0, let rhrBpm, rhrBpm > 0 {
            autonomicMetrics["hrv_ms"] = hrvMs
            autonomicMetrics["rhr_bpm"] = rhrBpm
            autonomicMetrics["hrv_z_score"] = hrvZScore

            if hrvZScore < -1.0 {
                autonomicContribution += 0.40
                autonomicEvidence.append("HRV Z-score \(String(format: "%.1f", hrvZScore)): significantly suppressed")
            } else if hrvZScore < -0.3 {
                autonomicContribution += 0.20
                autonomicEvidence.append("HRV Z-score \(String(format: "%.1f", hrvZScore)): mildly suppressed")
            }

            if rhrBpm > 65 {
                autonomicContribution += 0.15
                autonomicEvidence.append("Resting HR \(Int(rhrBpm)) bpm: elevated")
            }

            confidence["autonomic"] = hrvMs > 0 ? .high : .medium
        }

        if autonomicContribution > 0 {
            sources.append(FatigueSource(
                category: .autonomic,
                contribution: min(autonomicContribution, 1.0),
                evidence: autonomicEvidence,
                metrics: autonomicMetrics
            ))
        }

        // Muscular fatigue: high strain + gait changes
        var muscularContribution = 0.0
        var muscularEvidence: [String] = []
        var muscularMetrics: [String: Double] = [:]

        if strainScore > 65 {
            muscularContribution += 0.25
            muscularEvidence.append("Strain score \(Int(strainScore))/100: high training load")
        }
        muscularMetrics["strain_score"] = strainScore

        if let asymmetry = dashboard.extendedMetrics.walkingAsymmetry, asymmetry > 3.0 {
            muscularContribution += 0.15
            muscularEvidence.append("Walking asymmetry \(String(format: "%.1f", asymmetry))%: above normal")
        }
        if let doubleSupport = dashboard.extendedMetrics.walkingDoubleSupport, doubleSupport > 28 {
            muscularContribution += 0.15
            muscularEvidence.append("Double support \(String(format: "%.1f", doubleSupport))%: indicates fatigue")
        }

        if muscularContribution > 0 {
            sources.append(FatigueSource(
                category: .muscular,
                contribution: min(muscularContribution, 1.0),
                evidence: muscularEvidence,
                metrics: muscularMetrics
            ))
        }

        // Sleep deficit
        if let sleepScore, sleepScore < 70 {
            let efficiencyText = sleepEfficiency.map { String(format: "%.0f", $0) } ?? "暂无"
            var sleepMetrics: [String: Double] = ["sleep_score": sleepScore]
            if let sleepEfficiency {
                sleepMetrics["sleep_efficiency"] = sleepEfficiency
            }
            sources.append(FatigueSource(
                category: .sleepRelated,
                contribution: sleepScore < 50 ? 0.35 : 0.20,
                evidence: ["Sleep score \(Int(sleepScore))/100, efficiency \(efficiencyText)%"],
                metrics: sleepMetrics
            ))
            confidence["sleep"] = .high
        }

        // Mental stress
        if stressIndex > 50 {
            sources.append(FatigueSource(
                category: .mentalStress,
                contribution: stressIndex > 70 ? 0.25 : 0.12,
                evidence: ["Stress index \(Int(stressIndex))/100"],
                metrics: ["stress_index": stressIndex]
            ))
        }

        // 疲劳等级分类使用归一化前的原始总贡献（阈值 0.1/0.3/0.5/0.7 按原始量级设计）；
        // 归一化后的值仅用于展示层相对权重，归一化本身会令总和恒为 1，不能参与阈值判定。
        let rawTotal = sources.map(\.contribution).reduce(0, +)

        // Normalize contributions for relative display weights
        if rawTotal > 0 {
            sources = sources.map { src in
                var s = src
                s = FatigueSource(
                    id: s.id,
                    category: s.category,
                    contribution: s.contribution / rawTotal,
                    evidence: s.evidence,
                    metrics: s.metrics
                )
                return s
            }
        }

        return (sources, rawTotal)
    }

    private func classifyFatigueLevel(_ totalFatigue: Double) -> FatigueLevel {
        if totalFatigue < 0.1 { return .none }
        if totalFatigue < 0.3 { return .mild }
        if totalFatigue < 0.5 { return .moderate }
        if totalFatigue < 0.7 { return .significant }
        return .severe
    }

    // MARK: - Limiter Identification

    private func identifyPrimaryLimiter(
        dashboard: DashboardSummary,
        fatigueSources: [FatigueSource],
        confidence: inout [String: DataConfidence]
    ) -> PrimaryLimiter {
        guard dashboard.recovery.hasData || dashboard.sleepScore.hasData else {
            confidence["data_coverage"] = .unavailable
            return PrimaryLimiter(
                system: "Data Coverage",
                metricName: "Data Coverage",
                currentValue: 0,
                optimalRange: 1...1,
                severity: 1,
                interpretation: AppLanguage.stored.isChinese
                    ? "健康信号不足，暂不对恢复状态做数值判断。"
                    : "Health signals are insufficient, so recovery cannot be scored yet."
            )
        }

        let recoveryScore = dashboard.recovery.score
        let sleepScore = dashboard.sleepScore.value
        let hrvZScore = dashboard.recovery.metrics["hrv_z_score"] ?? 0
        let tsb = dashboard.energy.metrics["tsb"]
        let stressIndex = dashboard.stress.stressIndex

        // Check autonomic first (HRV + RHR)
        if hrvZScore < -1.0 {
            return PrimaryLimiter(
                system: "Autonomic Nervous System",
                metricName: "HRV Z-Score",
                currentValue: hrvZScore,
                optimalRange: -0.3...1.0,
                severity: min(abs(hrvZScore) / 3.0, 1.0),
                interpretation: AppLanguage.stored.isChinese
                    ? "HRV 低于个人基线，是今天需要保守安排恢复与训练的一个信号；单一指标不用于判断自主神经功能。"
                    : "HRV is below your personal baseline, one signal to plan recovery and training conservatively today; it does not diagnose autonomic function."
            )
        }

        // Check training load
        if let tsb, tsb < -15 {
            return PrimaryLimiter(
                system: "Training Load Balance",
                metricName: "TSB (Training Stress Balance)",
                currentValue: tsb,
                optimalRange: -5...15,
                severity: min(abs(tsb) / 30.0, 1.0),
                interpretation: AppLanguage.stored.isChinese
                    ? "近期训练负荷高于长期负荷趋势，TSB 明显为负，今天宜保守安排训练量。"
                    : "Recent training load is above the longer-term trend and TSB is notably negative, so today's volume should be conservative."
            )
        }

        // Check sleep
        if let sleepScore, sleepScore < 75 {
            return PrimaryLimiter(
                system: "Sleep Recovery",
                metricName: "Sleep Score",
                currentValue: sleepScore,
                optimalRange: 80...100,
                severity: (80 - sleepScore) / 80,
                interpretation: AppLanguage.stored.isChinese
                    ? "睡眠评分低于目标范围，今天的训练强度和容量建议会相应保守。"
                    : "Sleep score is below the target range, so today's intensity and volume guidance is more conservative."
            )
        }

        // Check stress
        if stressIndex > 60 {
            return PrimaryLimiter(
                system: "Physiological Stress Proxy",
                metricName: "Stress Index",
                currentValue: stressIndex,
                optimalRange: 0...30,
                severity: stressIndex / 100,
                interpretation: AppLanguage.stored.isChinese
                    ? "生理压力代理值偏高，今天建议保守安排训练，并结合主观感受判断。"
                    : "The physiological stress proxy is elevated; plan training conservatively today and consider how you feel."
            )
        }

        // Default: recovery is the limiter
        return PrimaryLimiter(
            system: "Recovery Status",
            metricName: "Recovery Score",
            currentValue: recoveryScore,
            optimalRange: 75...100,
            severity: max(0, (75 - recoveryScore) / 75),
            interpretation: AppLanguage.stored.isChinese
                ? "整体恢复状态是当前主要限制因素。"
                : "Overall recovery status is the primary limiting factor."
        )
    }

    private func identifySecondaryLimiters(
        dashboard: DashboardSummary,
        primary: PrimaryLimiter
    ) -> [PrimaryLimiter] {
        var limiters: [PrimaryLimiter] = []

        let sleepScore = dashboard.sleepScore.value
        let strainScore = dashboard.strain.score

        if let sleepScore, primary.metricName != "Sleep Score" && sleepScore < 80 {
            limiters.append(PrimaryLimiter(
                system: "Sleep Recovery",
                metricName: "Sleep Score",
                currentValue: sleepScore,
                optimalRange: 80...100,
                severity: (80 - sleepScore) / 80,
                interpretation: "Sleep quality is suboptimal."
            ))
        }

        if dashboard.strain.hasData, primary.metricName != "Strain Score" && strainScore > 65 {
            limiters.append(PrimaryLimiter(
                system: "Training Load",
                metricName: "Strain Score",
                currentValue: strainScore,
                optimalRange: 30...60,
                severity: (strainScore - 60) / 40,
                interpretation: "Training load is elevated."
            ))
        }

        return limiters
    }

    // MARK: - Training Window

    private func assessTrainingWindow(
        dashboard: DashboardSummary,
        fatigueLevel: FatigueLevel,
        primaryLimiter: PrimaryLimiter,
        wiki: [String: String]
    ) -> TrainingWindow {
        guard dashboard.recovery.hasData || dashboard.sleepScore.hasData else {
            let constraint = AppLanguage.stored.isChinese
                ? "缺少睡眠与恢复信号，建议仅做轻量活动并根据主观感受调整。"
                : "Sleep and recovery signals are unavailable; keep activity light and adjust to how you feel."
            return TrainingWindow(
                isOpen: true,
                recommendedIntensity: "low",
                maxDurationMinutes: 30,
                targetHRZone: "Zone 1-2",
                bestTimeOfDay: nil,
                constraints: [constraint],
                narrative: constraint
            )
        }

        let tsb = dashboard.energy.metrics["tsb"]
        let sleepScore = dashboard.sleepScore.value
        let lang = AppLanguage.stored

        let isOpen: Bool
        let intensity: String
        let maxDuration: Int
        let hrZone: String?

        switch fatigueLevel {
        case .none:
            isOpen = true
            intensity = "high"
            maxDuration = 90
            hrZone = "Zone 2-5"
        case .mild:
            isOpen = true
            intensity = "moderate"
            maxDuration = 60
            hrZone = "Zone 2-4"
        case .moderate:
            isOpen = true
            intensity = "low"
            maxDuration = 45
            hrZone = "Zone 1-2"
        case .significant:
            isOpen = false
            intensity = "rest"
            maxDuration = 0
            hrZone = nil
        case .severe:
            isOpen = false
            intensity = "rest"
            maxDuration = 0
            hrZone = nil
        }

        // TSB override
        let finalIntensity: String
        if let tsb, tsb < -15 && intensity == "high" {
            finalIntensity = "moderate"
        } else if let tsb, tsb > 10 && intensity == "low" {
            finalIntensity = "moderate"
        } else {
            finalIntensity = intensity
        }

        var constraints: [String] = []
        if let sleepScore, sleepScore < 70 {
            constraints.append(lang.isChinese ? "睡眠不足，训练后恢复效率降低" : "Sleep deficit may slow post-training recovery")
        }
        if primaryLimiter.severity > 0.5 {
            constraints.append(lang.isChinese
                ? "\(primaryLimiter.system) 是当前主要限制因素"
                : "\(primaryLimiter.system) is the primary limiter"
            )
        }

        let narrative = buildTrainingWindowNarrative(
            isOpen: isOpen,
            intensity: finalIntensity,
            maxDuration: maxDuration,
            hrZone: hrZone,
            constraints: constraints,
            primaryLimiter: primaryLimiter,
            lang: lang
        )

        return TrainingWindow(
            isOpen: isOpen,
            recommendedIntensity: finalIntensity,
            maxDurationMinutes: maxDuration,
            targetHRZone: hrZone,
            bestTimeOfDay: sleepScore.map { $0 < 70 ? (lang.isChinese ? "下午" : "Afternoon") : (lang.isChinese ? "上午或下午" : "Morning or Afternoon") },
            constraints: constraints,
            narrative: narrative
        )
    }

    // MARK: - Recovery Tasks

    private func generateRecoveryTasks(
        dashboard: DashboardSummary,
        fatigueSources: [FatigueSource],
        primaryLimiter: PrimaryLimiter,
        wiki: [String: String]
    ) -> [RecoveryTask] {
        var tasks: [RecoveryTask] = []
        let lang = AppLanguage.stored

        // Sleep
        if dashboard.sleepScore.hasData, dashboard.sleepScore.score < 80 {
            tasks.append(RecoveryTask(
                category: "sleep",
                title: lang.isChinese ? "优先补足睡眠" : "Prioritize Sleep",
                description: lang.isChinese
                    ? "今晚比平时早 30 分钟上床，目标 7-9 小时睡眠。睡前 1 小时避免屏幕和蓝光。"
                    : "Go to bed 30 min earlier tonight. Target 7-9 hours. No screens 1 hour before bed.",
                durationMinutes: nil,
                priority: 0
            ))
        }

        // Hydration
        if let water = dashboard.extendedMetrics.waterMl, water < 1500 {
            tasks.append(RecoveryTask(
                category: "hydration",
                title: lang.isChinese ? "补充水分" : "Hydrate",
                description: lang.isChinese
                    ? "今日饮水量不足。目标 2000-2500ml，训练前后各补充 500ml。"
                    : "Water intake is low today. Target 2000-2500ml.",
                durationMinutes: nil,
                priority: 2
            ))
        }

        // Mobility / Active recovery
        if dashboard.recovery.hasData, dashboard.recovery.score < 60 {
            tasks.append(RecoveryTask(
                category: "mobility",
                title: lang.isChinese ? "泡沫轴放松 + 拉伸" : "Foam Rolling + Stretch",
                description: lang.isChinese
                    ? "15 分钟泡沫轴（股四头肌、腘绳肌、上背）+ 10 分钟静态拉伸。"
                    : "15 min foam rolling (quads, hamstrings, upper back) + 10 min static stretch.",
                durationMinutes: 25,
                priority: 1
            ))
        }

        // Breathwork for stress
        if dashboard.stress.hasData, dashboard.stress.stressIndex > 50 {
            tasks.append(RecoveryTask(
                category: "breathwork",
                title: lang.isChinese ? "深呼吸练习" : "Breathwork",
                description: lang.isChinese
                    ? "5 分钟 4-7-8 呼吸法（吸气 4 秒、屏息 7 秒、呼气 8 秒）。"
                    : "5 min 4-7-8 breathing (inhale 4s, hold 7s, exhale 8s).",
                durationMinutes: 5,
                priority: 1
            ))
        }

        return tasks.sorted { $0.priority < $1.priority }
    }

    // MARK: - Risk Flags

    private func identifyRiskFlags(
        dashboard: DashboardSummary,
        fatigueLevel: FatigueLevel,
        primaryLimiter: PrimaryLimiter,
        weeklyTrends: [String: String]
    ) -> [RiskFlag] {
        var flags: [RiskFlag] = []
        let lang = AppLanguage.stored

        // Overtraining risk
        if fatigueLevel == .significant || fatigueLevel == .severe {
            flags.append(RiskFlag(
                level: .critical,
                system: "Recovery",
                message: lang.isChinese ? "高负荷恢复提醒" : "High-Load Recovery Notice",
                detail: lang.isChinese
                    ? "多个可用信号显示疲劳较明显。今天建议暂停高强度训练，并结合主观感受决定是否休息或做温和活动。"
                    : "Available signals suggest notable fatigue. Pause high-intensity training today and use how you feel to choose rest or gentle movement.",
                triggeringMetrics: ["recovery_score", "hrv_z_score", "tsb"]
            ))
        }

        // Injury risk from gait
        if let asymmetry = dashboard.extendedMetrics.walkingAsymmetry, asymmetry > 4.0 {
            flags.append(RiskFlag(
                level: .warning,
                system: "Gait / Mobility",
                message: lang.isChinese ? "步态不对称需关注" : "Gait Asymmetry Notice",
                detail: lang.isChinese
                    ? "步行不对称性为 \(String(format: "%.1f", asymmetry))%。建议结合近期不适、训练变化和连续趋势观察；如有疼痛或持续异常，请咨询专业人士。"
                    : "Walking asymmetry is \(String(format: "%.1f", asymmetry))%. Interpret it with symptoms, training changes, and repeated trends; seek professional advice for pain or persistent changes.",
                triggeringMetrics: ["walking_asymmetry"]
            ))
        }

        // HRV suppression trend
        if let hrvTrend = weeklyTrends["hrv_trend"], hrvTrend.contains("declining") {
            flags.append(RiskFlag(
                level: .warning,
                system: "Autonomic",
                message: lang.isChinese ? "HRV 近期下降" : "HRV Recent Decline",
                detail: lang.isChinese
                    ? "本周 HRV 较上周下降。请结合睡眠、压力、训练和个人感受观察，今天可考虑降低训练量。"
                    : "HRV is lower this week than last week. Review sleep, stress, training, and how you feel; consider a lower-load session today.",
                triggeringMetrics: ["hrv_weekly_trend"]
            ))
        }

        return flags
    }

    // MARK: - Narrative

    private func buildNarrative(
        dashboard: DashboardSummary,
        fatigueLevel: FatigueLevel,
        primaryLimiter: PrimaryLimiter,
        fatigueSources: [FatigueSource],
        trainingWindow: TrainingWindow
    ) -> String {
        let lang = AppLanguage.stored

        let sourcesText = fatigueSources
            .sorted { $0.contribution > $1.contribution }
            .prefix(3)
            .map { src in
                let pct = Int((src.contribution * 100).rounded())
                return "\(src.category.label) (\(pct)%)"
            }
            .joined(separator: lang.isChinese ? "、" : ", ")

        if lang.isChinese {
            return """
            今天你的身体疲劳程度为「\(fatigueLevel.label)」。主要限制因素是\(primaryLimiter.system)。
            疲劳主要来自：\(sourcesText)。
            \(trainingWindow.narrative)
            \(primaryLimiter.interpretation)
            """
        }

        return """
        Your fatigue level today is "\(fatigueLevel.label)". The primary limiter is \(primaryLimiter.system).
        Fatigue stems mainly from: \(sourcesText).
        \(trainingWindow.narrative)
        \(primaryLimiter.interpretation)
        """
    }

    // MARK: - Recommended Action

    private func buildRecommendedAction(
        dashboard: DashboardSummary,
        fatigueLevel: FatigueLevel,
        primaryLimiter: PrimaryLimiter,
        trainingWindow: TrainingWindow,
        wiki: [String: String]
    ) -> RecommendedAction {
        let lang = AppLanguage.stored

        let evidenceItems = buildEvidenceChain(
            dashboard: dashboard,
            primaryLimiter: primaryLimiter,
            fatigueLevel: fatigueLevel
        )

        let type: DailyActionType
        let title: String
        let subtitle: String
        let detail: String

        switch trainingWindow.recommendedIntensity {
        case "high":
            type = .train
            title = lang.isChinese ? "🏋️ 最佳训练窗口" : "🏋️ Prime Training Window"
            subtitle = lang.isChinese
                ? "可承受高强度训练 \(trainingWindow.maxDurationMinutes) 分钟"
                : "Can handle high intensity for \(trainingWindow.maxDurationMinutes) min"
            detail = lang.isChinese
                ? "身体处于最佳恢复状态。建议：热身 Zone 1-2 (10 min) → 主训练 Zone 4-5 间歇或 5x5 力量 → 放松 (10 min)。"
                : "Body is in optimal recovery. Recommended: warmup Zone 1-2 (10 min) → main Zone 4-5 intervals or 5x5 strength → cooldown (10 min)."
        case "moderate":
            type = .train
            title = lang.isChinese ? "💪 常规训练日" : "💪 Regular Training Day"
            subtitle = lang.isChinese
                ? "建议中等强度，\(trainingWindow.maxDurationMinutes) 分钟"
                : "Moderate intensity, \(trainingWindow.maxDurationMinutes) min"
            detail = trainingWindow.narrative
        case "low":
            type = .activeRecovery
            title = lang.isChinese ? "🚶 轻量活动" : "🚶 Light Activity"
            subtitle = lang.isChinese
                ? "Zone 1-2 有氧或拉伸，\(trainingWindow.maxDurationMinutes) 分钟"
                : "Zone 1-2 cardio or stretch, \(trainingWindow.maxDurationMinutes) min"
            detail = trainingWindow.narrative
        default:
            type = .rest
            title = lang.isChinese ? "🛌 完整休息" : "🛌 Full Rest"
            subtitle = lang.isChinese ? "今天的训练就是休息" : "Your workout today is rest"
            detail = trainingWindow.narrative
        }

        return RecommendedAction(
            type: type,
            title: title,
            subtitle: subtitle,
            detailMarkdown: detail,
            evidenceChain: evidenceItems,
            priority: 0
        )
    }

    private func buildAlternativeActions(
        dashboard: DashboardSummary,
        primary: RecommendedAction,
        wiki: [String: String]
    ) -> [RecommendedAction] {
        var alternatives: [RecommendedAction] = []
        let lang = AppLanguage.stored

        if primary.type == .train {
            alternatives.append(RecommendedAction(
                type: .activeRecovery,
                title: lang.isChinese ? "替代：主动恢复" : "Alternative: Active Recovery",
                subtitle: lang.isChinese ? "瑜伽、散步或轻度拉伸" : "Yoga, walking, or light stretching",
                detailMarkdown: lang.isChinese ? "如果感觉疲劳，可以选择主动恢复代替训练。" : "If feeling tired, opt for active recovery instead.",
                evidenceChain: [],
                priority: 1
            ))
        }

        if dashboard.sleepScore.hasData, dashboard.sleepScore.score < 80 {
            alternatives.append(RecommendedAction(
                type: .sleepTip,
                title: lang.isChinese ? "附加：优化今晚睡眠" : "Bonus: Optimize Tonight's Sleep",
                subtitle: lang.isChinese ? "提前 30 分钟上床，避免咖啡因" : "30 min earlier bedtime, avoid caffeine",
                detailMarkdown: "",
                evidenceChain: [],
                priority: 2
            ))
        }

        return alternatives
    }

    // MARK: - Evidence Chain (Why This 2.0)

    private func buildEvidenceChain(
        dashboard: DashboardSummary,
        primaryLimiter: PrimaryLimiter,
        fatigueLevel: FatigueLevel
    ) -> [EvidenceChainItem] {
        var items: [EvidenceChainItem] = []

        // HRV
        if let hrvMs = dashboard.recoveryMetrics.hrvMilliseconds, hrvMs > 0 {
            let zScore = dashboard.recovery.metrics["hrv_z_score"] ?? 0
            items.append(EvidenceChainItem(
                metricName: "HRV",
                metricCategory: "recovery",
                currentValue: hrvMs,
                currentValueFormatted: "\(Int(hrvMs))",
                unit: "ms",
                baselineValue: nil,
                baselineFormatted: nil,
                trend: zScore < -0.3 ? .declining : .stable,
                trendDescription: "Z-score: \(String(format: "%.2f", zScore))",
                interpretation: zScore < -1.0
                    ? "HRV 显著低于个人基线"
                    : "HRV 接近个人基线范围",
                confidence: .high,
                dataFreshness: .today,
                source: .healthKit,
                actionImpact: zScore < -1.0
                    ? "HRV 偏低 → 建议结合睡眠和主观状态降低训练强度"
                    : "HRV 接近基线 → 仍需结合其他信号安排训练"
            ))
        }

        // RHR
        if let rhr = dashboard.recoveryMetrics.restingHeartRate, rhr > 0 {
            items.append(EvidenceChainItem(
                metricName: "Resting Heart Rate",
                metricCategory: "recovery",
                currentValue: rhr,
                currentValueFormatted: "\(Int(rhr))",
                unit: "bpm",
                baselineValue: nil,
                baselineFormatted: nil,
                trend: rhr > 65 ? .declining : .stable,
                trendDescription: rhr > 65 ? "偏高" : "正常",
                interpretation: rhr > 65
                    ? "静息心率偏高，可能反映恢复不足或压力"
                    : "静息心率正常",
                confidence: .high,
                dataFreshness: .today,
                source: .healthKit,
                actionImpact: rhr > 65
                    ? "RHR 偏高 → 身体可能未完全恢复"
                    : "RHR 正常 → 心血管系统状态良好"
            ))
        }

        // Sleep
        if dashboard.sleepScore.hasData {
            let sleepScore = dashboard.sleepScore.score
            items.append(EvidenceChainItem(
                metricName: "Sleep Score",
                metricCategory: "sleep",
                currentValue: sleepScore,
                currentValueFormatted: "\(Int(sleepScore))",
                unit: "pts",
                baselineValue: 85,
                baselineFormatted: "85",
                trend: sleepScore < 80 ? .declining : .stable,
                trendDescription: sleepScore < 80 ? "低于理想值" : "正常",
                interpretation: sleepScore < 70
                    ? "睡眠质量不足，影响次日恢复和表现"
                    : "睡眠质量可接受",
                confidence: .high,
                dataFreshness: .today,
                source: .healthKit,
                actionImpact: sleepScore < 70
                    ? "睡眠不足 → 建议降低训练强度，优先补眠"
                    : "睡眠充足 → 支持正常训练"
            ))
        }

        // TSB
        if let tsb = dashboard.energy.metrics["tsb"] {
            items.append(EvidenceChainItem(
                metricName: "TSB",
                metricCategory: "energy",
                currentValue: tsb,
                currentValueFormatted: "\(Int(tsb) > 0 ? "+" : "")\(Int(tsb))",
                unit: "AU",
                baselineValue: 0,
                baselineFormatted: "0",
                trend: tsb < -10 ? .declining : .stable,
                trendDescription: tsb < -15 ? "深度疲劳累积" : tsb < -5 ? "轻度疲劳" : "平衡",
                interpretation: tsb < -15
                    ? "TSB 深度为负，训练负荷累积过高"
                    : "TSB 在合理范围内",
                confidence: .medium,
                dataFreshness: .today,
                source: .computed,
                actionImpact: tsb < -15
                    ? "TSB 深度为负 → 必须减载"
                    : "TSB 正常 → 可维持当前训练负荷"
            ))
        }

        return items
    }

    // MARK: - State & Readiness

    private func computeDailyState(
        dashboard: DashboardSummary,
        fatigueLevel: FatigueLevel,
        trainingWindow: TrainingWindow
    ) -> DailyState {
        guard dashboard.recovery.hasData || dashboard.sleepScore.hasData else { return .unknown }
        switch fatigueLevel {
        case .none: return .great
        case .mild: return .good
        case .moderate: return .fair
        case .significant, .severe: return .poor
        }
    }

    private func computeReadiness(dashboard: DashboardSummary, fatigueLevel: FatigueLevel) -> Double {
        guard dashboard.recovery.hasData else { return 0 }
        let baseScore: Double
        switch fatigueLevel {
        case .none: baseScore = 90
        case .mild: baseScore = 75
        case .moderate: baseScore = 55
        case .significant: baseScore = 35
        case .severe: baseScore = 15
        }
        // Blend with actual recovery score
        let recoveryScore = dashboard.recovery.score
        return (baseScore * 0.6 + recoveryScore * 0.4)
    }

    private func computeOverallConfidence(_ breakdown: [String: DataConfidence]) -> DataConfidence {
        let values = Array(breakdown.values)
        if values.isEmpty { return .medium }
        let highCount = values.filter { $0 == .high }.count
        let lowCount = values.filter { $0 == .low || $0 == .unavailable }.count
        if Double(highCount) / Double(values.count) > 0.7 { return .high }
        if Double(lowCount) / Double(values.count) > 0.5 { return .low }
        return .medium
    }

    private func buildTrainingWindowNarrative(
        isOpen: Bool,
        intensity: String,
        maxDuration: Int,
        hrZone: String?,
        constraints: [String],
        primaryLimiter: PrimaryLimiter,
        lang: AppLanguage
    ) -> String {
        if !isOpen {
            return lang.isChinese
                ? "今天的训练窗口关闭。身体需要恢复，不建议进行结构化训练。专注于恢复任务。"
                : "Training window is closed today. Your body needs recovery. Focus on recovery tasks."
        }

        let zoneText = hrZone.map { " (\($0))" } ?? ""
        let constraintText = constraints.isEmpty ? "" : "\n\n" + (lang.isChinese ? "注意事项：" : "Notes: ") + constraints.joined(separator: "; ")

        if lang.isChinese {
            return "训练窗口已开启。建议强度：\(intensity)，最长 \(maxDuration) 分钟\(zoneText)。" + constraintText
        }
        return "Training window is open. Recommended intensity: \(intensity), max \(maxDuration) min\(zoneText)." + constraintText
    }
}
