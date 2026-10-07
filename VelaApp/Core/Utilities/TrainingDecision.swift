import Foundation
import SwiftData

enum DailyTrainingDecisionType: String, Codable, Hashable, Sendable {
    case keep
    case reduce
    case swap
    case rest

    /// Short Plan headline. Completion progress is not this decision.
    var todayDecisionTitle: String {
        switch self {
        case .keep: return "保持"
        case .reduce: return "减量"
        case .swap: return "替换"
        case .rest: return "恢复"
        }
    }
}

struct DailyTrainingDecision: Codable, Hashable, Sendable {
    var decision: DailyTrainingDecisionType
    var targetSessionTitle: String?
    var volumeMultiplier: Double
    var intensityCap: Int
    var reasons: [String]
    var userFacingSummary: String
    var confidence: Double
    var source: String
    var safetyNotice: String
}

enum TrainingDecisionFallback {
    static func conservative(targetSessionTitle: String?) -> DailyTrainingDecision {
        DailyTrainingDecision(
            decision: .reduce,
            targetSessionTitle: targetSessionTitle,
            volumeMultiplier: 0.60,
            intensityCap: 7,
            reasons: ["数据状态：今日身体信号尚未完成同步，使用保守训练窗口。"],
            userFacingSummary: "今日数据尚未完成同步；先按约 60% 容量训练，RPE 不超过 7，并在动作质量下降时停止加量。",
            confidence: 0.25,
            source: "TrainingDecisionFallback",
            safetyNotice: "一般健康与训练建议，不构成医疗诊断。"
        )
    }
}

struct DecisionFeedbackCalibration: Codable, Hashable, Sendable {
    var completedFeedbackCount: Int
    var volumeAdjustmentMultiplier: Double // e.g. +0.05 or -0.05
    var note: String?

    init(
        completedFeedbackCount: Int = 0,
        volumeAdjustmentMultiplier: Double = 0.0,
        note: String? = nil
    ) {
        self.completedFeedbackCount = completedFeedbackCount
        self.volumeAdjustmentMultiplier = volumeAdjustmentMultiplier
        self.note = note
    }
}

struct TrainingDecisionInput {
    var bodyState: BodyState
    var activePlan: TrainingPlanDTO?
    var trainingResponses: [TrainingResponseDTO]
    var userConstraints: [String]
    /// 已落库的训练事件：用于解析「今天实际应执行的计划日」。
    /// 与训练页 `TrainingScheduleResolver` 同源，避免遗漏已完成/逾期日。
    var workoutEvents: [WorkoutEventDTO]
    /// 长期训练量长线统计（Layer 2：本月训练量三年百分位信号；nil = 不启用）。
    var longTermTrainingVolume: TrainingVolumeLongTerm?
    /// 用户反馈闭环校准（Layer 3：结合近期 14 天决策反馈微调容量偏置）。
    var feedbackCalibration: DecisionFeedbackCalibration?
    /// The next focus in the user's lightweight rotation when no multi-week plan
    /// is active. This lets Apple Watch remain the execution surface.
    var rotationFocus: String?
    /// 唯一事实源身体简报（Layer 1：作为上游身体状态基准输入）。
    var personalHealthBrief: PersonalHealthBrief?
    /// Calendar is explicit so schedule resolution is deterministic for a selected day.
    var calendar: Calendar

    init(
        bodyState: BodyState,
        activePlan: TrainingPlanDTO? = nil,
        trainingResponses: [TrainingResponseDTO] = [],
        userConstraints: [String] = [],
        workoutEvents: [WorkoutEventDTO] = [],
        longTermTrainingVolume: TrainingVolumeLongTerm? = nil,
        feedbackCalibration: DecisionFeedbackCalibration? = nil,
        rotationFocus: String? = nil,
        personalHealthBrief: PersonalHealthBrief? = nil,
        calendar: Calendar = .current
    ) {
        self.bodyState = bodyState
        self.activePlan = activePlan
        self.trainingResponses = trainingResponses
        self.userConstraints = userConstraints
        self.workoutEvents = workoutEvents
        self.longTermTrainingVolume = longTermTrainingVolume
        self.feedbackCalibration = feedbackCalibration
        self.rotationFocus = rotationFocus
        self.personalHealthBrief = personalHealthBrief
        self.calendar = calendar
    }
}

enum TrainingRotationResolver {
    static let defaultFocuses = ["back", "chest", "shoulders", "legs", "accessories"]

    static func focuses(for profile: TrainingPreferenceProfile?) -> [String] {
        let configured = profile?.rotationFocuses?
            .map(normalize)
            .filter { defaultFocuses.contains($0) } ?? []
        return configured.isEmpty ? defaultFocuses : Array(configured.uniqued())
    }

    static func nextFocus(
        profile: TrainingPreferenceProfile?,
        recentResponses: [TrainingResponseDTO]
    ) -> String {
        let order = focuses(for: profile)
        if let explicit = profile?.nextRotationFocus.map(normalize), order.contains(explicit) {
            return explicit
        }
        // An optional check-in with no selected focus is not evidence that the
        // rotation restarted. Keep looking for the latest meaningful focus tag.
        guard let latest = recentResponses
            .filter({ !$0.primaryMuscleGroups.isEmpty })
            .max(by: { $0.date < $1.date }) else {
            return order[0]
        }
        return focus(after: latest.primaryMuscleGroups, order: order)
    }

    static func focus(
        after completedGroups: [String],
        profile: TrainingPreferenceProfile?
    ) -> String {
        focus(after: completedGroups, order: focuses(for: profile))
    }

    static func focus(after completedGroups: [String], order: [String]) -> String {
        let normalized = Set(completedGroups.map(normalize))
        guard let index = order.firstIndex(where: normalized.contains) else {
            return order[0]
        }
        return order[(index + 1) % order.count]
    }

    static func title(for focus: String) -> String {
        switch normalize(focus) {
        case "back": return "背部"
        case "chest": return "胸部"
        case "shoulders": return "肩部"
        case "legs": return "腿部"
        case "accessories": return "手臂与核心"
        default: return "自由训练"
        }
    }

    static func muscleKeys(for focus: String) -> Set<String> {
        switch normalize(focus) {
        case "back": return ["back"]
        case "chest": return ["chest"]
        case "shoulders": return ["shoulders"]
        case "legs": return ["legs", "quads", "hamstrings", "glutes"]
        case "accessories": return ["accessories", "arms", "biceps", "triceps", "core", "abs"]
        default: return []
        }
    }

    static func normalize(_ raw: String) -> String {
        let value = raw.lowercased()
        if ["back", "pull", "背"].contains(where: value.contains) { return "back" }
        if ["chest", "push", "胸"].contains(where: value.contains) { return "chest" }
        if ["shoulder", "deltoid", "肩"].contains(where: value.contains) { return "shoulders" }
        if ["leg", "quad", "hamstring", "glute", "腿"].contains(where: value.contains) { return "legs" }
        if ["accessories", "arm", "biceps", "triceps", "core", "abs", "手臂", "腹", "核心"].contains(where: value.contains) { return "accessories" }
        return value
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct TrainingDecisionKernel: Sendable {
    func decide(input: TrainingDecisionInput) -> DailyTrainingDecision {
        let state = input.bodyState
        let activePlan = input.activePlan
        
        // 1. Resolve today's scheduled TrainingDay with the same resolver used by
        // the Training page. A simplistic weekday lookup missed completed days
        // linked through WorkoutEventRecord and overdue-day carry-over.
        let calendar = input.calendar
        let todayScheduledDay: TrainingDay?
        if let activePlan {
            todayScheduledDay = TrainingScheduleResolver.resolve(
                plan: activePlan,
                on: state.date,
                events: input.workoutEvents,
                calendar: calendar
            )
        } else {
            todayScheduledDay = nil
        }
        
        // 2. Identify target muscle groups from planned exercises
        var targetMuscles = Set<String>()
        if let todayScheduledDay {
            if let data = todayScheduledDay.plannedExercisesJSON.data(using: .utf8),
               let planned = try? JSONDecoder().decode([WorkoutTemplateExercise].self, from: data) {
                let library = ExerciseLibraryService.defaultDefinitionsDTO()
                for item in planned {
                    let definition = library.first { def in
                        if let key = item.exerciseCanonicalKey {
                            return def.canonicalKey == key
                        }
                        return def.name.caseInsensitiveCompare(item.name) == .orderedSame
                    }
                    if let definition {
                        targetMuscles.insert(definition.primaryMuscleGroup.lowercased())
                        for m in definition.secondaryMuscleGroups {
                            targetMuscles.insert(m.lowercased())
                        }
                    }
                }
            }
        } else if let rotationFocus = input.rotationFocus {
            targetMuscles.formUnion(TrainingRotationResolver.muscleKeys(for: rotationFocus))
        }
        
        // 3. Compare target muscles with local fatigue
        var highFatigueTargetMuscles: [String] = []
        for muscle in targetMuscles {
            if let fatigue = state.localFatigue[muscle], fatigue.fatigueLevel == "high" {
                highFatigueTargetMuscles.append(muscle)
            }
        }
        
        // 4. Use TrainingResponseRecord history by muscle group (last 28 days)
        var poorResponseTargetMuscles: [String] = []
        var severeResponseCrash = false
        let cutoffDate = state.date.addingTimeInterval(-28 * 86_400)
        let recentResponses = input.trainingResponses.filter {
            $0.date >= cutoffDate && $0.date <= state.date
        }
        for response in recentResponses {
            let responseMuscles = response.primaryMuscleGroups.map { $0.lowercased() }
            let intersects = responseMuscles.contains { targetMuscles.contains($0) }
            if intersects {
                let isPoor = Self.isPoorTrainingResponse(response)
                if isPoor {
                    for m in responseMuscles {
                        if targetMuscles.contains(m) {
                            poorResponseTargetMuscles.append(m)
                        }
                    }
                    if (response.nextDayRecoveryDelta ?? 0) <= -15 {
                        severeResponseCrash = true
                    }
                }
            }
        }
        
        // 5. Decision logic tree
        // 算法安全重构（Safety Guardrails First）：绝对禁忌与极端身体状况（生病/计划内休息/极低睡眠/急性高压）
        // 必须置顶于数据缺失检查之前，杜绝因恢复数据未同步而将严重睡眠不足漏放至 reduce 训练。
        let thresholds = PersonalBaselineEngine.resolveThresholds()
        let stressIndex = state.stress.stressIndex
        let energyLevel = state.energy.currentEnergy
        let tsb = state.energy.metrics["tsb"]
        let strainUpper = state.strain.recommendedRange.upperBound
        var type: DailyTrainingDecisionType = .keep
        var multiplier = 1.0
        var cap = 9
        var summary = ""
        var reasons: [String] = []
        
        if ["sick", "injured", "resting"].contains(state.activeStatus) {
            // 用户显式标记的身体状态是硬约束，先于一切数据判定。
            type = .rest
            multiplier = 0.0
            cap = 2
            summary = "状态受限，今天优先恢复与休息。"
            reasons.append("活动状态: 标记为\(Self.localizedActiveStatus(state.activeStatus))，今天自动降低训练冒险度。")
        } else {
            // 0. 未同步 / 纯空数据场景安全防御：不给出虚假的确定性训练建议
            let isUnsyncedData = state.confidence == .unavailable || input.personalHealthBrief?.overallState == .insufficientData || (!state.recovery.hasData && !state.sleep.hasData && !state.strain.hasData)
            if isUnsyncedData {
                let sessionTitle = todayScheduledDay?.title
                    ?? activePlan?.title
                    ?? input.rotationFocus.map(TrainingRotationResolver.title)
                    ?? "自由训练"
                // 契约修复（P0-A）：未同步数据不得包装成「正常训练」（keep@100%）。
                // 数据不可用 → 训练边界必须落在保守窗口（与 TrainingDecisionFallback、
                // TodayCommandState 及「保守健康窗口」文案一致）；confidence 为 0 表示
                // 这不是对身体的判断，只是可执行的保守默认。
                return DailyTrainingDecision(
                    decision: .reduce,
                    targetSessionTitle: sessionTitle,
                    volumeMultiplier: 0.60,
                    intensityCap: 7,
                    reasons: ["体征数据尚在同步；今日按保守健康窗口执行，不评估身体就绪度。"],
                    userFacingSummary: "今日数据尚未完成同步；如需训练，按约 60% 容量、RPE 不超过 7 执行。",
                    confidence: 0.0,
                    source: "TrainingDecisionKernel",
                    safetyNotice: "一般健康与训练建议，不构成医疗诊断。"
                )
            }

            if todayScheduledDay?.focus.lowercased() == "rest" {
                type = .rest
                multiplier = 0.0
                cap = 2
                summary = "今天是计划内的休息日，建议做好恢复工作。"
                reasons.append("日程安排: 计划内休息。")
            } else if state.sleep.hasData, state.sleep.score < thresholds.sleepRest {
                type = .rest
                multiplier = 0.0
                cap = 2
                summary = "睡眠明显不足，今天优先恢复与补觉，避免高强度训练。"
                reasons.append("睡眠不足: 睡眠分数 \(Int(state.sleep.score.rounded())) 低于休息阈值 \(Int(thresholds.sleepRest.rounded()))。")
        } else if state.stress.hasData, stressIndex > 75 {
            type = .rest
            multiplier = 0.0
            cap = 2
            summary = "生理压力偏高，今天优先减压与恢复，避免叠加训练负荷。"
            reasons.append("压力偏高: 压力指数 \(Int(stressIndex.rounded()))（>75），先降压力再考虑负荷。")
        } else if state.recovery.hasData, state.readiness == .recovering {
            type = .rest
            multiplier = 0.0
            cap = 2
            summary = "状态受限，今天优先恢复与休息。"
            reasons.append("生理状态: 恢复分数低于休息阈值，处于恢复期。")
        } else if input.personalHealthBrief?.overallState == .recovering {
            type = .rest
            multiplier = 0.0
            cap = 2
            summary = "身体处于恢复调节窗口，今天优先安排休整。"
            reasons.append("身体简报: 综合生理状态处于恢复调节窗口。")
        } else if input.personalHealthBrief?.overallState == .strained {
            type = .reduce
            multiplier = 0.65
            cap = 7
            summary = "近期生理负荷有所累积，建议适当控制训练强度。"
            reasons.append("身体简报: 综合生理负荷偏高，建议控制训练量。")
        } else if !state.recovery.hasData {
            type = .reduce
            multiplier = 0.60
            cap = 7
            summary = "恢复基线数据不足，先按保守方案执行。"
            reasons.append("数据状态: 恢复基线数据不足，按保守方案执行。")
        } else if !highFatigueTargetMuscles.isEmpty {
            type = .swap
            multiplier = 0.65
            cap = 7
            summary = "避开高疲劳肌群 \(Self.localizedMuscleGroups(highFatigueTargetMuscles))，改做低风险替代训练。"
            reasons.append("局部疲劳: 目标肌群处于高疲劳状态。")
        } else if targetMuscles.isEmpty,
                  let worstFatigue = state.localFatigue.values
                      .filter({ $0.fatigueLevel == "high" })
                      .sorted(by: { $0.setsLast48h > $1.setsLast48h })
                      .first {
            // 无计划日：任一肌群高疲劳即建议换部位（与今日页此前的「任一高疲劳 → 换练」语义对齐）。
            type = .swap
            multiplier = 0.65
            cap = 7
            summary = "\(Self.localizedMuscleGroup(worstFatigue.muscleGroup))局部疲劳偏高，建议换练其他部位。"
            reasons.append("局部疲劳: \(Self.localizedMuscleGroup(worstFatigue.muscleGroup))处于高疲劳状态（48 小时 \(worstFatigue.setsLast48h) 组）。")
        } else if severeResponseCrash {
            type = .swap
            multiplier = 0.65
            cap = 7
            summary = "近期同部位训练出现严重生理响应崩溃，建议今天替换训练肌群。"
            reasons.append("训练响应: 该肌群近期训练后次日恢复严重暴跌。")
        } else if !poorResponseTargetMuscles.isEmpty {
            type = .reduce
            multiplier = 0.70
            cap = 7
            summary = "近期对 \(Self.localizedMuscleGroups(poorResponseTargetMuscles)) 训练的恢复响应欠佳，建议减量训练。"
            reasons.append("训练响应: 该肌群近期训练后次日恢复有下降趋势。")
        } else if recentResponses.contains(where: { Self.isPoorTrainingResponse($0) }) {
            // 即使没有计划目标肌群，近期训练后恢复反应明显变差也必须减量，
            // 不能让 readiness 阈值或静态缓存污染把它漏放为 keep。
            type = .reduce
            multiplier = 0.70
            cap = 7
            summary = "近期训练后的恢复响应欠佳，建议今天减量训练。"
            reasons.append("训练响应: 近期训练后次日恢复指标出现明显下降，先降低训练容量。")
        } else if state.energy.hasData, energyLevel < 30 {
            type = .reduce
            multiplier = 0.70
            cap = 7
            summary = "身体储备偏低，建议减量训练，并保证正常进食与睡眠。"
            reasons.append("能量储备: 当前能量 \(Int(energyLevel.rounded()))/100 偏低，不宜硬扛。")
        } else if let tsb, tsb <= -15 {
            type = .reduce
            multiplier = 0.70
            cap = 7
            summary = "累积训练负荷偏高，建议今天降低容量。"
            reasons.append("训练压力平衡: TSB \(String(format: "%+.0f", tsb)) 深度为负（≤-15），累积负荷偏高。")
        } else if state.readiness == .caution {
            type = .reduce
            multiplier = 0.75
            cap = 7
            summary = "身体评分偏低，建议减量训练至 75% 容量，限制负荷上限。"
            reasons.append("生理评级: 恢复或睡眠分数偏低。")
        } else if state.strain.hasData, state.strain.score > Double(strainUpper) {
            type = .reduce
            multiplier = 0.75
            cap = 7
            summary = "当日负荷已高于目标区间，建议减量。"
            reasons.append("当日负荷: 负荷 \(Int(state.strain.score.rounded())) 已超过今日目标上限 \(strainUpper)。")
        } else if state.readiness == .unknown {
            type = .reduce
            multiplier = 0.60
            cap = 7
            summary = "当前生理数据覆盖度不足，进行保守减量推荐以规避风险。"
            reasons.append("数据状态: 生理可信度过低。")
        } else {
            type = .keep
            multiplier = 1.0
            cap = 9
            summary = "可以按计划训练，但建议保留 1-2 次余力，并根据动作质量自我调节。"
            reasons.append("生理评级: 身体信号优良，支持正常训练。")
        }
        }
        
        // Layer 2：本月训练量处于三年月分布 P85 以上时，长期视角建议减量。
        if type == .keep,
           let volume = input.longTermTrainingVolume,
           let percentile = volume.currentMonthPercentile,
           percentile >= 85 {
            type = .reduce
            multiplier = 0.85
            cap = 8
            summary = "本月训练量处于三年月分布 P\(Int(percentile.rounded()))，长期视角偏高，建议适当减量。"
            reasons.append("长线训练量: 本月 \(Int(volume.currentMonthMinutes.rounded())) 分钟处于三年月分布 P\(Int(percentile.rounded()))。")
        }

        // C3：按个人训练响应的平均恢复变化全局校准容量系数
        //（rest/swap 的决策语义已固定，不参与校准）。
        if type == .keep || type == .reduce {
            let recoveryDeltas = recentResponses.compactMap(\.nextDayRecoveryDelta)
            let calibrated = TrainingResponseCalibrator.calibratedVolumeMultiplier(
                base: multiplier,
                recoveryDeltas: recoveryDeltas
            )
            if abs(calibrated - multiplier) > 0.005 {
                reasons.append("已按你近期的训练后恢复变化校准容量。")
                multiplier = calibrated
            }
        }

        // Layer 3：用户决策反馈闭环微调（当近期 14 天反馈形成明确偏置时）
        if (type == .keep || type == .reduce),
           let feedback = input.feedbackCalibration,
           feedback.completedFeedbackCount >= 3,
           abs(feedback.volumeAdjustmentMultiplier) >= 0.02 {
            let adjusted = max(0.50, min(1.0, multiplier + feedback.volumeAdjustmentMultiplier))
            if abs(adjusted - multiplier) > 0.005 {
                multiplier = adjusted
                if let note = feedback.note {
                    reasons.append("反馈校准: \(note)")
                } else {
                    reasons.append("反馈校准: 结合近期 \(feedback.completedFeedbackCount) 次决策反馈微调容量。")
                }
            }
        }

        // Inject user constraints
        for constraint in input.userConstraints {
            if constraint.localizedCaseInsensitiveContains("injury") || constraint.localizedCaseInsensitiveContains("hurt") || constraint.localizedCaseInsensitiveContains("pain") {
                type = .rest
                multiplier = 0.0
                cap = 2
                summary = "受用户限制条件约束，今天建议完全休息。"
                reasons.append("用户约束: 限制条件包含伤病或疼痛。")
            }
        }
        
        let confidence: Double = switch state.confidence {
        case .high: 0.9
        case .medium: 0.75
        case .low: 0.5
        case .unavailable: 0.3
        }
        
        let finalTitle = todayScheduledDay?.title
            ?? activePlan?.title
            ?? input.rotationFocus.map(TrainingRotationResolver.title)
            ?? "自由训练"
        
        return DailyTrainingDecision(
            decision: type,
            targetSessionTitle: finalTitle,
            volumeMultiplier: multiplier,
            intensityCap: cap,
            reasons: reasons,
            userFacingSummary: summary,
            confidence: confidence,
            source: "BodyStateKernel + TrainingDecisionKernel v3",
            safetyNotice: "仅提供一般健康与训练建议，不构成医疗诊断；如出现异常症状，请停止训练并寻求专业帮助。"
        )
    }
    

    private static func isPoorTrainingResponse(_ response: TrainingResponseDTO) -> Bool {
        (response.nextDayRecoveryDelta ?? 0) <= -8
            || (response.nextDayHRVDelta ?? 0) <= -10
            || (response.nextDayRHRDelta ?? 0) >= 5
    }
    private static func localizedActiveStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "sick": return "生病"
        case "injured": return "受伤"
        case "resting": return "休息中"
        default: return "活跃"
        }
    }

    private static func localizedMuscleGroups(_ groups: [String]) -> String {
        let localized = groups.map(localizedMuscleGroup).filter { !$0.isEmpty }
        guard !localized.isEmpty else { return "相关肌群" }
        return localized.joined(separator: "、")
    }

    private static func localizedMuscleGroup(_ group: String) -> String {
        switch group.lowercased() {
        case "chest": return "胸部"
        case "back": return "背部"
        case "shoulders": return "肩部"
        case "biceps": return "肱二头肌"
        case "triceps": return "肱三头肌"
        case "quads", "quadriceps": return "股四头肌"
        case "hamstrings": return "腘绳肌"
        case "glutes": return "臀部"
        case "core", "abs": return "核心"
        case "legs": return "腿部"
        default: return group
        }
    }
}
