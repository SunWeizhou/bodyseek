import Foundation
import SwiftUI

enum BehaviorTag: String, Codable, Hashable, CaseIterable {
    case alcohol
    case caffeine
    case lateMeal
    case highFat
    case highSalt
    case highSugar
    case overeating
    case lowHydration
    case spicy
    case lowProtein

    var displayTitle: String {
        switch self {
        case .alcohol: return "饮酒"
        case .caffeine: return "咖啡因"
        case .lateMeal: return "晚餐过晚"
        case .highFat: return "高油"
        case .highSalt: return "高盐"
        case .highSugar: return "高糖"
        case .overeating: return "吃撑"
        case .lowHydration: return "补水不足"
        case .spicy: return "辛辣"
        case .lowProtein: return "蛋白不足"
        }
    }
}

enum BehaviorIntensity: String, Codable, Hashable, CaseIterable {
    case low
    case medium
    case high
}

enum BehaviorTiming: String, Codable, Hashable, CaseIterable {
    case morning
    case midday
    case evening
    case preSleep
    case unknown
}

enum BehaviorSignalConfidence: String, Codable, Hashable, CaseIterable {
    case userConfirmed
    case aiInferred
    case photoAssisted
}

struct BehaviorSignal: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var tag: BehaviorTag
    var intensity: BehaviorIntensity
    var timing: BehaviorTiming
    var confidence: BehaviorSignalConfidence
    var sourceNote: String
    var createdAt: Date
}

enum BehaviorSignalExtractor {
    static func extract(
        from text: String,
        createdAt: Date = Date(),
        confidence: BehaviorSignalConfidence = .aiInferred
    ) -> [BehaviorSignal] {
        let lowered = text.lowercased()
        var signals: [BehaviorTag: BehaviorSignal] = [:]

        func timing(default fallback: BehaviorTiming = .unknown) -> BehaviorTiming {
            if lowered.contains("睡前") || lowered.contains("临睡") || lowered.contains("before bed") { return .preSleep }
            if lowered.contains("早上") || lowered.contains("早餐") || lowered.contains("morning") { return .morning }
            if lowered.contains("中午") || lowered.contains("午餐") || lowered.contains("lunch") { return .midday }
            if lowered.contains("晚上") || lowered.contains("晚餐") || lowered.contains("夜宵") || lowered.contains("dinner") { return .evening }
            return fallback
        }

        func intensity(for tag: BehaviorTag) -> BehaviorIntensity {
            if tag == .overeating, lowered.contains("吃撑") || lowered.contains("撑") {
                return .high
            }
            if lowered.contains("两杯") || lowered.contains("2杯") || lowered.contains("中等") || lowered.contains("medium") {
                return .medium
            }
            if lowered.contains("一点") || lowered.contains("少量") || lowered.contains("一杯") || lowered.contains("1杯") {
                return .low
            }
            if lowered.contains("很多") || lowered.contains("大量") || lowered.contains("high") {
                return .high
            }
            switch tag {
            case .overeating: return .high
            case .alcohol: return .medium
            default: return .medium
            }
        }

        func add(_ tag: BehaviorTag, timing explicitTiming: BehaviorTiming? = nil) {
            signals[tag] = BehaviorSignal(
                id: "\(Int(createdAt.timeIntervalSince1970))-\(tag.rawValue)",
                tag: tag,
                intensity: intensity(for: tag),
                timing: explicitTiming ?? timing(default: .unknown),
                confidence: confidence,
                sourceNote: text,
                createdAt: createdAt
            )
        }

        func addLegacy(_ tag: BehaviorTag, timing explicitTiming: BehaviorTiming? = nil) {
            signals[tag] = BehaviorSignal(
                id: "\(Int(createdAt.timeIntervalSince1970))-\(tag.rawValue)",
                tag: tag,
                intensity: intensity(for: tag),
                timing: explicitTiming ?? timing(default: .unknown),
                confidence: confidence,
                sourceNote: text,
                createdAt: createdAt
            )
        }

        if lowered.contains("酒") || lowered.contains("啤酒") || lowered.contains("红酒") || lowered.contains("白酒") || lowered.contains("alcohol") || lowered.contains("beer") {
            addLegacy(.alcohol)
        }
        if lowered.contains("咖啡") || lowered.contains("拿铁") || lowered.contains("美式") || lowered.contains("caffeine") || lowered.contains("coffee") {
            addLegacy(.caffeine, timing: lowered.contains("睡前") ? .preSleep : nil)
        }
        if lowered.contains("夜宵") || lowered.contains("很晚") || lowered.contains("晚吃") || lowered.contains("late meal") {
            addLegacy(.lateMeal)
        }
        if lowered.contains("火锅") || lowered.contains("油炸") || lowered.contains("炸鸡") || lowered.contains("烧烤") || lowered.contains("高油") || lowered.contains("high fat") {
            addLegacy(.highFat)
        }
        if lowered.contains("火锅") || lowered.contains("烧烤") || lowered.contains("外卖") || lowered.contains("咸") || lowered.contains("高盐") || lowered.contains("high salt") {
            addLegacy(.highSalt)
        }
        if lowered.contains("甜") || lowered.contains("奶茶") || lowered.contains("蛋糕") || lowered.contains("高糖") || lowered.contains("sugar") {
            addLegacy(.highSugar)
        }
        if lowered.contains("吃撑") || lowered.contains("撑了") || lowered.contains("过饱") || lowered.contains("overeating") {
            addLegacy(.overeating)
        }
        if lowered.contains("没喝水") || lowered.contains("喝水少") || lowered.contains("缺水") || lowered.contains("low hydration") {
            addLegacy(.lowHydration)
        }
        if lowered.contains("辣") || lowered.contains("辛辣") || lowered.contains("spicy") {
            addLegacy(.spicy)
        }
        if lowered.contains("蛋白不足") || lowered.contains("没吃蛋白") || lowered.contains("low protein") {
            addLegacy(.lowProtein)
        }
        return signals.values.sorted { $0.tag.rawValue < $1.tag.rawValue }
    }

    static func extract(from entry: JournalEntryRecord) -> [BehaviorSignal] {
        extract(from: entry.dto)
    }
    private static func intensity(from tags: [String]) -> BehaviorIntensity {
        if tags.contains("intensity:high") { return .high }
        if tags.contains("intensity:low") { return .low }
        return .medium
    }
}

enum BodyModelMaturityLevel: String, Codable, Hashable, CaseIterable, Sendable {
    case seed
    case learning
    case stable
}

struct BodyModelMaturity: Codable, Hashable, Sendable {
    var overall: BodyModelMaturityLevel
    var baselineDays: Int
    var behaviorPairs: Int
    var trainingSessions: Int
}

struct BodyModelClaim: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String
    var confidence: DataConfidence
    var evidenceCount: Int
}

struct BodyModelUncertainArea: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
}

struct BodyModelState: Codable, Hashable, Sendable {
    var generatedAt: Date
    var maturity: BodyModelMaturity
    var claims: [BodyModelClaim]
    var uncertainAreas: [BodyModelUncertainArea]
    var behaviorSignals: [BehaviorSignal]
    var trainingPatternSummary: String
    var coachRules: [String]
}

extension BodyModelState {
    /// 联通专项批次 2：主流程一句话洞察（产品方向「只在影响当前计划时显示一句
    /// Personal Response Insight」）。按价值优先级取最强断言；点击进证据页。
    func insightLine() -> String? {
        let preferredIDs = [
            "dose_response_curve",
            "training_outcome_pairing",
            "long_term_baseline"
        ]
        for id in preferredIDs {
            if let claim = claims.first(where: { $0.id == id }) {
                return claim.summary
            }
        }
        return nil
    }
}

/// 值类型版手记信号抽取（审计 H2：供离线组装，不跨并发域传 Live Object）。
extension BehaviorSignalExtractor {
    /// 提取手记行为信号（值类型版，与 @Model 版同源逻辑）。
    static func extract(from entry: JournalEntryDTO) -> [BehaviorSignal] {
        var signals = extract(from: entry.note, createdAt: entry.createdAt)
        for tag in entry.tags {
            guard tag.hasPrefix("behavior:"),
                  let behavior = BehaviorTag(rawValue: String(tag.dropFirst("behavior:".count))) else {
                continue
            }
            if !signals.contains(where: { $0.tag == behavior }) {
                signals.append(BehaviorSignal(
                    id: "\(Int(entry.createdAt.timeIntervalSince1970))-\(behavior.rawValue)",
                    tag: behavior,
                    intensity: intensity(from: entry.tags),
                    timing: .unknown,
                    confidence: .userConfirmed,
                    sourceNote: entry.note,
                    createdAt: entry.createdAt
                ))
            }
        }
        return signals.sorted { $0.tag.rawValue < $1.tag.rawValue }
    }
}

// MARK: - Body Model Value Inputs（审计 H2）

/// Onboarding 的值类型种子：允许离线组装时携带档案事实，不携带 Live Object。
struct OnboardingProfileSeed: Sendable, Equatable {
    var primaryGoal: String
    var experienceLevel: String
    var trainingStyle: String
    var weeklyTrainingDays: Int
    var sessionDurationMinutes: Int
    var coachingStyle: String
    var isCompleted: Bool
}

extension OnboardingState {
    var profileSeed: OnboardingProfileSeed {
        OnboardingProfileSeed(
            primaryGoal: goalProfile.primaryGoal,
            experienceLevel: goalProfile.experienceLevel,
            trainingStyle: trainingPreference.trainingStyle,
            weeklyTrainingDays: trainingPreference.weeklyTrainingDays,
            sessionDurationMinutes: trainingPreference.sessionDurationMinutes,
            coachingStyle: coachingPreference.style,
            isCompleted: isCompleted
        )
    }
}

/// 每日摘要的证据快照（BodyModelBuilder 实际消费的字段子集）。
struct BodyModelDailyEvidence: Sendable, Equatable {
    var date: Date
    var workoutCount: Int?
    var workoutDuration: Double?
    var hrvAverage: Double?
    var restingHeartRate: Double?
}

extension DailyHealthSummaryRecord {
    var bodyModelEvidence: BodyModelDailyEvidence {
        BodyModelDailyEvidence(
            date: date,
            workoutCount: workoutCount,
            workoutDuration: workoutDuration,
            hrvAverage: hrvAverage,
            restingHeartRate: restingHeartRate
        )
    }
}

/// BodyModelBuilder 的完整值类型输入：在 MainActor 上完成 @Model→值转换后，
/// 可在 Task.detached 中安全组装（所有成员 Sendable）。
struct BodyModelEvidence: Sendable {
    var onboardingSeed: OnboardingProfileSeed?
    var dailySummaries: [BodyModelDailyEvidence]
    var journalEntries: [JournalEntryDTO]
    var strengthWorkouts: [StrengthWorkoutDTO]
    var trainingResponses: [TrainingResponseDTO]
    var longTermBaselines: LongTermBaselineReport?
    var asOf: Date
    var calendar: Calendar
}


struct BodyModelBuilder {
    static func profileSeedSummary(primaryGoal: String, trainingStyle: String, weeklyTrainingDays: Int) -> String {
        let goal = localizedOnboardingGoal(primaryGoal)
        let style = localizedOnboardingTrainingStyle(trainingStyle)
        return L10n.t(
            "Goal \(goal), training style \(style), \(weeklyTrainingDays) times per week.",
            "目标 \(goal)，训练风格 \(style)，每周 \(weeklyTrainingDays) 次。"
        )
    }

    /// 值类型入口（审计 H2）：只依赖 Sendable 证据，可在 Task.detached 中运行。
    func build(evidence: BodyModelEvidence) -> BodyModelState {
        // 历史日/缓存路径的 asOf 语义：模型只能使用 asOf 当天及之前的事实，
        // 不能让未来日期的训练/手记/摘要反向抬高成熟度或改变训练事实计数。
        let asOfDay = evidence.calendar.startOfDay(for: evidence.asOf)
        let dailySummaries = evidence.dailySummaries.filter {
            evidence.calendar.startOfDay(for: $0.date) <= asOfDay
        }
        let journalEntries = evidence.journalEntries.filter { $0.createdAt <= evidence.asOf }
        let strengthWorkouts = evidence.strengthWorkouts.filter { $0.startedAt <= evidence.asOf }
        let trainingResponses = evidence.trainingResponses.filter { $0.date <= evidence.asOf }

        let recentBaselineDays = Set(dailySummaries.map { evidence.calendar.startOfDay(for: $0.date) }).count
        let longTermDays = evidence.longTermBaselines?.daysOfData ?? 0
        // 三年回填后基线天数以全历史为准：基线「仍在建立」从此不再由窗口截断造成。
        let baselineDays = max(recentBaselineDays, longTermDays)
        let behaviorSignals = journalEntries.flatMap { BehaviorSignalExtractor.extract(from: $0) }
        let behaviorPairs = behaviorSignals.count
        // 训练事实 = App 内力量记录 ∪ 三年每日汇总里的训练日
        //（Apple 健康 + 训记导入的训练都以 workoutCount/时长落进每日汇总）。
        let recordedTrainingDays = dailySummaries.filter {
            ($0.workoutCount ?? 0) > 0 || ($0.workoutDuration ?? 0) >= 15
        }.count
        let trainingSessions = max(strengthWorkouts.count, recordedTrainingDays)
        let maturity = BodyModelMaturity(
            overall: maturityLevel(baselineDays: baselineDays, behaviorPairs: behaviorPairs, trainingSessions: trainingSessions, longTermDays: longTermDays),
            baselineDays: baselineDays,
            behaviorPairs: behaviorPairs,
            trainingSessions: trainingSessions
        )

        var claims: [BodyModelClaim] = []
        if let onboarding = evidence.onboardingSeed {
            claims.append(BodyModelClaim(
                id: "profile_seed",
                title: "目标与训练偏好已建立",
                summary: Self.profileSeedSummary(
                    primaryGoal: onboarding.primaryGoal,
                    trainingStyle: onboarding.trainingStyle,
                    weeklyTrainingDays: onboarding.weeklyTrainingDays
                ),
                confidence: onboarding.isCompleted ? .medium : .low,
                evidenceCount: 1
            ))
        }
        if trainingSessions > 0 {
            let analysis = TrainingAnalyticsService().buildRecentSummary(workouts: strengthWorkouts, days: 28, endingAt: evidence.asOf)
            claims.append(BodyModelClaim(
                id: "training_facts",
                title: "训练事实正在积累",
                summary: "近 28 天 \(analysis.sessions) 次训练，\(analysis.effectiveSets) 个有效组；这些数据会先用于局部疲劳和训练后反应观察。",
                confidence: trainingSessions >= 6 ? .medium : .low,
                evidenceCount: trainingSessions
            ))
        }
        // 三年生理基线拟合（Layer 2 身体模型版）：从回填数据拟合出「你这个人」。
        if let report = evidence.longTermBaselines, report.daysOfData >= 60 {
            var parts: [String] = []
            if let rhr = report.baselines[.restingHeartRate], let median = rhr.threeYearMedian {
                var text = "静息心率三年中位 \(Int(median.rounded())) bpm"
                if let dev = rhr.longTermDeviationPercent {
                    text += "，近 30 天偏离 \(String(format: "%+.0f", dev))%"
                }
                parts.append(text)
            }
            if let hrv = report.baselines[.hrv], let median = hrv.threeYearMedian {
                var text = "HRV 三年中位 \(Int(median.rounded())) ms"
                if let trend = hrv.trendLabel {
                    let label = trend == "improving" ? "改善" : (trend == "worsening" ? "走弱" : "平稳")
                    text += "，趋势\(label)"
                }
                parts.append(text)
            }
            if let volume = report.trainingVolume, let pct = volume.currentMonthPercentile {
                parts.append("本月训练量处于三年月分布 P\(Int(pct.rounded()))")
            }
            if !parts.isEmpty {
                claims.append(BodyModelClaim(
                    id: "long_term_baseline",
                    title: "三年生理基线已拟合",
                    summary: parts.joined(separator: "；"),
                    confidence: .high,
                    evidenceCount: report.daysOfData
                ))
            }
        }
        // 训练 → 次日 HRV/RHR 三年配对（行为-结果配对：训练作为行为）。
        if let pairing = Self.trainingResponsePairing(dailySummaries: dailySummaries, calendar: evidence.calendar, asOf: evidence.asOf) {
            claims.append(BodyModelClaim(
                id: "training_outcome_pairing",
                title: "训练后的次日反应已配对",
                summary: pairing.summary,
                confidence: pairing.sampleCount >= 24 ? .high : .medium,
                evidenceCount: pairing.sampleCount
            ))
        }
        // 深度专项批次 3：长线剂量-反应曲线（只作参考/收紧，不据良好反应加量）。
        if let dose = Self.doseResponseCurve(dailySummaries: dailySummaries, calendar: evidence.calendar, asOf: evidence.asOf) {
            claims.append(BodyModelClaim(
                id: "dose_response_curve",
                title: "训练剂量-反应曲线",
                summary: dose.summary,
                confidence: dose.samplePairs >= 120 ? .high : .medium,
                evidenceCount: dose.samplePairs
            ))
        }
        if behaviorPairs >= 6 {
            let grouped = Dictionary(grouping: behaviorSignals, by: \.tag)
            if let top = grouped.max(by: { $0.value.count < $1.value.count }) {
                claims.append(BodyModelClaim(
                    id: "behavior_pattern_\(top.key.rawValue)",
                    title: "行为信号样本开始可用",
                    summary: "\(top.key.displayTitle) 已记录 \(top.value.count) 次。下一步会和次日睡眠、HRV、RHR、恢复进行配对分析。",
                    confidence: .medium,
                    evidenceCount: top.value.count
                ))
            }
        }

        var uncertain: [BodyModelUncertainArea] = []
        if baselineDays < 7 && longTermDays < 60 {
            uncertain.append(BodyModelUncertainArea(
                id: "baseline_history",
                title: "个人基线仍在建立",
                detail: "需要至少 7 天健康摘要，才能把 HRV、RHR、睡眠和负荷判断从通用规则转向个人基线。"
            ))
        }
        if behaviorPairs < 6 {
            uncertain.append(BodyModelUncertainArea(
                id: "behavior_pairs",
                title: "行为-结果配对不足",
                detail: "饮食、咖啡因、饮酒、补水等行为至少需要约 6 次配对记录后才报告个人化影响。"
            ))
        }
        if trainingSessions < 3 || trainingResponses.count < 3 {
            uncertain.append(BodyModelUncertainArea(
                id: "training_response",
                title: "训练后反应样本不足",
                detail: "需要更多训练事实和次日恢复反馈，才能判断不同肌群/容量对你的恢复冲击。"
            ))
        }

        return BodyModelState(
            generatedAt: evidence.asOf,
            maturity: maturity,
            claims: claims,
            uncertainAreas: uncertain,
            behaviorSignals: behaviorSignals,
            trainingPatternSummary: trainingSummary(strengthWorkouts, recordedTrainingDays: recordedTrainingDays, asOf: evidence.asOf),
            coachRules: coachRules(for: maturity, uncertainAreas: uncertain)
        )
    }

    /// @Model 入口：转换为值类型后委托证据版（行为不变；调用方如已持有 Live
    /// 对象且处于 MainActor 可直接使用本入口）。
    func build(
        onboarding: OnboardingState?,
        dailySummaries: [DailyHealthSummaryRecord],
        journalEntries: [JournalEntryRecord],
        strengthWorkouts: [StrengthWorkoutRecord],
        trainingResponses: [TrainingResponseRecord],
        longTermBaselines: LongTermBaselineReport? = nil,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> BodyModelState {
        build(evidence: BodyModelEvidence(
            onboardingSeed: onboarding?.profileSeed,
            dailySummaries: dailySummaries.map(\.bodyModelEvidence),
            journalEntries: journalEntries.map(\.dto),
            strengthWorkouts: strengthWorkouts.map(\.dto),
            trainingResponses: trainingResponses.map(\.dto),
            longTermBaselines: longTermBaselines,
            asOf: asOf,
            calendar: calendar
        ))
    }

    private func maturityLevel(
        baselineDays: Int,
        behaviorPairs: Int,
        trainingSessions: Int,
        longTermDays: Int
    ) -> BodyModelMaturityLevel {
        // 整体成熟度衡量「模型是否拟合了你这个人」，以生理数据为准：
        // 三年长线（≥180 天）+ 足够训练事实即视为稳定期；
        // 手记行为是独立轨道（不足 6 对时仍在「待验证区域」诚实提示），
        // 不再阻塞整体稳定期——用户不写手记不意味着身体模型没拟合。
        let physiologicallyFitted = baselineDays >= 28 && trainingSessions >= 8
        let longTermFitted = longTermDays >= 180 && trainingSessions >= 8
        if physiologicallyFitted && behaviorPairs >= 12 { return .stable }
        if longTermFitted { return .stable }
        if baselineDays >= 7 || longTermDays >= 60 || behaviorPairs >= 6 || trainingSessions >= 3 { return .learning }
        return .seed
    }

    private func trainingSummary(_ workouts: [StrengthWorkoutDTO], recordedTrainingDays: Int, asOf: Date) -> String {
        guard !workouts.isEmpty else {
            if recordedTrainingDays > 0 {
                return "三年记录 \(recordedTrainingDays) 个训练日（Apple 健康 + 训记）；记录动作与组数后还可分析肌群容量。"
            }
            return "尚无训练事实。训记或 Vela 训练记录同步后会开始学习训练反应。"
        }
        let summary = TrainingAnalyticsService().buildRecentSummary(workouts: workouts, days: 28, endingAt: asOf)
        return "近 28 天 \(summary.sessions) 次训练，\(summary.effectiveSets) 个有效组，容量 \(Int(summary.volumeKg.rounded())) kg。"
    }

    /// 训练-结果三年配对（纯函数）：训练日次日 HRV/RHR 变化 vs 休息日次日变化。
    /// 训练日 = workoutCount > 0 或 workoutDuration ≥ 15 分钟；两组各 ≥ 8 天才发布，
    /// 效应量超过噪声阈值（HRV 3 ms / RHR 1.5 bpm）才形成结论。
    struct TrainingOutcomePairing: Equatable {
        var sampleCount: Int
        var summary: String
    }

    static func trainingResponsePairing(
        dailySummaries: [BodyModelDailyEvidence],
        calendar: Calendar = .current,
        asOf: Date = Date()
    ) -> TrainingOutcomePairing? {
        let byDay = dailySummaries.reduce(into: [Date: BodyModelDailyEvidence]()) { result, record in
            result[calendar.startOfDay(for: record.date)] = record
        }
        let sortedDays = byDay.keys.filter { $0 <= calendar.startOfDay(for: asOf) }.sorted()
        guard sortedDays.count >= 10 else { return nil }

        func isTrainingDay(_ record: BodyModelDailyEvidence) -> Bool {
            (record.workoutCount ?? 0) > 0 || (record.workoutDuration ?? 0) >= 15
        }

        var trainHRVDeltas: [Double] = []
        var restHRVDeltas: [Double] = []
        var trainRHRDeltas: [Double] = []
        var restRHRDeltas: [Double] = []

        for day in sortedDays {
            guard let record = byDay[day] else { continue }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day),
                  let nextRecord = byDay[next] else { continue }
            if let today = record.hrvAverage, let tomorrow = nextRecord.hrvAverage {
                let delta = tomorrow - today
                if isTrainingDay(record) { trainHRVDeltas.append(delta) } else { restHRVDeltas.append(delta) }
            }
            if let today = record.restingHeartRate, let tomorrow = nextRecord.restingHeartRate {
                let delta = tomorrow - today
                if isTrainingDay(record) { trainRHRDeltas.append(delta) } else { restRHRDeltas.append(delta) }
            }
        }

        func mean(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        guard trainHRVDeltas.count >= 8, restHRVDeltas.count >= 8 else { return nil }

        var parts: [String] = []
        let sampleCount = trainHRVDeltas.count
        if let trainMean = mean(trainHRVDeltas), let restMean = mean(restHRVDeltas) {
            let effect = trainMean - restMean
            if abs(effect) >= 3 {
                let direction = effect < 0 ? "多降" : "少降"
                parts.append("训练日次日 HRV 平均比休息日\(direction) \(String(format: "%.0f", abs(effect))) ms")
            }
        }
        if trainRHRDeltas.count >= 8, restRHRDeltas.count >= 8,
           let trainMean = mean(trainRHRDeltas), let restMean = mean(restRHRDeltas) {
            let effect = trainMean - restMean
            if abs(effect) >= 1.5 {
                let direction = effect > 0 ? "多升" : "少升"
                parts.append("次日静息心率比休息日\(direction) \(String(format: "%.1f", abs(effect))) bpm")
            }
        }
        guard !parts.isEmpty else { return nil }
        return TrainingOutcomePairing(
            sampleCount: sampleCount,
            summary: "三年配对（n=\(sampleCount) 个训练日）：\(parts.joined(separator: "；"))"
        )
    }

    /// @Model 版配对（保持既有测试与调用契约）：转换后委托值类型版。
    static func trainingResponsePairing(
        dailySummaries: [DailyHealthSummaryRecord],
        calendar: Calendar = .current,
        asOf: Date = Date()
    ) -> TrainingOutcomePairing? {
        trainingResponsePairing(
            dailySummaries: dailySummaries.map(\.bodyModelEvidence),
            calendar: calendar,
            asOf: asOf
        )
    }

    /// 深度专项批次 3：长线剂量-反应曲线（训练时长剂量 → 次日 HRV/RHR）。
    /// 三分位稳健对照（低/中/高剂量各 ≥8 对、总 ≥60 对），只作参考/收紧信号，
    /// 绝不据良好反应建议加量（ADR 0005 保守原则）。
    struct DoseResponseCurve: Equatable {
        var samplePairs: Int
        var summary: String
    }

    static func doseResponseCurve(
        dailySummaries: [BodyModelDailyEvidence],
        calendar: Calendar = .current,
        asOf: Date = Date()
    ) -> DoseResponseCurve? {
        let byDay = dailySummaries.reduce(into: [Date: BodyModelDailyEvidence]()) { result, record in
            result[calendar.startOfDay(for: record.date)] = record
        }
        let sortedDays = byDay.keys.filter { $0 <= calendar.startOfDay(for: asOf) }.sorted()
        var pairs: [(dose: Double, hrvDelta: Double?, rhrDelta: Double?)] = []
        for day in sortedDays {
            guard let record = byDay[day],
                  let duration = record.workoutDuration, duration >= 15,
                  let next = calendar.date(byAdding: .day, value: 1, to: day),
                  let nextRecord = byDay[next] else { continue }
            let hrvDelta: Double?
            if let today = record.hrvAverage, let tomorrow = nextRecord.hrvAverage {
                hrvDelta = tomorrow - today
            } else {
                hrvDelta = nil
            }
            let rhrDelta: Double?
            if let today = record.restingHeartRate, let tomorrow = nextRecord.restingHeartRate {
                rhrDelta = tomorrow - today
            } else {
                rhrDelta = nil
            }
            guard hrvDelta != nil || rhrDelta != nil else { continue }
            pairs.append((dose: duration, hrvDelta: hrvDelta, rhrDelta: rhrDelta))
        }
        guard pairs.count >= 60 else { return nil }
        let sorted = pairs.sorted { $0.dose < $1.dose }
        let n = sorted.count
        let low = sorted[0..<(n / 3)]
        let high = sorted[((2 * n) / 3)...]
        guard low.count >= 8, high.count >= 8 else { return nil }

        func meanHRV(_ slice: ArraySlice<(dose: Double, hrvDelta: Double?, rhrDelta: Double?)>) -> Double? {
            let values = slice.compactMap(\.hrvDelta)
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        func meanRHR(_ slice: ArraySlice<(dose: Double, hrvDelta: Double?, rhrDelta: Double?)>) -> Double? {
            let values = slice.compactMap(\.rhrDelta)
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        var parts: [String] = []
        if let lowH = meanHRV(low), let highH = meanHRV(high) {
            let effect = highH - lowH
            if abs(effect) >= 2 {
                parts.append("高剂量训练日次日 HRV 比低剂量日\(effect < 0 ? "多降" : "少降") \(String(format: "%.0f", abs(effect))) ms")
            }
        }
        if let lowR = meanRHR(low), let highR = meanRHR(high) {
            let effect = highR - lowR
            if abs(effect) >= 1 {
                parts.append("高剂量训练日次日静息心率比低剂量日\(effect > 0 ? "多升" : "少升") \(String(format: "%.1f", abs(effect))) bpm")
            }
        }
        guard !parts.isEmpty else { return nil }
        return DoseResponseCurve(
            samplePairs: pairs.count,
            summary: "剂量-反应（n=\(pairs.count) 个训练日）：\(parts.joined(separator: "；"))"
        )
    }

    /// @Model 版曲线（保持既有测试与调用契约）：转换后委托值类型版。
    static func doseResponseCurve(
        dailySummaries: [DailyHealthSummaryRecord],
        calendar: Calendar = .current,
        asOf: Date = Date()
    ) -> DoseResponseCurve? {
        doseResponseCurve(
            dailySummaries: dailySummaries.map(\.bodyModelEvidence),
            calendar: calendar,
            asOf: asOf
        )
    }


    private func coachRules(for maturity: BodyModelMaturity, uncertainAreas: [BodyModelUncertainArea]) -> [String] {
        var rules = [
            "只把样本充足的模式描述为个人规律；样本不足时使用“正在学习”。",
            "训练建议必须同时展示证据、置信度和可替代行动。"
        ]
        if maturity.overall == .seed {
            rules.append("Body Model 处于种子期，Coach 默认采用保守训练建议。")
        }
        if uncertainAreas.contains(where: { $0.id == "behavior_pairs" }) {
            rules.append("行为影响暂不下结论，只收集低摩擦手记信号。")
        }
        return rules
    }
}

struct DailyPlanLimiter: Codable, Hashable, Identifiable {
    var id: String { kind.rawValue }
    var kind: LimiterKind
    var accent: DailyPlanAccent
    var title: String
    var detail: String
    var severity: Double

    enum LimiterKind: String, Codable {
        case recovery, sleep, strain, stress, energy, localFatigue, trainingResponse
        case hrv, restingHeartRate
    }
}


enum CoachSnapshotDirective {
    static func build(
        dashboard: DashboardSummary,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let plan = dashboard.trainingDecision
        let limiterText = plan.limiter.map { "\($0.title) - \($0.detail)" } ?? L10n.t("none detected", "暂未识别")
        let time = formattedTime(generatedAt, calendar: calendar)
        let hrv = dashboard.recoveryMetrics.hrvMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "N/A"
        let rhr = dashboard.recoveryMetrics.restingHeartRate.map { "\(Int($0.rounded()))bpm" } ?? "N/A"
        let energy = dashboard.energy.value.map { "\(Int($0.rounded()))" } ?? "N/A"
        let targetRange = "\(dashboard.strain.recommendedRange.lowerBound)-\(dashboard.strain.recommendedRange.upperBound)"

        if AppLanguage.stored.isChinese {
            return """
            ## 当前健康快照协议（必须优先于旧对话）
            - 生成时间：\(time)
            - 恢复 \(Int(dashboard.recovery.score.rounded()))，睡眠 \(dashboard.sleepScore.value.map { String(Int($0.rounded())) } ?? "N/A")，负荷 \(Int(dashboard.strain.score.rounded()))（目标 \(targetRange)），能量 \(energy)，压力 \(Int(dashboard.stress.stressIndex.rounded()))
            - HRV \(hrv)，静息心率 \(rhr)
            - 主要限制因素：\(limiterText)

            回答健康或训练问题时，必须以这份最新快照为准；如果历史聊天与它冲突，以这里的数据为准。输出结构保持为：判断 / 原因 / 今天怎么做 / 不要做什么 / 可追问。不要把旧对话里的过期分数当成当前状态。
            """
        }

        return """
        ## Current Health Snapshot Protocol (fresh data has priority over old chat)
        - Generated at: \(time)
        - Recovery \(Int(dashboard.recovery.score.rounded())), Sleep \(dashboard.sleepScore.value.map { String(Int($0.rounded())) } ?? "N/A"), Strain \(Int(dashboard.strain.score.rounded())) (target \(targetRange)), Energy \(energy), Stress \(Int(dashboard.stress.stressIndex.rounded()))
        - HRV \(hrv), resting heart rate \(rhr)
        - Main limiter: \(limiterText)

        For health or training questions, treat this snapshot as the source of truth. If prior chat history conflicts with it, use these values. Keep the answer structure: judgment / reason / what to do today / what to avoid / follow-up. Do not reuse stale scores from older conversation turns as current state.
        """
    }

    private static func formattedTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = AppLanguage.stored.isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm XXX"
        return formatter.string(from: date)
    }
}

// MARK: - 联通专项批次 2：个人模型断言校准（正确/部分正确/不正确）

/// 用户对 BodyModelClaim 的标记（UserDefaults 存储；用于后续校准，
/// 一次评价不写成永久结论——产品方向 DIRECTION:27）。
enum ClaimRatingStore {
    private static let key = "vela.claim_ratings.v1"

    static func rating(for claimID: String, defaults: UserDefaults = .standard) -> String? {
        all(defaults: defaults)[claimID]
    }

    static func set(_ rating: String, for claimID: String, defaults: UserDefaults = .standard) {
        var ratings = all(defaults: defaults)
        ratings[claimID] = rating
        guard let data = try? JSONEncoder().encode(ratings) else { return }
        defaults.set(data, forKey: key)
    }

    static func all(defaults: UserDefaults = .standard) -> [String: String] {
        guard let data = defaults.data(forKey: key),
              let ratings = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return ratings
    }
}
