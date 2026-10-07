import Foundation

public struct EnergyBankInput: Hashable {
    public var asOf: Date
    public var recoveryScore: Double?
    public var sleepScore: Double?
    public var strainScore: Double?
    public var stressIndex: Double?

    public var hrvToday: Double?
    public var hrvBaseline: Double?
    public var rhrToday: Double?
    public var rhrBaseline: Double?
    public var sleepHours: Double?
    public var strainHistory: [Double]?
    /// Evidence-preserving history. When supplied, this takes precedence over
    /// the legacy numeric history and keeps missing calendar days distinct from
    /// measured zero-load days.
    public var trainingLoadHistory: [DailyLoadObservation]?
    /// 今日真实训练负荷（TRIMP 域，与 strainHistory 同单位）。
    /// ATL/CTL/TSB 计算必须使用该值；strainScore 是 0-100 评分域，只用于能量消耗 drain。
    public var todayLoad: Double?
    public var todayLoadObservation: DailyLoadObservation?
    public var bodyTempDelta: Double?
    
    // New fields for Core Metrics v1
    public var hoursSinceWake: Double?
    public var respiratoryRateZ: Double?
    public var SpO2: Double?
    public var mindfulMinutes: Double?
    public var napMinutes: Double?
    public var trainingLoadStatus: TrainingLoadStatus?
    public var recoveryConfidence: MetricConfidence?
    public var sleepConfidence: MetricConfidence?

    public init(
        asOf: Date,
        recoveryScore: Double?,
        sleepScore: Double?,
        strainScore: Double?,
        stressIndex: Double?,
        hrvToday: Double? = nil,
        hrvBaseline: Double? = nil,
        rhrToday: Double? = nil,
        rhrBaseline: Double? = nil,
        sleepHours: Double? = nil,
        strainHistory: [Double]? = nil,
        trainingLoadHistory: [DailyLoadObservation]? = nil,
        todayLoad: Double? = nil,
        todayLoadObservation: DailyLoadObservation? = nil,
        bodyTempDelta: Double? = nil,
        hoursSinceWake: Double? = nil,
        respiratoryRateZ: Double? = nil,
        SpO2: Double? = nil,
        mindfulMinutes: Double? = nil,
        napMinutes: Double? = nil,
        trainingLoadStatus: TrainingLoadStatus? = nil,
        recoveryConfidence: MetricConfidence? = nil,
        sleepConfidence: MetricConfidence? = nil
    ) {
        self.asOf = asOf
        self.recoveryScore = recoveryScore
        self.sleepScore = sleepScore
        self.strainScore = strainScore
        self.stressIndex = stressIndex
        self.hrvToday = hrvToday
        self.hrvBaseline = hrvBaseline
        self.rhrToday = rhrToday
        self.rhrBaseline = rhrBaseline
        self.sleepHours = sleepHours
        self.strainHistory = strainHistory
        self.trainingLoadHistory = trainingLoadHistory
        self.todayLoad = todayLoad
        self.todayLoadObservation = todayLoadObservation
        self.bodyTempDelta = bodyTempDelta
        self.hoursSinceWake = hoursSinceWake
        self.respiratoryRateZ = respiratoryRateZ
        self.SpO2 = SpO2
        self.mindfulMinutes = mindfulMinutes
        self.napMinutes = napMinutes
        self.trainingLoadStatus = trainingLoadStatus
        self.recoveryConfidence = recoveryConfidence
        self.sleepConfidence = sleepConfidence
    }
}

public struct EnergyBankEngine: ScoreEngine {
    public typealias Input = EnergyBankInput
    public typealias Output = MetricResult

    public init() {}

    public func calculate(from input: EnergyBankInput) -> MetricResult {
        var components: [String: Double] = [:]
        var reasons: [String] = []
        var missingInputs: [String] = []

        // 1. Overnight Stability
        let hasOvernightSignals = input.bodyTempDelta != nil || input.respiratoryRateZ != nil || input.SpO2 != nil
        let overnightStability: Double
        if hasOvernightSignals {
            var stab = 100.0
            if let bodyTempDelta = input.bodyTempDelta, bodyTempDelta > 1.0 {
                stab -= 15.0
                reasons.append("夜间体温明显升高，扣除稳定性基准分")
            }
            if let rrZ = input.respiratoryRateZ, rrZ > 1.5 {
                stab -= 10.0
            }
            if let spO2 = input.SpO2, spO2 < 94 {
                stab -= 10.0
            }
            overnightStability = stab
        } else {
            // 未测稳定性不作为已测 100 分；缺失也不扣为 0，采用中性基准 50 并明确标明
            overnightStability = 50.0
            missingInputs.append("overnightStabilitySignals")
            reasons.append("缺少夜间体温、呼吸率与血氧信号，夜间稳定性按基准中值 50 估计。")
        }
        components["overnight_stability"] = overnightStability

        // 2. Morning Energy (0.45 Recovery + 0.35 Sleep + 0.20 Stability)
        var morningEnergy: Double?
        let rec = input.recoveryScore
        let slp = input.sleepScore

        if let rec, let slp {
            morningEnergy = 0.45 * rec + 0.35 * slp + 0.20 * overnightStability
            components["recovery"] = rec
            components["sleep"] = slp
        } else if let rec {
            morningEnergy = 0.70 * rec + 0.30 * overnightStability
            components["recovery"] = rec
            missingInputs.append("sleepScore")
            reasons.append("睡眠数据缺失，早间能量根据恢复度估算")
        } else if let slp {
            morningEnergy = 0.70 * slp + 0.30 * overnightStability
            components["sleep"] = slp
            missingInputs.append("recoveryScore")
            reasons.append("恢复度数据缺失，早间能量根据睡眠评分估算")
        } else {
            morningEnergy = nil
            missingInputs.append("recoveryScore")
            missingInputs.append("sleepScore")
            reasons.append("需要恢复或睡眠评分后，才会给出能量评分。")
        }
        let chargeEfficiency = calculateChargeEfficiency(from: input)
        components["charge_efficiency"] = chargeEfficiency

        if let value = morningEnergy {
            let adjusted = ScoringMath.clamp(
                value + (chargeEfficiency - 0.6) * 12.0,
                min: 0,
                max: 100
            )
            morningEnergy = adjusted
            components["morningEnergy"] = adjusted
        }

        let trainingLoad = calculateTrainingLoad(
            history: input.trainingLoadHistory ?? legacyTrainingLoadHistory(input),
            today: input.todayLoadObservation ?? legacyTodayLoadObservation(input)
        )
        if let atl = trainingLoad.atl,
           let ctl = trainingLoad.ctl,
           let tsb = trainingLoad.tsb,
           let acwr = trainingLoad.acwr {
            components["atl"] = atl
            components["ctl"] = ctl
            components["tsb"] = tsb
            components["acwr"] = acwr
        } else {
            if trainingLoad.observedDays < 7 {
                missingInputs.append("trainingLoadHistory")
                reasons.append("历史负荷有效观测不足 7 天，未发布 ATL、CTL、TSB 或 ACWR。")
            }
            if !trainingLoad.todayAvailability.contributesToLoad {
                missingInputs.append("todayLoad")
                reasons.append("今日训练负荷缺失或被排除，未发布当日负荷状态。")
            }
        }

        // 3. Day Drain Calculations
        let strainScore = input.strainScore ?? 0.0
        let strainDrain = 0.35 * strainScore
        if input.strainScore == nil {
            // A missing strain score contributes no drain, but it is still
            // unknown evidence. Preserve that distinction for coverage and
            // downstream explanations instead of silently treating it as a
            // measured zero.
            missingInputs.append("strainScore")
            reasons.append("负荷评分数据缺失，未计入训练消耗。")
        }

        let stressDrain: Double
        if let stress = input.stressIndex {
            stressDrain = 0.25 * stress
        } else if let strain = input.strainScore, strain > 0 {
            // 运动及恢复期内，生理压力处于排除状态（nil），消耗已由训练负荷承担，避免误判为能量回升
            stressDrain = 0.0
            reasons.append("生理压力处于运动排除窗口，未计入额外静息压力消耗（消耗由训练负荷承担）。")
        } else {
            // 未知消耗：压力缺失且无活动负荷
            stressDrain = 0.0
            missingInputs.append("stressIndex")
            reasons.append("生理压力数据缺失，未计入日间压力消耗。")
        }
        
        let timeDrain: Double
        if let hoursSinceWake = input.hoursSinceWake {
            timeDrain = ScoringMath.clamp(hoursSinceWake / 16.0 * 12.0, min: 0, max: 12.0)
        } else {
            timeDrain = 0
            missingInputs.append("wakeTime")
            reasons.append("缺少起床时间，当前能量未扣除日间时间消耗。")
        }
        
        // Training Load status drain
        let loadDrain: Double
        switch input.trainingLoadStatus {
        case .elevated:
            loadDrain = 5.0
            reasons.append("检测到积累性训练负荷升高，加速能量消耗")
        case .highRisk:
            loadDrain = 10.0
            reasons.append("近期负荷激增，身体处于高敏感疲劳状态，加速日间能量流失")
        default:
            loadDrain = 0.0
        }

        // 4. Recharge behaviors
        let mindful = input.mindfulMinutes ?? 0.0
        let nap = input.napMinutes ?? 0.0
        let recharge = min(8.0, mindful * 0.15 + nap * 0.20)
        if recharge > 0 {
            reasons.append("今日通过静心/小憩补充了 \(String(format: "%.1f", recharge)) 点身体能量")
        }

        // Current Energy
        let currentEnergy = morningEnergy.map {
            ScoringMath.clamp(
                $0 - strainDrain - stressDrain - timeDrain - loadDrain + recharge,
                min: 0,
                max: 100
            )
        }

        components["strain_drain"] = strainDrain
        components["stress_drain"] = stressDrain
        components["time_drain"] = timeDrain
        components["load_drain"] = loadDrain
        components["recharge"] = recharge

        let band: MetricBand
        if let currentEnergy, currentEnergy < 25 {
            band = .veryLow // depleted
        } else if let currentEnergy, currentEnergy < 50 {
            band = .low // low
        } else if let currentEnergy, currentEnergy < 75 {
            band = .normal // stable
        } else if currentEnergy != nil {
            band = .high // strong
        } else {
            band = .low
        }

        reasons.append("能量估计：全天体能代理估算值，主要用于规划今日运动与恢复，非医学诊断。")

        let dataWindow = DateInterval(
            start: Calendar.current.date(byAdding: .hour, value: -12, to: input.asOf) ?? input.asOf,
            end: input.asOf
        )

        let confidence: MetricConfidence
        if currentEnergy == nil {
            confidence = .low
        } else if rec != nil && slp != nil {
            let upstreamHigh = (input.recoveryConfidence == nil || input.recoveryConfidence == .high)
                && (input.sleepConfidence == nil || input.sleepConfidence == .high)
            let upstreamLow = (input.recoveryConfidence == .low || input.sleepConfidence == .low)

            if upstreamLow {
                confidence = .low
            } else if upstreamHigh && hasOvernightSignals && input.stressIndex != nil {
                confidence = .high
            } else {
                confidence = .medium
            }
        } else {
            confidence = .low
        }

        return MetricResult(
            domain: .energy,
            name: "Energy Bank",
            value: currentEnergy,
            band: band,
            confidence: confidence,
            components: components,
            componentWeights: [:],
            reasons: reasons,
            missingInputs: missingInputs,
            dataWindow: dataWindow,
            source: .derived,
            algorithmVersion: ScoringAlgorithmVersions.energy,
            lastUpdated: input.asOf
        )
    }

    private func calculateChargeEfficiency(from input: EnergyBankInput) -> Double {
        guard let hrvToday = input.hrvToday,
              let hrvBaseline = input.hrvBaseline,
              hrvBaseline > 0,
              let rhrToday = input.rhrToday,
              let rhrBaseline = input.rhrBaseline,
              rhrBaseline > 0 else {
            return 0.6
        }

        let hrvRatio = hrvToday / hrvBaseline
        let hrvScore: Double
        switch hrvRatio {
        case ..<0.8: hrvScore = 0.2
        case ..<0.9: hrvScore = 0.4
        case ..<1.1: hrvScore = 0.7
        case ..<1.3: hrvScore = 0.9
        default: hrvScore = 1.0
        }

        let rhrRatio = rhrToday / rhrBaseline
        let rhrScore: Double
        switch rhrRatio {
        case ..<0.90: rhrScore = 1.0
        case ..<0.95: rhrScore = 0.9
        case ..<1.05: rhrScore = 0.7
        case ..<1.10: rhrScore = 0.4
        default: rhrScore = 0.2
        }

        return 0.6 * hrvScore + 0.4 * rhrScore
    }

    private struct TrainingLoadProjection {
        let atl: Double?
        let ctl: Double?
        let tsb: Double?
        let acwr: Double?
        let observedDays: Int
        let todayAvailability: TrainingLoadAvailability
    }

    private func calculateTrainingLoad(
        history: [DailyLoadObservation],
        today: DailyLoadObservation
    ) -> TrainingLoadProjection {
        let orderedHistory = history.sorted { $0.date < $1.date }
        let observedDays = orderedHistory.filter(\.isObservedValue).count
        // Missing/excluded dates contribute calendar decay but are not counted
        // as measured zero-load days. Known zero remains a real observation.
        let loadsIncludingToday = orderedHistory.map { observation in
            observation.availability.contributesToLoad ? (observation.value ?? 0.0) : 0.0
        } + (today.availability.contributesToLoad ? [today.value ?? 0.0] : [])

        guard observedDays >= 7,
              today.availability.contributesToLoad,
              !loadsIncludingToday.isEmpty else {
            return TrainingLoadProjection(
                atl: nil,
                ctl: nil,
                tsb: nil,
                acwr: nil,
                observedDays: observedDays,
                todayAvailability: today.availability
            )
        }

        let atl = ewma(loadsIncludingToday, lambda: 2.0 / (7.0 + 1.0))
        let ctl = ewma(loadsIncludingToday, lambda: 2.0 / (42.0 + 1.0))

        let ctl28 = ewma(loadsIncludingToday, lambda: 2.0 / (28.0 + 1.0))
        let acwr = ctl28 > 0 ? atl / ctl28 : nil

        return TrainingLoadProjection(
            atl: atl,
            ctl: ctl,
            tsb: ctl - atl,
            acwr: acwr,
            observedDays: observedDays,
            todayAvailability: today.availability
        )
    }

    private func legacyTrainingLoadHistory(_ input: EnergyBankInput) -> [DailyLoadObservation] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: input.asOf)
        return (input.strainHistory ?? []).enumerated().map { index, value in
            DailyLoadObservation(
                date: calendar.date(byAdding: .day, value: -(index + 1), to: day) ?? day,
                value: value,
                availability: .observed,
                reason: "兼容旧版数值历史"
            )
        }
    }

    private func legacyTodayLoadObservation(_ input: EnergyBankInput) -> DailyLoadObservation {
        DailyLoadObservation(
            date: Calendar.current.startOfDay(for: input.asOf),
            value: input.todayLoad,
            availability: input.todayLoad == nil ? .missing : (input.todayLoad == 0 ? .knownZero : .observed),
            reason: input.todayLoad == nil ? "今日负荷未提供" : nil
        )
    }

    private func ewma(_ values: [Double], lambda: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        // 暖启动：用初期（最多 7 个）样本的均值作种子，降低首值冷启动偏差。
        let warmupCount = min(7, values.count)
        let seed = values.prefix(warmupCount).reduce(0, +) / Double(warmupCount)
        var result = seed
        for value in values.dropFirst(warmupCount) {
            result = value * lambda + result * (1.0 - lambda)
        }
        return result
    }
}
