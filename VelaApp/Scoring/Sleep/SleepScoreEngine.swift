import Foundation

/// In-memory sleep evidence contract. Availability describes the quality of a
/// component; freshness and query outcome are carried separately so a retained
/// value can be distinguished from a current observation.
public enum SleepObservationAvailability: String, Codable, Hashable, Sendable {
    case observed
    case estimated
    case missing
    case excluded
}

public struct SleepComponentObservation: Codable, Hashable, Sendable {
    public var value: Double?
    public var availability: SleepObservationAvailability
    public var reason: String?
    public var observedWindow: DateInterval?

    public init(
        value: Double?,
        availability: SleepObservationAvailability,
        reason: String? = nil,
        observedWindow: DateInterval? = nil
    ) {
        self.value = value
        self.availability = availability
        self.reason = reason
        self.observedWindow = observedWindow
    }

    public static func missing(_ reason: String? = nil) -> SleepComponentObservation {
        SleepComponentObservation(value: nil, availability: .missing, reason: reason)
    }
}

public struct SleepEvidenceContext: Codable, Hashable, Sendable {
    public var queryOutcome: HealthQueryOutcomeKind?
    public var freshness: DataFreshness?
    public var totalSleep: SleepComponentObservation
    public var bedtime: SleepComponentObservation
    public var wakeTime: SleepComponentObservation
    public var inBed: SleepComponentObservation
    public var awake: SleepComponentObservation
    public var rem: SleepComponentObservation
    public var deep: SleepComponentObservation
    public var episodeCount: SleepComponentObservation

    public init(
        queryOutcome: HealthQueryOutcomeKind? = nil,
        freshness: DataFreshness? = nil,
        totalSleep: SleepComponentObservation,
        bedtime: SleepComponentObservation,
        wakeTime: SleepComponentObservation,
        inBed: SleepComponentObservation,
        awake: SleepComponentObservation,
        rem: SleepComponentObservation,
        deep: SleepComponentObservation,
        episodeCount: SleepComponentObservation
    ) {
        self.queryOutcome = queryOutcome
        self.freshness = freshness
        self.totalSleep = totalSleep
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.inBed = inBed
        self.awake = awake
        self.rem = rem
        self.deep = deep
        self.episodeCount = episodeCount
    }

    public var isStale: Bool { freshness == .stale }

    static func from(
        summary: SleepSummary?,
        range: DateInterval,
        queryOutcome: HealthQueryOutcomeKind? = .data,
        freshness: DataFreshness? = .today
    ) -> SleepEvidenceContext {
        func observation(
            _ value: Double?,
            availability: SleepObservationAvailability,
            reason: String? = nil
        ) -> SleepComponentObservation {
            SleepComponentObservation(
                value: value,
                availability: availability,
                reason: reason,
                observedWindow: range
            )
        }

        guard let summary else {
            let missingOutcome = queryOutcome == .data ? .noData : (queryOutcome ?? .noData)
            let missingFreshness = missingOutcome == .noData ? .missing : (freshness ?? .missing)
            return SleepEvidenceContext(
                queryOutcome: missingOutcome,
                freshness: missingFreshness,
                totalSleep: .missing("没有睡眠摘要"),
                bedtime: .missing("没有入睡时间"),
                wakeTime: .missing("没有起床时间"),
                inBed: .missing("没有卧床阶段"),
                awake: .missing("没有清醒阶段"),
                rem: .missing("没有 REM 阶段"),
                deep: .missing("没有 Deep 阶段"),
                episodeCount: .missing("没有清醒次数")
            )
        }

        let total = Double(summary.totalSleepMinutes)
        let awake = summary.stageMinutes[.awake].map(Double.init)
        let inBed = summary.stageMinutes[.inBed].map(Double.init)
        let rem = summary.stageMinutes[.rem].map(Double.init)
        let deep = summary.stageMinutes[.deep].map(Double.init)
        let episodeCount = summary.segments.filter {
            $0.stage == .awake && $0.end.timeIntervalSince($0.start) >= 120
        }.count

        return SleepEvidenceContext(
            queryOutcome: queryOutcome,
            freshness: freshness,
            totalSleep: observation(
                total > 0 ? total : nil,
                availability: total > 0 ? .observed : .missing,
                reason: total > 0 ? nil : "没有有效睡眠片段"
            ),
            bedtime: observation(
                summary.bedtime?.timeIntervalSinceReferenceDate,
                availability: summary.bedtime == nil ? .missing : .observed
            ),
            wakeTime: observation(
                summary.wakeTime?.timeIntervalSinceReferenceDate,
                availability: summary.wakeTime == nil ? .missing : .observed
            ),
            inBed: {
                if let inBed, inBed > 0 {
                    return observation(inBed, availability: .observed)
                }
                if total > 0, let awake, awake >= 0 {
                    return observation(
                        total + awake,
                        availability: .estimated,
                        reason: "由睡眠时长与清醒时长推导卧床时长"
                    )
                }
                return .missing("HealthKit 未提供卧床阶段")
            }(),
            awake: observation(
                awake,
                availability: awake == nil ? .missing : .observed,
                reason: awake == nil ? "HealthKit 未提供清醒阶段" : nil
            ),
            rem: observation(
                rem,
                availability: rem == nil ? .missing : .observed,
                reason: rem == nil ? "HealthKit 未提供 REM 阶段" : nil
            ),
            deep: observation(
                deep,
                availability: deep == nil ? .missing : .observed,
                reason: deep == nil ? "HealthKit 未提供 Deep 阶段" : nil
            ),
            episodeCount: observation(
                Double(episodeCount),
                availability: .estimated,
                reason: "由清醒片段估算醒来次数"
            )
        )
    }

    public static func inferred(from input: SleepScoreInput) -> SleepEvidenceContext {
        SleepEvidenceContext(
            totalSleep: SleepComponentObservation(
                value: input.totalSleepMinutes,
                availability: input.totalSleepMinutes.map { $0 > 0 ? .observed : .missing } ?? .missing,
                reason: input.totalSleepMinutes == nil || (input.totalSleepMinutes ?? 0) <= 0
                    ? "没有有效睡眠片段"
                    : nil
            ),
            bedtime: input.todayBedtime.map {
                SleepComponentObservation(value: $0.timeIntervalSinceReferenceDate, availability: .observed)
            } ?? .missing("缺少入睡时间"),
            wakeTime: .missing("未提供起床时间"),
            inBed: {
                if let inBed = input.inBedMinutes {
                    return SleepComponentObservation(value: inBed, availability: .observed)
                }
                if let total = input.totalSleepMinutes,
                   let awake = input.awakeMinutes,
                   total > 0,
                   awake >= 0 {
                    return SleepComponentObservation(
                        value: total + awake,
                        availability: .estimated,
                        reason: "由睡眠时长与清醒时长推导卧床时长"
                    )
                }
                return .missing("缺少卧床时长")
            }(),
            awake: input.awakeMinutes.map {
                SleepComponentObservation(value: $0, availability: .observed)
            } ?? .missing("缺少清醒中断数据"),
            rem: input.remMinutes.map {
                SleepComponentObservation(value: $0, availability: .observed)
            } ?? .missing("缺少 REM 阶段数据"),
            deep: input.deepMinutes.map {
                SleepComponentObservation(value: $0, availability: .observed)
            } ?? .missing("缺少 Deep 阶段数据"),
            episodeCount: input.awakeEpisodeCount.map {
                SleepComponentObservation(value: Double($0), availability: .observed)
            } ?? .missing("缺少清醒次数数据")
        )
    }
}

enum SleepTargetSettings {
    static let hoursKey = "vela_sleep_target_hours"
    static let defaultHours = 7.5
    static let availableHours = stride(from: 5.0, through: 10.0, by: 0.5).map { $0 }

    static func targetMinutes(defaults: UserDefaults = .standard) -> Double {
        let configuredHours = defaults.object(forKey: hoursKey) as? Double ?? defaultHours
        return min(max(configuredHours, 5.0), 10.0) * 60.0
    }

    static func displayHours(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }
}

public struct SleepScoreInput: Hashable {
    public var asOf: Date
    public var totalSleepMinutes: Double?
    public var sleepTargetMinutes: Double
    public var todayBedtime: Date?
    public var recentBedtimes: [Date] // recent bedtimes (e.g. up to 13 nights)
    public var awakeMinutes: Double?
    public var awakeEpisodeCount: Int? // segments >= 2 minutes
    
    // Legacy support fields
    public var remMinutes: Double?
    public var deepMinutes: Double?
    public var inBedMinutes: Double?
    public var bedtimeOffsetMinutes: Double?
    public var wakeOffsetMinutes: Double?
    public var evidence: SleepEvidenceContext?

    public init(
        asOf: Date,
        totalSleepMinutes: Double?,
        sleepTargetMinutes: Double = 450,
        todayBedtime: Date? = nil,
        recentBedtimes: [Date] = [],
        awakeMinutes: Double? = nil,
        awakeEpisodeCount: Int? = nil,
        remMinutes: Double? = nil,
        deepMinutes: Double? = nil,
        inBedMinutes: Double? = nil,
        bedtimeOffsetMinutes: Double? = nil,
        wakeOffsetMinutes: Double? = nil,
        evidence: SleepEvidenceContext? = nil
    ) {
        self.asOf = asOf
        self.totalSleepMinutes = totalSleepMinutes
        self.sleepTargetMinutes = sleepTargetMinutes
        self.todayBedtime = todayBedtime
        self.recentBedtimes = recentBedtimes
        self.awakeMinutes = awakeMinutes
        self.awakeEpisodeCount = awakeEpisodeCount
        self.remMinutes = remMinutes
        self.deepMinutes = deepMinutes
        self.inBedMinutes = inBedMinutes
        self.bedtimeOffsetMinutes = bedtimeOffsetMinutes
        self.wakeOffsetMinutes = wakeOffsetMinutes
        self.evidence = evidence
    }
}

public struct SleepDetailAnalysis: Codable, Hashable {
    public var durationScore: Double
    public var efficiencyScore: Double
    public var regularityScore: Double
    public var architectureScore: Double
    public var continuityScore: Double
}

public struct SleepScoreEngine: ScoreEngine {
    public typealias Input = SleepScoreInput
    public typealias Output = MetricResult

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private func minutesFromNoon(_ date: Date) -> Double {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        var minutes = Double(h * 60 + m)
        if minutes < 12 * 60 {
            minutes += 24 * 60
        }
        return minutes
    }

    private func canUse(_ observation: SleepComponentObservation) -> Bool {
        switch observation.availability {
        case .observed, .estimated:
            return observation.value != nil
        case .missing, .excluded:
            return false
        }
    }

    private func downgrade(_ confidence: MetricConfidence) -> MetricConfidence {
        switch confidence {
        case .high: return .medium
        case .medium, .low: return .low
        }
    }

    public func calculate(from input: SleepScoreInput) -> MetricResult {
        let evidence = input.evidence ?? SleepEvidenceContext.inferred(from: input)
        let totalSleep = input.totalSleepMinutes ?? evidence.totalSleep.value
        guard let totalSleep, totalSleep > 0, canUse(evidence.totalSleep) else {
            let dataWindow = DateInterval(
                start: calendar.date(byAdding: .day, value: -13, to: input.asOf) ?? input.asOf,
                end: input.asOf
            )
            var reasons = ["缺少睡眠时长数据"]
            if evidence.isStale {
                reasons.append("睡眠数据来自上次可信同步，当前查询结果已过期")
            }
            if let outcome = evidence.queryOutcome, outcome != .data {
                reasons.append("睡眠查询状态：\(outcome.rawValue)")
            }
            return MetricResult(
                domain: .sleep,
                name: "Sleep Score",
                value: nil,
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: reasons,
                missingInputs: ["totalSleepMinutes"],
                dataWindow: dataWindow,
                source: .healthKit,
                algorithmVersion: ScoringAlgorithmVersions.sleep,
                lastUpdated: input.asOf
            )
        }

        var components: [String: Double] = [:]
        var componentWeights: [String: Double] = [:]
        var reasons: [String] = []
        var missingInputs: [String] = []

        if evidence.isStale {
            reasons.append("睡眠数据来自上次可信同步，当前结果已标记为陈旧")
        }
        if let outcome = evidence.queryOutcome, outcome != .data {
            reasons.append("睡眠查询状态：\(outcome.rawValue)")
        }

        let todayBedtime = canUse(evidence.bedtime) ? input.todayBedtime : nil
        let awakeMinutes = canUse(evidence.awake) ? (input.awakeMinutes ?? evidence.awake.value) : nil
        let awakeEpisodeCount = canUse(evidence.episodeCount)
            ? (input.awakeEpisodeCount ?? evidence.episodeCount.value.map { Int($0.rounded()) })
            : nil
        let inBedMinutes = canUse(evidence.inBed)
            ? (input.inBedMinutes ?? evidence.inBed.value)
            : nil
        let remMinutes = canUse(evidence.rem) ? (input.remMinutes ?? evidence.rem.value) : nil
        let deepMinutes = canUse(evidence.deep) ? (input.deepMinutes ?? evidence.deep.value) : nil
        let hasEstimatedComponent = [
            evidence.totalSleep,
            evidence.bedtime,
            evidence.wakeTime,
            evidence.inBed,
            evidence.awake,
            evidence.rem,
            evidence.deep,
            evidence.episodeCount
        ].contains { $0.availability == .estimated }
            || (awakeMinutes != nil && awakeEpisodeCount == nil)

        func appendMissing(_ key: String, when unavailable: Bool) {
            guard unavailable, !missingInputs.contains(key) else { return }
            missingInputs.append(key)
        }
        appendMissing("inBedMinutes", when: !canUse(evidence.inBed))
        appendMissing("remMinutes", when: !canUse(evidence.rem))
        appendMissing("deepMinutes", when: !canUse(evidence.deep))
        appendMissing("awakeEpisodeCount", when: !canUse(evidence.episodeCount))

        let target = input.sleepTargetMinutes > 0 ? input.sleepTargetMinutes : 450

        // 1. Duration Score (0 - 50)
        var durationScore: Double? = nil
        if totalSleep > 0 {
            if totalSleep >= (target - 30) && totalSleep <= (target + 60) {
                durationScore = 50.0
            } else if totalSleep < (target - 30) {
                let range = (target - 30) - 240
                let progress = range > 0 ? (totalSleep - 240) / range : 0
                durationScore = 50.0 * ScoringMath.clamp(progress, min: 0, max: 1)
            } else {
                let progress = 1.0 - (totalSleep - (target + 60)) / 240.0
                durationScore = 50.0 * ScoringMath.clamp(progress, min: 0, max: 1)
            }
            components["duration"] = durationScore!
            componentWeights["duration"] = 50.0
            
            let actualText = Self.durationText(totalSleep)
            let targetText = Self.targetDurationText(target)
            let completion: String
            if totalSleep >= target {
                let excess = totalSleep - target
                completion = excess > 0
                    ? "已达成个人作息目标 \(targetText)；超过目标\(Self.excessDurationText(excess))"
                    : "已达成个人作息目标 \(targetText)"
            } else {
                completion = "未达成个人作息目标 \(targetText)"
            }
            if target < 420 {
                reasons.append("睡眠时长 \(actualText)（\(completion)；注：依据 AASM 成人共识，成人健康睡眠建议为 7–9 小时，达成个人作息目标不代表生理充分满足）")
            } else {
                reasons.append("睡眠时长 \(actualText)（\(completion)）")
            }
        }

        // 2. Consistency Score (0 - 30)
        var consistencyScore: Double? = nil
        if input.recentBedtimes.count >= 5, let todayBedtime {
            let baselineBedtimesMinutes = input.recentBedtimes.map { minutesFromNoon($0) }
            if let baselineMedian = PersonalBaselineEngine.median(baselineBedtimesMinutes) {
                let todayBedtimeMinutes = minutesFromNoon(todayBedtime)
                let diff = abs(todayBedtimeMinutes - baselineMedian)
                
                if diff <= 30 {
                    consistencyScore = 30.0
                } else if diff <= 60 {
                    consistencyScore = 24.0
                } else if diff <= 90 {
                    consistencyScore = 18.0
                } else if diff <= 120 {
                    consistencyScore = 12.0
                } else if diff <= 180 {
                    consistencyScore = 6.0
                } else {
                    consistencyScore = 0.0
                }
                components["consistency"] = consistencyScore!
                componentWeights["consistency"] = 30.0
                
                reasons.append("入睡一致性差异约为 \(Int(diff))分钟（基线参考过去 \(input.recentBedtimes.count)晚）")
            }
        } else {
            if todayBedtime == nil {
                missingInputs.append("todayBedtime")
            }
            if input.recentBedtimes.count < 5 {
                missingInputs.append("recentBedtimesHistory")
                reasons.append("最近 13 晚有效睡眠记录不足 5 晚，一致性得分已降级")
            }
        }

        // 3. Interruption Score (0 - 20)
        var interruptionScore: Double? = nil
        if let awakeMinutes {
            let awakeCount = awakeEpisodeCount ?? (awakeMinutes > 0 ? max(1, Int(awakeMinutes / 8)) : 0)
            let penalty = 0.45 * awakeMinutes + 2.5 * Double(awakeCount)
            interruptionScore = ScoringMath.clamp(20.0 - penalty, min: 0, max: 20)
            
            components["interruption"] = interruptionScore!
            componentWeights["interruption"] = 20.0
            
            if awakeEpisodeCount != nil, evidence.episodeCount.availability != .estimated {
                reasons.append("睡眠中断 \(Int(awakeMinutes))分钟（醒来频率 \(awakeCount)次）")
            } else if awakeMinutes > 0 {
                reasons.append("睡眠中断 \(Int(awakeMinutes))分钟（醒来频率约 \(awakeCount)次 · 估算）")
            } else {
                reasons.append("睡眠中断 0分钟")
            }
        } else {
            missingInputs.append("awakeMinutes")
            reasons.append("缺少睡眠阶段中断数据")
        }

        // Renormalization
        let availableWeight = componentWeights.values.reduce(0, +)
        let sumScore = components.reduce(0) { $0 + $1.value }
        
        let confidence: MetricConfidence
        if components.count == 3 {
            confidence = .high
        } else if components.count >= 2 {
            confidence = .medium
        } else {
            confidence = .low
        }

        var adjustedConfidence = confidence
        if hasEstimatedComponent {
            adjustedConfidence = downgrade(adjustedConfidence)
            reasons.append("部分睡眠组件由其他观测估算，置信度已降低")
        }
        if evidence.isStale {
            adjustedConfidence = downgrade(adjustedConfidence)
        }

        var finalValue: Double?
        if availableWeight > 0 {
            let baseVal = ScoringMath.clamp((sumScore / availableWeight) * 100.0, min: 0, max: 100)
            if adjustedConfidence == .low {
                finalValue = min(baseVal, 79.0)
                reasons.append("由于缺少质量与一致性指标，该评分已降为低置信度（最大限制为 79 分）")
            } else {
                finalValue = baseVal
            }
        } else {
            finalValue = nil
        }

        // Mapped Band
        let band: MetricBand
        if let val = finalValue {
            band = ScoringMath.band(for: val)
        } else {
            band = .low
        }

        // Add disclaimers
        reasons.append("睡眠分析根据 Apple 公开结构建模，非官方指标。")

        // 4. Preserve Buysse 5-Dimension Legacy Analysis under components/metrics
        let detail = calculateLegacyBuysse(from: input)
        components["buysse_duration"] = detail.durationScore
        if inBedMinutes != nil || awakeMinutes != nil {
            components["buysse_efficiency"] = detail.efficiencyScore
        }
        if input.bedtimeOffsetMinutes != nil || input.wakeOffsetMinutes != nil {
            components["buysse_regularity"] = detail.regularityScore
        }
        if remMinutes != nil && deepMinutes != nil {
            components["buysse_architecture"] = detail.architectureScore
        }
        if awakeMinutes != nil {
            components["buysse_continuity"] = detail.continuityScore
        }

        if totalSleep > 0 {
            if let inBed = inBedMinutes, inBed > 0 {
                components["sleep_efficiency"] = totalSleep / inBed * 100.0
            }
            if let remMinutes {
                components["rem_pct"] = remMinutes / totalSleep * 100.0
            }
            if let deepMinutes {
                components["deep_pct"] = deepMinutes / totalSleep * 100.0
            }
        }
        if let awakeMinutes {
            components["awake_minutes"] = awakeMinutes
            let awakeCount = awakeEpisodeCount ?? (awakeMinutes > 0 ? max(1, Int(awakeMinutes / 8)) : 0)
            components["awake_episode_count"] = Double(awakeCount)
        }

        let dataWindow = DateInterval(
            start: calendar.date(byAdding: .day, value: -13, to: input.asOf) ?? input.asOf,
            end: input.asOf
        )

        return MetricResult(
            domain: .sleep,
            name: "Sleep Score",
            value: finalValue,
            band: band,
            confidence: adjustedConfidence,
            components: components,
            componentWeights: componentWeights,
            reasons: reasons,
            missingInputs: missingInputs,
            dataWindow: dataWindow,
            source: .healthKit,
            algorithmVersion: ScoringAlgorithmVersions.sleep,
            lastUpdated: input.asOf
        )
    }

    private static func durationText(_ minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded(.towardZero)))
        return "\(roundedMinutes / 60)小时\(roundedMinutes % 60)分钟"
    }

    private static func targetDurationText(_ minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded(.towardZero)))
        return roundedMinutes % 60 == 0
            ? "\(roundedMinutes / 60)小时"
            : durationText(minutes)
    }

    private static func excessDurationText(_ minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded(.towardZero)))
        return roundedMinutes < 60
            ? "\(roundedMinutes)分钟"
            : durationText(minutes)
    }

    private func calculateLegacyBuysse(from input: SleepScoreInput) -> SleepDetailAnalysis {
        // Implement simple fallback 5D scoring based on input values
        let dur: Double
        if let totalSleep = input.totalSleepMinutes {
            let target = input.sleepTargetMinutes > 0 ? input.sleepTargetMinutes : 450
            let ratio = totalSleep / target
            if ratio >= 0.95 && ratio <= 1.05 { dur = 20 }
            else if ratio >= 0.90 && ratio <= 1.10 { dur = 18 }
            else if ratio < 0.60 { dur = 4 }
            else if ratio > 1.30 { dur = 12 }
            else { dur = 20 * pow(ratio, 3) }
        } else {
            dur = 15
        }

        let eff: Double
        if let totalSleep = input.totalSleepMinutes {
            let awake = input.awakeMinutes ?? 0
            let inBed = input.inBedMinutes ?? (totalSleep + awake)
            if inBed > 0 {
                let ratio = totalSleep / inBed
                if ratio >= 0.95 { eff = 20 }
                else if ratio >= 0.90 { eff = 18 }
                else if ratio >= 0.85 { eff = 15 }
                else if ratio >= 0.80 { eff = 12 }
                else { eff = 6 }
            } else { eff = 15 }
        } else {
            eff = 15
        }

        let reg: Double
        if let bOffset = input.bedtimeOffsetMinutes, let wOffset = input.wakeOffsetMinutes {
            let avgOffset = (abs(bOffset) + abs(wOffset)) / 2
            if avgOffset <= 15 { reg = 20 }
            else if avgOffset <= 30 { reg = 18 }
            else if avgOffset <= 45 { reg = 15 }
            else if avgOffset <= 60 { reg = 12 }
            else { reg = 8 }
        } else {
            reg = 15
        }

        let arch: Double
        if let totalSleep = input.totalSleepMinutes, totalSleep > 0 {
            let rem = input.remMinutes ?? 0
            let deep = input.deepMinutes ?? 0
            let remPct = rem / totalSleep
            let deepPct = deep / totalSleep
            
            let remS = (0.20...0.25).contains(remPct) ? 10.0 : ((0.15..<0.20).contains(remPct) || (0.25...0.30).contains(remPct) ? 8.0 : 5.0)
            let deepS = (0.15...0.20).contains(deepPct) ? 10.0 : ((0.10..<0.15).contains(deepPct) || (0.20...0.25).contains(deepPct) ? 8.0 : 5.0)
            arch = remS + deepS
        } else {
            arch = 15
        }

        let cont: Double
        if let awakeMinutes = input.awakeMinutes {
            let awakeCount = input.awakeEpisodeCount ?? (awakeMinutes > 0 ? max(1, Int(awakeMinutes / 8)) : 0)
            let tPenalty = awakeMinutes <= 10 ? 0.0 : (awakeMinutes <= 20 ? 3.0 : (awakeMinutes <= 40 ? 7.0 : 11.0))
            let cPenalty = awakeCount <= 1 ? 0.0 : (awakeCount <= 3 ? 2.0 : 5.0)
            cont = max(2.0, 20.0 - tPenalty - cPenalty)
        } else {
            cont = 15
        }

        return SleepDetailAnalysis(
            durationScore: dur,
            efficiencyScore: eff,
            regularityScore: reg,
            architectureScore: arch,
            continuityScore: cont
        )
    }
}
