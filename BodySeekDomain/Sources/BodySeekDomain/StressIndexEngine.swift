import Foundation

public enum StressIndexInputMode: Hashable {
    case rawVitals
    case legacyComponentScores
}

public struct StressIndexInput: Hashable {
    public var asOf: Date
    public var mode: StressIndexInputMode
    public var quietHRToday: Double?
    public var quietHRBaseline: Double?
    public var quietHRSD: Double?
    
    public var hrvToday: Double?
    public var hrvBaseline: Double?
    public var hrvSD: Double?
    
    public var respRateToday: Double?
    public var respRateBaseline: Double?
    public var respRateSD: Double?
    
    public var bodyTempDelta: Double?
    public var sleepScoreLastNight: Double?
    public var strainScoreToday: Double?
    
    public var isWithinWorkoutWindow: Bool // inside workout window or 90 minutes post-workout

    /// 三年长线静息心率中位（Layer 3：RHR 压力分量的双基线门控；nil = 不启用）。
    public var longTermQuietHRMedian: Double?

    // Legacy fields for backward compatibility
    public var heartRateElevationScore: Double?
    public var hrvSuppressionScore: Double?
    public var sleepDebtStressScore: Double?
    public var recentStrainStressScore: Double?

    public init(
        asOf: Date,
        mode: StressIndexInputMode? = nil,
        quietHRToday: Double? = nil,
        quietHRBaseline: Double? = nil,
        quietHRSD: Double? = nil,
        hrvToday: Double? = nil,
        hrvBaseline: Double? = nil,
        hrvSD: Double? = nil,
        respRateToday: Double? = nil,
        respRateBaseline: Double? = nil,
        respRateSD: Double? = nil,
        bodyTempDelta: Double? = nil,
        sleepScoreLastNight: Double? = nil,
        strainScoreToday: Double? = nil,
        isWithinWorkoutWindow: Bool = false,
        longTermQuietHRMedian: Double? = nil,
        heartRateElevationScore: Double? = nil,
        hrvSuppressionScore: Double? = nil,
        sleepDebtStressScore: Double? = nil,
        recentStrainStressScore: Double? = nil
    ) {
        self.asOf = asOf
        let hasRawInput = quietHRToday != nil
            || hrvToday != nil
            || respRateToday != nil
            || bodyTempDelta != nil
            || sleepScoreLastNight != nil
            || strainScoreToday != nil
        self.mode = mode ?? (hasRawInput ? .rawVitals : .legacyComponentScores)
        self.quietHRToday = quietHRToday
        self.quietHRBaseline = quietHRBaseline
        self.quietHRSD = quietHRSD
        self.hrvToday = hrvToday
        self.hrvBaseline = hrvBaseline
        self.hrvSD = hrvSD
        self.respRateToday = respRateToday
        self.respRateBaseline = respRateBaseline
        self.respRateSD = respRateSD
        self.bodyTempDelta = bodyTempDelta
        self.sleepScoreLastNight = sleepScoreLastNight
        self.strainScoreToday = strainScoreToday
        self.isWithinWorkoutWindow = isWithinWorkoutWindow
        self.longTermQuietHRMedian = longTermQuietHRMedian
        self.heartRateElevationScore = heartRateElevationScore
        self.hrvSuppressionScore = hrvSuppressionScore
        self.sleepDebtStressScore = sleepDebtStressScore
        self.recentStrainStressScore = recentStrainStressScore
    }
}

public struct StressIndexEngine: ScoreEngine {
    public typealias Input = StressIndexInput
    public typealias Output = MetricResult

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func calculate(from input: StressIndexInput) -> MetricResult {
        var components: [String: Double] = [:]
        var componentWeights: [String: Double] = [:]
        var reasons: [String] = []
        var missingInputs: [String] = []

        let weights = [
            "rhr_stress": 0.25,
            "hrv_stress": 0.25,
            "resp_stress": 0.15,
            "temp_stress": 0.10,
            "sleep_debt_stress": 0.15,
            "load_stress": 0.10
        ]

        // Check if inside workout/post-workout window (exercise exclusion rule)
        if input.isWithinWorkoutWindow {
            reasons.append("运动窗口及运动后 90 分钟的自主神经恢复期内，生理压力处于不可估计状态（已排除，非零压力）。")
            let dataWindow = DateInterval(
                start: calendar.date(byAdding: .hour, value: -2, to: input.asOf) ?? input.asOf,
                end: input.asOf
            )
            
            return MetricResult(
                domain: .physiologicalStress,
                name: "Physiological Stress Index",
                value: nil, // Excluded
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: reasons,
                missingInputs: ["quietWindow"],
                dataWindow: dataWindow,
                source: .derived,
                algorithmVersion: ScoringAlgorithmVersions.physiologicalStress,
                lastUpdated: input.asOf
            )
        }

        // 1. RHR quiet stress (25%)
        switch input.mode {
        case .rawVitals:
            if let quietHR = input.quietHRToday {
                let baseline = input.quietHRBaseline ?? quietHR
                // SD=0 或非有限值时视为缺失（否则除零 → +inf → 静默满分）。
                let sd: Double
                if let provided = input.quietHRSD, provided.isFinite, provided > 0 {
                    sd = provided
                } else {
                    sd = max(2.5, baseline * 0.04)
                }
                let rhrZ = (quietHR - baseline) / sd
                var rhrStress = ScoringMath.clamp(50.0 + 18.0 * rhrZ, min: 0, max: 100)
                components["rhr_stress"] = rhrStress
                componentWeights["rhr_stress"] = weights["rhr_stress"] ?? 0

                if rhrZ > 1.2 {
                    // Layer 3 双基线门控：高于短期基线、但仍在三年长线正常范围内时，
                    // RHR 压力分量中和为 50（不再计为压力），并给出解释。
                    if let longTermMedian = input.longTermQuietHRMedian, quietHR <= longTermMedian {
                        rhrStress = 50.0
                        components["rhr_stress"] = rhrStress
                        reasons.append("静息心率高于短期基线，但仍在三年长期正常范围内，RHR 压力分量已中和")
                    } else {
                        reasons.append("静息心率高于近期个人基线")
                    }
                }
            } else {
                missingInputs.append("quietHRToday")
            }
        case .legacyComponentScores:
            if let rhrStress = input.heartRateElevationScore {
                components["rhr_stress"] = ScoringMath.clamp(rhrStress)
                componentWeights["rhr_stress"] = weights["rhr_stress"] ?? 0
            }
        }

        // 2. HRV quiet stress (25%)
        switch input.mode {
        case .rawVitals:
            if let hrvToday = input.hrvToday {
                let baseline = input.hrvBaseline ?? hrvToday
                let lnToday = log(max(hrvToday, 1.0))
                let lnBaseline = log(max(baseline, 1.0))
                // hrvSD 语义为原始 ms 域标准差，而 hrvZ 在 log 域计算。
                // 用 delta 方法换算：sd(log X) ≈ sd(X) / mean(X)；
                // 缺失时退回基线比例启发式（log 域），两者单位一致。
                let sd: Double
                if let rawSD = input.hrvSD, rawSD > 0, baseline > 1 {
                    sd = max(rawSD / baseline, 0.01)
                } else {
                    sd = max(0.01, lnBaseline * 0.12)
                }
                let hrvZ = (lnToday - lnBaseline) / sd

                let hrvStress = ScoringMath.clamp(50.0 - 18.0 * hrvZ, min: 0, max: 100)
                components["hrv_stress"] = hrvStress
                componentWeights["hrv_stress"] = weights["hrv_stress"] ?? 0

                if hrvZ < -1.2 {
                    reasons.append("今日 HRV 低于近期个人基线")
                }
            } else {
                missingInputs.append("hrvToday")
            }
        case .legacyComponentScores:
            if let hrvStress = input.hrvSuppressionScore {
                components["hrv_stress"] = ScoringMath.clamp(hrvStress)
                componentWeights["hrv_stress"] = weights["hrv_stress"] ?? 0
            }
        }

        // 3. Respiratory Rate Stress (15%)
        if let respToday = input.respRateToday {
            let baseline = input.respRateBaseline ?? respToday
            // SD=0 或非有限值时视为缺失（否则除零 → +inf → 静默满分）。
            let sd: Double
            if let provided = input.respRateSD, provided.isFinite, provided > 0 {
                sd = provided
            } else {
                sd = 1.0
            }
            let respZ = (respToday - baseline) / sd
            let respStress = ScoringMath.clamp(50.0 + 15.0 * respZ, min: 0, max: 100)
            components["resp_stress"] = respStress
            componentWeights["resp_stress"] = weights["resp_stress"] ?? 0
        }

        // 4. Temp Stress (10%)
        if let tempDelta = input.bodyTempDelta {
            let tempStress: Double
            // Normal circadian/day-to-day body-temp variation spans ~±0.6°C, so only
            // departures beyond that should raise stress. Was previously over-sensitive
            // (flagged at ±0.3/0.5/0.6°C), which fired on healthy users every day and
            // dragged Recovery/Energy/Stress low with normal raw signals.
            if abs(tempDelta) < 0.6 {
                tempStress = 20.0
            } else if abs(tempDelta) < 1.0 {
                tempStress = 50.0
                reasons.append("夜间皮肤温度检测到轻微波动")
            } else {
                tempStress = 80.0
                reasons.append("夜间皮肤温度偏离个人参考范围，已纳入压力评分")
            }
            components["temp_stress"] = tempStress
            componentWeights["temp_stress"] = weights["temp_stress"] ?? 0
        } else {
            missingInputs.append("bodyTempDelta")
        }

        // 5. Sleep Debt Stress (15%)
        let debtStress: Double? = {
            switch input.mode {
            case .rawVitals:
                return input.sleepScoreLastNight.map { ScoringMath.clamp(100.0 - $0) }
            case .legacyComponentScores:
                return input.sleepDebtStressScore.map { ScoringMath.clamp($0) }
            }
        }()
        if let debtStress {
            components["sleep_debt_stress"] = debtStress
            componentWeights["sleep_debt_stress"] = weights["sleep_debt_stress"] ?? 0
            
            if debtStress > 40 {
                reasons.append("昨晚睡眠评分偏低（单夜睡眠亏欠，非多日累积睡眠债），已提高生理压力代理估算。")
            }
        }

        // 6. Load Stress (10%)
        let strain = input.mode == .rawVitals ? input.strainScoreToday : input.recentStrainStressScore
        if let strain {
            components["load_stress"] = strain
            componentWeights["load_stress"] = weights["load_stress"] ?? 0
        }

        // Calculate Weighted Sum
        let totalWeight = componentWeights.values.reduce(0, +)
        let sumScore = components.reduce(0.0) { partial, item in
            partial + (item.value * (componentWeights[item.key] ?? 0.0))
        }

        let stressValue: Double?
        if totalWeight > 0 {
            stressValue = ScoringMath.clamp(sumScore / totalWeight, min: 0, max: 100)
        } else {
            stressValue = nil
        }

        // Mapped Band
        let band: MetricBand
        if let val = stressValue {
            if val < 25 {
                band = .veryLow // calm
            } else if val < 50 {
                band = .low // normal
            } else if val < 75 {
                band = .normal // elevated
            } else {
                band = .high // high
            }
        } else {
            band = .low
        }

        // Confidence: core quiet vitals (quietHR, HRV) must be present for high confidence
        let confidence: MetricConfidence
        let hasCoreVitals = (input.mode == .rawVitals ? (input.quietHRToday != nil && input.hrvToday != nil) : (input.heartRateElevationScore != nil && input.hrvSuppressionScore != nil))
        let hasAnyCoreVital = (input.mode == .rawVitals ? (input.quietHRToday != nil || input.hrvToday != nil) : (input.heartRateElevationScore != nil || input.hrvSuppressionScore != nil))
        if hasCoreVitals && components.count >= 5 {
            confidence = .high
        } else if hasAnyCoreVital && components.count >= 3 {
            confidence = .medium
        } else {
            confidence = .low
        }

        reasons.append("生理压力·估计：基于可用日级静息心率、HRV、呼吸、体温与昨夜睡眠的代理指标，不是心理或医疗诊断。")

        let dataWindow = DateInterval(
            start: calendar.date(byAdding: .hour, value: -24, to: input.asOf) ?? input.asOf,
            end: input.asOf
        )

        return MetricResult(
            domain: .physiologicalStress,
            name: "Physiological Stress Index",
            value: stressValue,
            band: band,
            confidence: confidence,
            components: components,
            componentWeights: componentWeights,
            reasons: reasons,
            missingInputs: missingInputs,
            dataWindow: dataWindow,
            source: .derived,
            algorithmVersion: ScoringAlgorithmVersions.physiologicalStress,
            lastUpdated: input.asOf
        )
    }
}
