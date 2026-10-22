import Foundation
import SwiftUI

enum DailyPlanKind: String, Codable, Hashable {
    case rest
    case recovery
    case train
    case maintain
    case protectSleep
    case downshift
}

enum DailyPlanAccent: String, Codable, Hashable {
    case recovery
    case sleep
    case strain
    case energy
    case stress
}

struct TodayExperienceNutrition: Codable, Hashable {
    var calories: Int
    var calorieTarget: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    static let empty = TodayExperienceNutrition(
        calories: 0,
        calorieTarget: 0,
        protein: 0,
        carbs: 0,
        fat: 0
    )

    var calorieProgress: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(1, max(0, Double(calories) / Double(calorieTarget)))
    }

    var calorieText: String {
        if calories == 0, protein == 0, carbs == 0, fat == 0 {
            return "今日未记录"
        }
        if calorieTarget > 0 {
            return "\(calories)/\(calorieTarget) kcal"
        }
        return calories > 0 ? "\(calories) kcal · 目标未设置" : "--"
    }

    var macroText: String {
        guard calories > 0 || protein > 0 || carbs > 0 || fat > 0 else { return "今日营养尚未记录" }
        return "蛋白 \(protein)g · 碳水 \(carbs)g · 脂肪 \(fat)g"
    }
}

struct TodayExperienceHero: Codable, Hashable {
    var scoreTitle: String
    var decisionTitle: String
    var summary: String
    var confidenceLabel: String
    var primaryActionTitle: String
}

struct TodayExperienceSignalCard: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var value: String
    var directionLabel: String
    var confidenceLabel: String
    var coverageLabel: String
    var subtitle: String
    var trend: [Double]
    var accent: DailyPlanAccent
    var state: MetricState
}

struct TodayExperienceAction: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var destination: String
    var isPrimary: Bool
    var evidence: String? = nil
}

struct TodayExperienceModel: Codable, Hashable, Sendable {
    var generatedAt: Date
    var hero: TodayExperienceHero
    var signalCards: [TodayExperienceSignalCard]
    var baselineFormation: PersonalBaselineFormation
    var evidenceChips: [String]
    var actions: [TodayExperienceAction]
    var nutrition: TodayExperienceNutrition
    var coachPreview: String

    static func build(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        trainingDecision: DailyTrainingDecision,
        readiness: ReadinessDecisionKind? = nil,
        generatedAt: Date = Date(),
        nutrition: TodayExperienceNutrition = .empty,
        history: [DailyHealthSummaryDTO] = [],
        baselineFormation: PersonalBaselineFormation = .ready,
        operatingPlan: DailyOperatingPlanPayload? = nil
    ) -> TodayExperienceModel {
        let hasReadinessData = dashboard.recovery.hasData
        let confidenceDetail = hasReadinessData ? label(for: bodyState.confidence) : "数据不足"
        // 算法打通（批次 A）：行动列表与 Hero 标题统一跟随 readiness（TodayCommandBuilder），
        // 而 readiness 投影自 TrainingDecisionKernel 的同一结论（rest↔recover 归一）；
        // Kernel 提供量化细节（容量/RPE）。同屏不再出现「标题说恢复、细节说 100%」的矛盾。
        let effectiveReadiness = readiness ?? Self.readinessMapping(for: trainingDecision)
        let brief = dashboard.personalHealthBrief
        var hero = TodayExperienceHero(
            scoreTitle: scoreTitle(dashboard),
            decisionTitle: decisionTitle(
                effectiveReadiness,
                brief: brief,
                hasReadinessData: hasReadinessData
            ),
            summary: summary(
                dashboard: dashboard,
                bodyState: bodyState,
                decision: trainingDecision,
                brief: brief,
                hasReadinessData: hasReadinessData
            ),
            confidenceLabel: confidenceDetail,
            primaryActionTitle: primaryActionTitle(
                effectiveReadiness,
                brief: brief,
                hasReadinessData: hasReadinessData
            )
        )
        if let primaryAction = operatingPlan?.primaryAction,
           operatingPlan?.hasCanonicalActionSequence == true {
            hero.primaryActionTitle = primaryAction.title
        }

        let signals = [
            signal(
                id: "recovery",
                title: "恢复",
                metric: dashboard.recovery,
                fallbackSubtitle: "等待 HealthKit 恢复基线",
                accent: .recovery,
                trend: historicalTrend(
                    id: "recovery",
                    current: dashboard.recovery,
                    selectedDate: dashboard.date,
                    history: history
                )
            ),
            signal(
                id: "sleep",
                title: "睡眠",
                metric: dashboard.sleepScore,
                fallbackSubtitle: "等待睡眠时长与连续性",
                accent: .sleep,
                trend: historicalTrend(
                    id: "sleep",
                    current: dashboard.sleepScore,
                    selectedDate: dashboard.date,
                    history: history
                )
            ),
            signal(
                id: "strain",
                title: "负荷",
                metric: dashboard.strain,
                fallbackSubtitle: "等待训练负荷",
                accent: .strain,
                trend: historicalTrend(
                    id: "strain",
                    current: dashboard.strain,
                    selectedDate: dashboard.date,
                    history: history
                )
            ),
            signal(
                id: "stress",
                title: "压力",
                metric: dashboard.stress,
                fallbackSubtitle: "等待压力指标",
                accent: .stress,
                trend: historicalTrend(
                    id: "stress",
                    current: dashboard.stress,
                    selectedDate: dashboard.date,
                    history: history
                )
            ),
            signal(
                id: "energy",
                title: "能量",
                metric: dashboard.energy,
                fallbackSubtitle: "等待能量模型",
                accent: .energy,
                trend: historicalTrend(
                    id: "energy",
                    current: dashboard.energy,
                    selectedDate: dashboard.date,
                    history: history
                )
            )
        ]

        return TodayExperienceModel(
            generatedAt: generatedAt,
            hero: hero,
            signalCards: signals,
            baselineFormation: baselineFormation,
            evidenceChips: evidenceChips(
                dashboard: dashboard,
                bodyState: bodyState,
                decision: trainingDecision,
                hasReadinessData: hasReadinessData
            ),
            actions: canonicalActions(from: operatingPlan) ?? actionPlan(
                    dashboard: dashboard,
                    bodyState: bodyState,
                    decision: trainingDecision,
                    readiness: effectiveReadiness,
                    hasReadinessData: hasReadinessData
                ),
            nutrition: nutrition,
            coachPreview: coachPreview(
                dashboard: dashboard,
                bodyState: bodyState,
                decision: trainingDecision,
                hasReadinessData: hasReadinessData
            )
        )
    }

    /// Today is an Adapter over the persisted Daily Operating Plan. Legacy payloads
    /// intentionally fall back to the deterministic local projection until the next
    /// coordinator refresh migrates them to the current Daily Operating Plan schema.
    private static func canonicalActions(
        from operatingPlan: DailyOperatingPlanPayload?
    ) -> [TodayExperienceAction]? {
        guard let operatingPlan,
              operatingPlan.hasCanonicalActionSequence,
              let primary = operatingPlan.primaryAction else {
            return nil
        }
        let primaryProjection = TodayExperienceAction(
            id: primary.id,
            title: primary.title,
            detail: primary.detail,
            destination: primary.destination,
            isPrimary: true,
            evidence: primary.evidence
        )
        let supportProjections = operatingPlan.supportingActions.prefix(2).map { action in
            TodayExperienceAction(
                id: action.id,
                title: action.title,
                detail: action.detail,
                destination: action.destination,
                isPrimary: false,
                evidence: action.evidence
            )
        }
        return [primaryProjection] + supportProjections
    }

    private static func scoreTitle(_ dashboard: DashboardSummary) -> String {
        "恢复 \(dashboard.recovery.formattedScore)"
    }

    private static func decisionTitle(
        _ readiness: ReadinessDecisionKind,
        brief: PersonalHealthBrief?,
        hasReadinessData: Bool
    ) -> String {
        guard hasReadinessData else { return "正在同步身体数据" }
        if let brief = brief, !brief.headline.isEmpty {
            return brief.headline
        }
        switch readiness {
        case .keep: return "按计划训练"
        case .reduce: return "控制训练量"
        case .swap: return "换练调整"
        case .recover: return "恢复优先"
        }
    }

    private static func primaryActionTitle(
        _ readiness: ReadinessDecisionKind,
        brief: PersonalHealthBrief?,
        hasReadinessData: Bool
    ) -> String {
        guard hasReadinessData else { return "检查数据连接" }
        if let brief = brief, let actionHeadline = brief.actionHeadline, !actionHeadline.isEmpty {
            return "查看\(actionHeadline)"
        }
        switch readiness {
        case .keep: return "查看今日训练建议"
        case .reduce: return "查看负荷调节建议"
        case .swap: return "查看换练建议"
        case .recover: return "查看恢复建议"
        }
    }

    private static func readinessMapping(for decision: DailyTrainingDecision) -> ReadinessDecisionKind {
        switch decision.decision {
        case .keep: return .keep
        case .reduce: return .reduce
        case .swap: return .swap
        case .rest: return .recover
        }
    }

    private static func summary(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        brief: PersonalHealthBrief?,
        hasReadinessData: Bool
    ) -> String {
        guard hasReadinessData else {
            return "当前缺少恢复基线，Vela 会先按保守健康窗口处理，并优先引导同步数据。"
        }
        if let brief = brief, !brief.subheadline.isEmpty {
            return brief.subheadline
        }
        let sleep = dashboard.sleepScore.formattedScore
        let strain = dashboard.strain.formattedScore
        let limiter = bodyState.drivers.first.map(displayDriverTitle) ?? "未发现主要限制"
        return "\(displayDecisionSummary(decision)) 睡眠 \(sleep)，负荷 \(strain)，主要证据：\(limiter)。"
    }

    private static func signal(
        id: String,
        title: String,
        metric: MetricResult,
        fallbackSubtitle: String,
        accent: DailyPlanAccent,
        trend: [Double]
    ) -> TodayExperienceSignalCard {
        let value = metric.hasData ? "\(Int(metric.score.rounded()))" : "--"
        let subtitle = metric.hasData ? signalSubtitle(for: metric) : fallbackSubtitle
        return TodayExperienceSignalCard(
            id: id,
            title: title,
            value: value,
            directionLabel: directionLabel(for: metric.direction),
            confidenceLabel: confidenceLabel(for: metric),
            coverageLabel: coverageLabel(for: metric.dataCoverage),
            subtitle: subtitle,
            trend: trend,
            accent: accent,
            state: metric.state
        )
    }

    private static func historicalTrend(
        id: String,
        current: MetricResult,
        selectedDate: Date,
        history: [DailyHealthSummaryDTO],
        calendar: Calendar = .current
    ) -> [Double] {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let previousValues = history
            .filter { calendar.startOfDay(for: $0.date) < selectedDay }
            .sorted { $0.date < $1.date }
            .compactMap { record -> Double? in
                switch id {
                case "recovery": return record.recoveryScore
                case "sleep": return record.sleepScore
                case "strain": return record.strainScore
                case "stress": return record.stressIndex
                case "energy": return record.currentEnergy ?? record.morningEnergy ?? record.energyBank
                default: return nil
                }
            }

        var values = Array(previousValues.suffix(13))
        if current.hasData {
            values.append(current.score)
        }
        return values
    }

    private static func signalSubtitle(for metric: MetricResult) -> String {
        guard let value = metric.value else { return "等待可用数据" }
        switch metric.domain {
        case .recovery:
            if value < 45 { return "偏低，今天恢复优先" }
            if value < 75 { return "中等，训练时保留余力" }
            return "较好，支持计划训练"
        case .sleep:
            if value < 60 { return "偏低，今晚优先修复睡眠" }
            if value < 80 { return "尚可，继续保护睡眠节奏" }
            return "较好，保持当前睡眠节奏"
        case .strain:
            let target = metric.recommendedRange
            if value < Double(target.lowerBound) { return "低于建议负荷区间" }
            if value > Double(target.upperBound) { return "高于建议区间，停止加量" }
            return "位于建议负荷区间"
        case .physiologicalStress:
            if value >= 70 { return "偏高，安排低刺激恢复窗口" }
            if value >= 45 { return "中等，减少额外刺激" }
            return "处于可控区间"
        case .energy:
            if value < 35 { return "偏低，保留能量避免透支" }
            if value < 70 { return "适中，优先重要任务" }
            return "较高，支持主要计划"
        }
    }

    private static func directionLabel(for direction: ScoreDirection) -> String {
        switch direction {
        case .higherIsBetter: return "越高越好"
        case .higherIsLoad: return "越高负荷越大"
        case .higherNeedsAttention: return "越高越需关注"
        }
    }

    private static func confidenceLabel(for metric: MetricResult) -> String {
        guard metric.hasData else { return "数据不足" }
        switch metric.confidence {
        case .low: return "低置信度"
        case .medium: return "中置信度"
        case .high: return "高置信度"
        }
    }

    private static func coverageLabel(for coverage: ScoreDataCoverage) -> String {
        switch coverage {
        case .unavailable: return "暂无覆盖"
        case .partial: return "部分数据"
        case .substantial: return "主要数据"
        case .complete: return "完整数据"
        }
    }

    private static func evidenceChips(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        hasReadinessData: Bool
    ) -> [String] {
        guard hasReadinessData else {
            return ["等待 HealthKit", "保守训练窗口", "先建立个人基线"]
        }

        var chips = [decisionEvidenceChip(decision)]
        if let driver = bodyState.drivers.first {
            // 联通专项批次 1：证据锚点展示引擎理由正文（reasons.first），而非只有标题。
            chips.append(driver.detail.isEmpty ? displayDriverTitle(driver) : driver.detail)
        }
        if let hrvZ = dashboard.recovery.metrics["hrv_z_score"] {
            // 联通专项批次 1：HRV 证据改用个人基线 z-score（相对语义），不再只报 raw ms。
            chips.append(String(format: "HRV 基线 %+.1f SD", hrvZ))
        } else if let hrv = dashboard.recoveryMetrics.hrvMilliseconds {
            chips.append("HRV \(Int(hrv.rounded()))ms")
        }
        if dashboard.sleepScore.hasData {
            chips.append("睡眠 \(dashboard.sleepScore.formattedScore)")
        }
        return Array(chips.prefix(4))
    }

    private static func actionPlan(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        readiness: ReadinessDecisionKind,
        hasReadinessData: Bool
    ) -> [TodayExperienceAction] {
        guard hasReadinessData else {
            return [
                .init(id: "sync_health", title: "同步健康数据", detail: "更新 HRV、静息心率、睡眠和日常活动。", destination: "sync", isPrimary: true, evidence: "体征数据尚在同步"),
                .init(id: "log_status", title: "记录身体状态", detail: "补充疲劳、酸痛、压力或主观感受。", destination: "journal", isPrimary: false),
                .init(id: "ask_coach", title: "询问 Vela", detail: "用当前有限数据生成保守建议。", destination: "coach", isPrimary: false)
            ]
        }
        let evidence = actionEvidence(
            dashboard: dashboard,
            bodyState: bodyState,
            decision: decision
        )
        let volume = decision.volumeMultiplier
        let cap = decision.intensityCap

        if let brief = dashboard.personalHealthBrief {
            switch brief.overallState {
            case .optimal:
                return [
                    .init(id: "maintain_rhythm", title: "按计划开展活动", detail: "各项核心体征处于良好水平，支持正常开展日常工作与训练节奏。", destination: "training", isPrimary: true, evidence: evidence),
                    .init(id: "protect_sleep", title: "保持睡眠节律", detail: "保持固定作息时间，规律入睡。", destination: "journal", isPrimary: false),
                    .init(id: "ask_coach", title: "问 Vela 身体分析", detail: "了解近期体征规律与状态演进。", destination: "coach", isPrimary: false)
                ]
            case .stable:
                return [
                    .init(id: "review_training", title: "保持日常节奏", detail: "体征平稳运行在基线区间，可正常执行既定活动与训练计划。", destination: "training", isPrimary: true, evidence: evidence),
                    .init(id: "protect_sleep", title: "保护今晚睡眠", detail: "固定入睡时间，避免过晚进食。", destination: "journal", isPrimary: false),
                    .init(id: "ask_coach", title: "问 Vela 趋势洞察", detail: "查看近期体征对比与趋势细节。", destination: "coach", isPrimary: false)
                ]
            case .strained:
                return [
                    .init(id: "reduce_training", title: "适度控制负荷", detail: "在 Apple Watch 开始训练；容量 \(Int((volume * 100).rounded()))%，RPE 上限 \(cap)。", destination: "training", isPrimary: true, evidence: evidence),
                    .init(id: "recovery_block", title: "安排主动恢复", detail: "补充水分、安排轻度散步与放松。", destination: "recovery", isPrimary: false),
                    .init(id: "protect_sleep", title: "今晚提前睡眠", detail: "减少晚间刺激，优先保证睡眠时长。", destination: "journal", isPrimary: false)
                ]
            case .recovering:
                return [
                    .init(id: "recovery_day", title: "优先休整调节", detail: "体征处于恢复窗口，建议停止高强度刺激，安排充分休息。", destination: "recovery", isPrimary: true, evidence: evidence),
                    .init(id: "sleep_plan", title: "今晚提前入睡", detail: "把睡眠修复放在高强度活动之前。", destination: "journal", isPrimary: false),
                    .init(id: "ask_coach", title: "问 Vela 恢复建议", detail: "获取个性化放松与生活调整建议。", destination: "coach", isPrimary: false)
                ]
            case .insufficientData:
                break
            }
        }

        switch readiness {
        case .keep:
            return [
                .init(id: "review_training", title: "查看训练边界", detail: "在 Apple Watch 开始训练；今天正常执行计划，保留 1–2 次余力。", destination: "training", isPrimary: true, evidence: evidence),
                .init(id: "protect_sleep", title: "保护今晚睡眠", detail: "固定入睡时间，避免训练后过晚进食。", destination: "journal", isPrimary: false),
                .init(id: "ask_coach", title: "问 Vela 调整细节", detail: "根据动作、RPE 和肌群疲劳微调。", destination: "coach", isPrimary: false)
            ]
        case .reduce:
            return [
                .init(id: "reduce_training", title: "训练时控制容量", detail: "在 Apple Watch 开始训练；容量 \(Int((volume * 100).rounded()))%，RPE 上限 \(cap)。", destination: "training", isPrimary: true, evidence: evidence),
                .init(id: "check_in", title: "记录疲劳", detail: "把酸痛、精神状态和压力写入上下文。", destination: "journal", isPrimary: false),
                .init(id: "recovery_block", title: "安排恢复块", detail: "补水、低强度步行和提前睡眠。", destination: "recovery", isPrimary: false)
            ]
        case .swap:
            return [
                .init(id: "swap_session", title: "替换训练内容", detail: "避开高疲劳肌群，保留训练节奏，RPE 不超过 \(cap)。", destination: "training", isPrimary: true, evidence: evidence),
                .init(id: "mobility", title: "增加活动度", detail: "优先低冲击和技术练习。", destination: "recovery", isPrimary: false),
                .init(id: "ask_coach", title: "让 Vela 改计划", detail: "生成替代动作与组数。", destination: "coach", isPrimary: false)
            ]
        case .recover:
            return [
                .init(id: "recovery_day", title: "执行恢复日", detail: "停止高强度训练，只做能轻松交谈的低强度活动。", destination: "recovery", isPrimary: true, evidence: evidence),
                .init(id: "symptom_check", title: "记录异常信号", detail: "如果有不适，记录并考虑专业意见。", destination: "journal", isPrimary: false),
                .init(id: "sleep_plan", title: "今晚提前睡眠", detail: "把恢复放在训练之前。", destination: "journal", isPrimary: false)
            ]
        }
    }

    private static func actionEvidence(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        decision: DailyTrainingDecision
    ) -> String {
        var parts: [String] = []
        if dashboard.recovery.hasData {
            parts.append("恢复 \(dashboard.recovery.formattedScore)")
        }
        if dashboard.sleepScore.hasData {
            parts.append("睡眠 \(dashboard.sleepScore.formattedScore)")
        }
        if decision.decision == .rest || decision.decision == .reduce,
           dashboard.stress.hasData {
            parts.append("压力 \(dashboard.stress.formattedScore)")
        } else if dashboard.strain.hasData {
            parts.append("负荷 \(dashboard.strain.formattedScore)")
        }
        if let driver = bodyState.drivers.first {
            parts.append(displayDriverTitle(driver))
        }
        return Array(parts.prefix(3)).joined(separator: " · ")
    }

    private static func coachPreview(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        hasReadinessData: Bool
    ) -> String {
        guard hasReadinessData else {
            return "本机教练：当前判断依据有限；先同步 Apple 健康，同时采用保守建议。"
        }
        let freshness = label(for: bodyState.freshness)
        let recovery = Int(dashboard.recovery.score.rounded())
        return "本机教练：恢复 \(recovery)，\(displayDecisionSummary(decision)) \(label(for: bodyState.confidence))，数据新鲜度：\(freshness)。"
    }

    private static func displayDecisionSummary(_ decision: DailyTrainingDecision) -> String {
        switch decision.decision {
        case .keep:
            return "按计划训练，保留 1-2 次余力，并根据动作质量自我调节。"
        case .reduce:
            return "建议将训练容量调整到 \(Int((decision.volumeMultiplier * 100).rounded()))%，RPE 控制在 \(decision.intensityCap) 以内。"
        case .swap:
            return "建议替换高疲劳肌群的训练内容，保留训练节奏，RPE 控制在 \(decision.intensityCap) 以内。"
        case .rest:
            return "今天优先恢复或轻活动，避免追求训练量。"
        }
    }

    private static func decisionEvidenceChip(_ decision: DailyTrainingDecision) -> String {
        switch decision.decision {
        case .keep:
            return "按计划训练"
        case .reduce:
            return "训练容量 \(Int((decision.volumeMultiplier * 100).rounded()))%"
        case .swap:
            return "替换高疲劳肌群"
        case .rest:
            return "恢复优先"
        }
    }

    private static func displayDriverTitle(_ driver: BodyStateDriver) -> String {
        switch driver.kind {
        case .localFatigue:
            return "\(localizedMuscle(from: driver.title))局部疲劳"
        case .trainingResponse:
            return "近期训练后的恢复反应"
        case .dataCoverage:
            return "数据覆盖不足"
        case .recovery:
            return "恢复信号"
        case .sleep:
            return "睡眠信号"
        case .strain:
            return "近期训练负荷"
        case .stress:
            return "压力信号"
        case .energy:
            return "能量状态"
        case .activeStatus:
            return "当前生活状态"
        case .nutrition:
            return "今日营养记录"
        case .journal:
            return "近期主观记录"
        case .activePlan:
            return "当前训练计划"
        case .recentActivity:
            return "近期活动"
        }
    }

    private static func localizedMuscle(from title: String) -> String {
        let normalized = title.lowercased()
        if normalized.contains("chest") { return "胸部" }
        if normalized.contains("back") { return "背部" }
        if normalized.contains("quads") || normalized.contains("quadriceps") { return "股四头肌" }
        if normalized.contains("hamstrings") { return "腘绳肌" }
        if normalized.contains("glutes") { return "臀部" }
        if normalized.contains("shoulders") || normalized.contains("shoulder") { return "肩部" }
        if normalized.contains("biceps") { return "肱二头肌" }
        if normalized.contains("triceps") { return "肱三头肌" }
        if normalized.contains("core") { return "核心" }
        if normalized.contains("leg") { return "腿部" }
        return "相关肌群"
    }

    private static func label(for confidence: DataConfidence) -> String {
        switch confidence {
        case .high: return "判断依据充分"
        case .medium: return "判断依据部分"
        case .low: return "判断依据有限"
        case .unavailable: return "数据不足"
        }
    }

    private static func label(for freshness: DataFreshness) -> String {
        switch freshness {
        case .live: return "实时"
        case .today: return "今日"
        case .recent: return "近期"
        case .stale: return "过期"
        case .missing: return "缺失"
        }
    }
}

struct TrainingSurfaceSummaryModel: Codable, Hashable {
    var decision: DailyTrainingDecisionType
    var headline: String
    var guidance: String
    var targetRangeText: String
    var recoveryValue: String
    var sleepValue: String
    var strainValue: String
    var confidenceLabel: String
    var primaryActionTitle: String
    var sessionTitle: String?
    var intensityCapText: String
    var coachQuestion: String

    static func build(
        dashboard: DashboardSummary,
        todayExperience: TodayExperienceModel,
        trainingDecision: DailyTrainingDecision,
        operatingPlan: DailyOperatingPlanPayload?
    ) -> TrainingSurfaceSummaryModel {
        let decision = operatingPlan?.decision ?? trainingDecision.decision
        let range = dashboard.strain.recommendedRange
        let sessionTitle = operatingPlan?.targetSessionTitle ?? trainingDecision.targetSessionTitle
        let guidance = operatingPlan?.summary ?? todayExperience.hero.summary
        let intensityCap = operatingPlan?.intensityCap ?? trainingDecision.intensityCap

        return TrainingSurfaceSummaryModel(
            decision: decision,
            headline: headline(for: decision),
            guidance: guidance,
            targetRangeText: dashboard.strain.hasData ? "\(range.lowerBound)-\(range.upperBound)" : "--",
            recoveryValue: dashboard.recovery.formattedScore,
            sleepValue: dashboard.sleepScore.formattedScore,
            strainValue: dashboard.strain.formattedScore,
            confidenceLabel: dashboard.source == .empty ? "数据不足" : todayExperience.hero.confidenceLabel,
            primaryActionTitle: primaryActionTitle(for: decision),
            sessionTitle: sessionTitle,
            intensityCapText: "RPE <= \(intensityCap)",
            coachQuestion: coachQuestion(for: decision, sessionTitle: sessionTitle, guidance: guidance)
        )
    }

    private static func headline(for decision: DailyTrainingDecisionType) -> String {
        switch decision {
        case .keep: return "今日按计划训练"
        case .reduce: return "今日减量训练"
        case .swap: return "替换训练内容"
        case .rest: return "恢复优先"
        }
    }

    private static func primaryActionTitle(for decision: DailyTrainingDecisionType) -> String {
        switch decision {
        case .keep: return "开始今日训练"
        case .reduce: return "执行减量训练"
        case .swap: return "换成更合适训练"
        case .rest: return "安排恢复日"
        }
    }

    private static func coachQuestion(
        for decision: DailyTrainingDecisionType,
        sessionTitle: String?,
        guidance: String
    ) -> String {
        let session = sessionTitle.map { "目标训练：\($0)。" } ?? ""
        switch decision {
        case .keep:
            return "\(session)请基于当前数据确认今天训练的热身、主项和强度上限。"
        case .reduce:
            return "\(session)请把今天训练改成减量版本，并保留最重要的训练刺激。依据：\(guidance)"
        case .swap:
            return "\(session)请替换今天训练内容，避开高疲劳部位，同时保持训练连续性。依据：\(guidance)"
        case .rest:
            return "请为今天安排恢复日，包括低强度活动、拉伸和睡眠优先级。依据：\(guidance)"
        }
    }
}
