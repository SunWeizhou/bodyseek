import Foundation

public enum BevelScoringEngine {
    /// Computes deterministic physiological scores for every day in `rawDays`,
    /// guaranteeing zero future-data leakage (rolling 28d baseline excludes target day and future days).
    public static func computeWindow(
        rawDays: [DailyRawMetrics],
        sleepGoalMinutes: Int,
        referenceDate: Date,
        sourceLabel: String,
        isAuthorized: Bool,
        calendar: Calendar = .current
    ) -> BodySeekDashboardSnapshot {
        let refStart = calendar.startOfDay(for: referenceDate)
        let sorted = Dictionary(
            rawDays.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        .values
        .sorted { $0.date < $1.date }

        var computed: [DailyComputedDay] = []
        computed.reserveCapacity(sorted.count)

        for raw in sorted {
            let dayStart = calendar.startOfDay(for: raw.date)
            let baselineStart = calendar.date(byAdding: .day, value: -28, to: dayStart) ?? dayStart
            let priorDays = sorted.filter { item in
                let d = calendar.startOfDay(for: item.date)
                return d >= baselineStart && d < dayStart
            }
            computed.append(
                scoreDay(
                    raw,
                    priorDays: priorDays,
                    sleepGoalMinutes: sleepGoalMinutes,
                    calendar: calendar
                )
            )
        }

        let today = computed.last { calendar.isDate($0.date, inSameDayAs: refStart) }
            ?? computed.last
            ?? scoreDay(
                DailyRawMetrics(date: refStart, hasAuthorizedHealthData: isAuthorized),
                priorDays: [],
                sleepGoalMinutes: sleepGoalMinutes,
                calendar: calendar
            )

        let acwr = computeACWR(computedDays: computed, referenceDate: refStart, calendar: calendar)

        return BodySeekDashboardSnapshot(
            referenceDate: refStart,
            today: today,
            historyDays: computed,
            trainingLoad: acwr,
            sourceLabel: sourceLabel,
            lastUpdatedAt: Date(),
            isAuthorized: isAuthorized,
            scoreAlgorithmVersion: .scoreV2
        )
    }

    public static func scoreDay(
        _ raw: DailyRawMetrics,
        priorDays: [DailyRawMetrics],
        sleepGoalMinutes: Int,
        calendar: Calendar = .current
    ) -> DailyComputedDay {
        let dayStart = calendar.startOfDay(for: raw.date)
        let sleepScore = computeSleep(raw, priorDays: priorDays, goalMinutes: sleepGoalMinutes)
        let strainScore = computeStrain(raw, priorDays: priorDays)
        let recoveryScore = computeRecovery(raw, priorDays: priorDays, sleepScore: sleepScore)
        let stressScore = computeStress(raw, priorDays: priorDays, strain: strainScore)
        let energyScore = computeEnergy(
            recovery: recoveryScore,
            sleep: sleepScore,
            strain: strainScore,
            stress: stressScore,
            raw: raw
        )

        let energyCurve = buildEnergyCurve(
            dayStart: dayStart,
            energy: energyScore,
            recovery: recoveryScore,
            strain: strainScore,
            raw: raw,
            calendar: calendar
        )
        let stressTimeline = buildStressTimeline(
            raw: raw,
            stress: stressScore,
            calendar: calendar
        )

        let factual = buildFactualSummary(
            recovery: recoveryScore,
            sleep: sleepScore,
            strain: strainScore,
            raw: raw
        )
        let evidence = buildEvidenceSummary(
            recovery: recoveryScore,
            sleep: sleepScore,
            strain: strainScore,
            raw: raw
        )

        return DailyComputedDay(
            date: dayStart,
            dayKey: DayKey(date: raw.date, cutoverHour: 4, timeZone: calendar.timeZone),
            raw: raw,
            recovery: recoveryScore,
            sleep: sleepScore,
            strain: strainScore,
            stress: stressScore,
            energy: energyScore,
            energyCurve: energyCurve,
            stressTimeline: stressTimeline,
            factualSummary: factual,
            evidenceSummary: evidence,
            algorithmVersion: .scoreV2
        )
    }

    public static func trendSeries(
        for kind: MetricKind,
        horizon: TrendHorizon,
        days: [DailyComputedDay],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> TrendSeries {
        let end = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -(horizon.dayCount - 1), to: end) ?? end
        let byDay = Dictionary(
            days.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var points: [TrendPoint] = []
        points.reserveCapacity(horizon.dayCount)

        for offset in 0..<horizon.dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if let computed = byDay[date] {
                let s = computed.score(for: kind)
                points.append(TrendPoint(date: date, value: s.value, availability: s.availability))
            } else {
                points.append(TrendPoint(date: date, value: nil, availability: .missing(reason: "当天无数据")))
            }
        }

        let validValues = points.compactMap(\.value).map(Double.init)
        let baselineRange: ClosedRange<Double>? = if validValues.count >= 5,
            let q25 = percentile(validValues, 0.25),
            let q75 = percentile(validValues, 0.75) {
            q25...max(q25 + 1, q75)
        } else {
            nil
        }

        let medianVal = percentile(validValues, 0.5).map { Int($0.rounded()) }
        let delta: Int? = if validValues.count >= 6 {
            {
                let mid = validValues.count / 2
                let firstHalf = Array(validValues.prefix(mid))
                let secondHalf = Array(validValues.suffix(validValues.count - mid))
                guard let m1 = percentile(firstHalf, 0.5), let m2 = percentile(secondHalf, 0.5) else {
                    return nil
                }
                return Int((m2 - m1).rounded())
            }()
        } else {
            nil
        }

        let coveredDays = validValues.count
        let status: String
        if coveredDays == 0 {
            status = "暂无历史采样，连接 Apple 健康并佩戴手表后将自动绘制个人基线。"
        } else if let delta {
            if abs(delta) <= 2 {
                status = "\(kind.title)保持在个人常模带附近，近期波动平稳。"
            } else if delta > 2 {
                status = "后半程\(kind.title)较前半程上升 \(delta) 分。"
            } else {
                status = "后半程\(kind.title)较前半程回落 \(abs(delta)) 分。"
            }
        } else {
            status = "已积累 \(coveredDays)/\(horizon.dayCount) 天有效样本。"
        }

        return TrendSeries(
            kind: kind,
            horizon: horizon,
            points: points,
            baselineRange: baselineRange,
            coveredDays: coveredDays,
            totalDays: horizon.dayCount,
            median: medianVal,
            deltaFromFirstHalf: delta,
            statusSummary: status
        )
    }

    /// Calculates 7-day Acute vs 28-day Chronic Workload Ratio (ACWR) from strain scores + Watch TRIMP.
    public static func computeACWR(
        computedDays: [DailyComputedDay],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> TrainingLoadStatus {
        let refStart = calendar.startOfDay(for: referenceDate)
        let sevenStart = calendar.date(byAdding: .day, value: -6, to: refStart) ?? refStart
        let twentyEightStart = calendar.date(byAdding: .day, value: -27, to: refStart) ?? refStart

        func dailyLoad(_ day: DailyComputedDay) -> Double {
            let trimp = day.raw.workouts.compactMap { $0.heartRateZones?.trimpScore }.reduce(0, +)
            let strainVal = Double(day.strain.value ?? 0)
            return trimp > 0 ? trimp : strainVal
        }

        let last28 = computedDays.filter { $0.date >= twentyEightStart && $0.date <= refStart && $0.strain.value != nil }
        let last7 = last28.filter { $0.date >= sevenStart }

        let acute7d = last7.reduce(0.0) { $0 + dailyLoad($1) }
        let chronic28Total = last28.reduce(0.0) { $0 + dailyLoad($1) }

        guard last28.count >= 7, chronic28Total > 10 else {
            return TrainingLoadStatus(
                acute7dLoad: acute7d,
                chronic28dWeeklyAvg: 0,
                acwrRatio: nil,
                zone: .insufficientData
            )
        }

        let weeksCovered = max(1.0, Double(last28.count) / 7.0)
        let chronicWeeklyAvg = chronic28Total / weeksCovered
        let ratio = (acute7d / max(1.0, chronicWeeklyAvg))

        let zone: ACWRZone
        if ratio < 0.8 {
            zone = .undertraining
        } else if ratio <= 1.32 {
            zone = .sweetSpot
        } else {
            zone = .highRisk
        }

        return TrainingLoadStatus(
            acute7dLoad: (acute7d * 10).rounded() / 10,
            chronic28dWeeklyAvg: (chronicWeeklyAvg * 10).rounded() / 10,
            acwrRatio: (ratio * 100).rounded() / 100,
            zone: zone
        )
    }

    // MARK: - Metric Calculators

    private static func computeRecovery(
        _ raw: DailyRawMetrics,
        priorDays: [DailyRawMetrics],
        sleepScore: MetricScore
    ) -> MetricScore {
        guard raw.hrvMs != nil || raw.restingHeartRateBpm != nil else {
            let reason = raw.hasAuthorizedHealthData
                ? "暂无昨夜 HRV 与静息心率样本"
                : "需授权读取 Apple 健康中的 HRV 与静息心率"
            return MetricScore(
                kind: .recovery,
                value: nil,
                availability: .missing(reason: reason),
                badge: "待同步",
                subtitle: reason
            )
        }

        let baselineHRV = median(priorDays.compactMap(\.hrvMs))
        let baselineRHR = median(priorDays.compactMap(\.restingHeartRateBpm))

        var weightedSum = 0.0
        var totalWeight = 0.0
        var deltaPct: Double?
        var contributors: [MetricContributor] = []

        if let hrv = raw.hrvMs {
            let component: Double
            let deltaText: String?
            let impact: MetricContributor.Impact
            if let base = baselineHRV, base > 1 {
                let ratio = (hrv - base) / max(base * 0.22, 6.0)
                component = clamp(68.0 + ratio * 22.0, min: 15, max: 99)
                let diff = hrv - base
                deltaPct = diff
                let diffInt = Int(diff.rounded())
                deltaText = "基线 \(Int(base.rounded())) ms（\(diffInt >= 0 ? "+" : "")\(diffInt)）"
                impact = diff >= 3 ? .positive : (diff <= -3 ? .negative : .neutral)
            } else {
                component = clamp(30.0 + hrv * 0.9, min: 25, max: 92)
                deltaText = nil
                impact = .neutral
            }
            weightedSum += component * 0.52
            totalWeight += 0.52
            contributors.append(MetricContributor(
                id: "recovery-hrv",
                label: "夜间 HRV (SDNN)",
                valueText: "\(Int(hrv.rounded())) ms",
                baselineDeltaText: deltaText,
                weight: 0.52,
                impact: impact
            ))
        } else {
            contributors.append(MetricContributor(
                id: "recovery-hrv",
                label: "夜间 HRV (SDNN)",
                valueText: "--",
                weight: 0.52,
                impact: .missing
            ))
        }

        if let rhr = raw.restingHeartRateBpm {
            let component: Double
            let deltaText: String?
            let impact: MetricContributor.Impact
            if let base = baselineRHR, base > 1 {
                let diff = base - rhr
                component = clamp(68.0 + (diff / 5.0) * 20.0, min: 15, max: 98)
                let rawDiff = Int((rhr - base).rounded())
                deltaText = "基线 \(Int(base.rounded())) bpm（\(rawDiff >= 0 ? "+" : "")\(rawDiff)）"
                impact = rawDiff <= -2 ? .positive : (rawDiff >= 2 ? .negative : .neutral)
            } else {
                component = clamp(105.0 - rhr * 0.6, min: 25, max: 92)
                deltaText = nil
                impact = .neutral
            }
            weightedSum += component * 0.30
            totalWeight += 0.30
            contributors.append(MetricContributor(
                id: "recovery-rhr",
                label: "静息心率",
                valueText: "\(Int(rhr.rounded())) bpm",
                baselineDeltaText: deltaText,
                weight: 0.30,
                impact: impact
            ))
        } else {
            contributors.append(MetricContributor(
                id: "recovery-rhr",
                label: "静息心率",
                valueText: "--",
                weight: 0.30,
                impact: .missing
            ))
        }

        if let sleepVal = sleepScore.value {
            weightedSum += Double(sleepVal) * 0.18
            totalWeight += 0.18
            contributors.append(MetricContributor(
                id: "recovery-sleep",
                label: "昨夜睡眠支撑",
                valueText: "\(sleepVal) 分",
                baselineDeltaText: sleepScore.subtitle,
                weight: 0.18,
                impact: sleepVal >= 75 ? .positive : (sleepVal < 55 ? .negative : .neutral)
            ))
        } else {
            contributors.append(MetricContributor(
                id: "recovery-sleep",
                label: "昨夜睡眠支撑",
                valueText: "--",
                weight: 0.18,
                impact: .missing
            ))
        }

        let final = Int(clamp(weightedSum / max(totalWeight, 0.01), min: 1, max: 100).rounded())
        let badge = final >= 75 ? "状态充沛" : (final >= 50 ? "处于平时" : "偏疲劳")
        let subtitle: String
        if let hrv = raw.hrvMs, let base = baselineHRV {
            let diff = Int((hrv - base).rounded())
            let sign = diff >= 0 ? "+" : ""
            subtitle = "HRV \(Int(hrv.rounded())) ms（\(sign)\(diff)）"
        } else if let hrv = raw.hrvMs {
            subtitle = "HRV \(Int(hrv.rounded())) ms"
        } else if let rhr = raw.restingHeartRateBpm {
            subtitle = "静息心率 \(Int(rhr.rounded())) bpm"
        } else {
            subtitle = badge
        }

        return MetricScore(
            kind: .recovery,
            value: final,
            availability: .available,
            badge: badge,
            subtitle: subtitle,
            baselineDelta: deltaPct.map { Int($0.rounded()) },
            algorithmVersion: .scoreV2,
            contributors: contributors
        )
    }

    private static func computeSleep(
        _ raw: DailyRawMetrics,
        priorDays: [DailyRawMetrics],
        goalMinutes: Int
    ) -> MetricScore {
        guard let asleep = raw.sleepAsleepMinutes, asleep > 0 else {
            let reason = raw.hasAuthorizedHealthData ? "昨晚暂无睡眠分段数据" : "需授权读取 Apple 健康中的睡眠分析"
            return MetricScore(
                kind: .sleep,
                value: nil,
                availability: .missing(reason: reason),
                badge: "待同步",
                subtitle: reason
            )
        }

        let target = max(300, Double(goalMinutes))
        let durationRatio = clamp(Double(asleep) / target, min: 0, max: 1.08)
        let durationScore = clamp(durationRatio * 90.0, min: 20, max: 96)

        let deep = Double(raw.deepMinutes ?? 0)
        let rem = Double(raw.remMinutes ?? 0)
        let hasStages = (raw.deepMinutes ?? 0) + (raw.remMinutes ?? 0) + (raw.coreMinutes ?? 0) > 0
        let restorativeRatio = hasStages ? (deep + rem) / Double(max(asleep, 1)) : 0.36
        let stageScore = clamp((restorativeRatio / 0.42) * 90.0, min: 35, max: 98)

        let inBed = Double(raw.sleepInBedMinutes ?? (asleep + (raw.awakeMinutes ?? 15)))
        let efficiency = clamp(Double(asleep) / max(inBed, Double(asleep)), min: 0.55, max: 1.0)
        let continuityScore = clamp(((efficiency - 0.65) / 0.32) * 92.0, min: 35, max: 98)

        let total = Int(clamp(durationScore * 0.55 + stageScore * 0.25 + continuityScore * 0.20, min: 1, max: 100).rounded())
        let h = asleep / 60
        let m = asleep % 60
        let baselineSleep = median(priorDays.compactMap(\.sleepAsleepMinutes).map(Double.init))
        let delta = baselineSleep.map { Int((Double(asleep) - $0).rounded()) }
        let badge = total >= 80 ? "睡眠充分" : (total >= 60 ? "整体平稳" : "睡得偏短")

        let contributors: [MetricContributor] = [
            MetricContributor(
                id: "sleep-duration",
                label: "实际睡眠时长",
                valueText: "\(h)小时\(m)分",
                baselineDeltaText: delta.map { "\($0 >= 0 ? "+" : "")\($0) 分钟 vs 基线" },
                weight: 0.55,
                impact: Double(asleep) >= target * 0.92 ? .positive : (Double(asleep) < target * 0.78 ? .negative : .neutral)
            ),
            MetricContributor(
                id: "sleep-stages",
                label: "深睡 + REM 修复比例",
                valueText: hasStages ? "\(Int((restorativeRatio * 100).rounded()))%" : "未拆分阶段",
                weight: 0.25,
                impact: hasStages ? (restorativeRatio >= 0.38 ? .positive : .neutral) : .missing
            ),
            MetricContributor(
                id: "sleep-efficiency",
                label: "在床连续性",
                valueText: "\(Int((efficiency * 100).rounded()))%",
                weight: 0.20,
                impact: efficiency >= 0.88 ? .positive : (efficiency < 0.78 ? .negative : .neutral)
            ),
        ]

        return MetricScore(
            kind: .sleep,
            value: total,
            availability: .available,
            badge: badge,
            subtitle: "\(h)小时\(m)分",
            baselineDelta: delta,
            algorithmVersion: .scoreV2,
            contributors: contributors
        )
    }

    private static func computeStrain(
        _ raw: DailyRawMetrics,
        priorDays: [DailyRawMetrics]
    ) -> MetricScore {
        let energy = raw.activeEnergyKcal
        let exercise = raw.exerciseMinutes
        let steps = raw.steps

        guard energy != nil || exercise != nil || !raw.workouts.isEmpty || steps != nil else {
            let reason = raw.hasAuthorizedHealthData ? "今日暂无活动负荷采样" : "需授权读取活动能量与锻炼记录"
            return MetricScore(
                kind: .strain,
                value: nil,
                availability: .missing(reason: reason),
                badge: "待同步",
                subtitle: reason
            )
        }

        let kcal = energy ?? Double(raw.workouts.reduce(0.0) { $0 + $1.activeEnergyKcal })
        let exMin = Double(exercise ?? raw.workouts.reduce(0) { $0 + $1.durationMinutes })

        if kcal <= 10 && exMin == 0 && raw.workouts.isEmpty && (steps ?? 0) < 100 {
            return MetricScore(
                kind: .strain,
                value: 0,
                availability: .knownZero(reason: "今日尚未产生明显训练消耗"),
                badge: "休息中",
                subtitle: "尚无训练负荷",
                baselineDelta: nil
            )
        }

        let baselineKcal = max(320.0, median(priorDays.compactMap(\.activeEnergyKcal)) ?? 480.0)
        let energyLoad = clamp((kcal / (baselineKcal * 1.35)) * 75.0, min: 0, max: 85)
        let exerciseBonus = clamp((exMin / 75.0) * 35.0, min: 0, max: 35)
        let rawStrain = clamp(energyLoad * 0.68 + exerciseBonus, min: 1, max: 100)
        let final = Int(rawStrain.rounded())

        let badge = final >= 70 ? "高强度输出" : (final >= 40 ? "中等负荷" : "日常活动")
        let subtitle: String
        if !raw.workouts.isEmpty {
            subtitle = "\(raw.workouts.count)次训练 · \(Int(kcal.rounded())) kcal"
        } else {
            subtitle = "\(badge) · \(Int(kcal.rounded())) kcal"
        }

        let contributors: [MetricContributor] = [
            MetricContributor(
                id: "strain-energy",
                label: "动态热量消耗",
                valueText: "\(Int(kcal.rounded())) kcal",
                baselineDeltaText: "基线 \(Int(baselineKcal.rounded())) kcal",
                weight: 0.68,
                impact: kcal >= baselineKcal ? .positive : .neutral
            ),
            MetricContributor(
                id: "strain-exercise",
                label: "锻炼时长 / 课程",
                valueText: "\(Int(exMin.rounded())) 分钟 · \(raw.workouts.count) 次",
                impact: !raw.workouts.isEmpty || exMin >= 30 ? .positive : .neutral
            ),
        ]

        return MetricScore(
            kind: .strain,
            value: final,
            availability: .available,
            badge: badge,
            subtitle: subtitle,
            algorithmVersion: .scoreV2,
            contributors: contributors
        )
    }

    private static func computeStress(
        _ raw: DailyRawMetrics,
        priorDays: [DailyRawMetrics],
        strain: MetricScore
    ) -> MetricScore {
        guard raw.restingHeartRateBpm != nil || raw.daytimeMeanHeartRateBpm != nil || raw.hrvMs != nil else {
            return MetricScore(
                kind: .stress,
                value: nil,
                availability: .missing(reason: "缺少心率或 HRV 样本，暂不估算压力"),
                badge: "待同步",
                subtitle: "需心率采样"
            )
        }

        let baselineHRV = median(priorDays.compactMap(\.hrvMs)) ?? raw.hrvMs ?? 55
        let baselineRHR = median(priorDays.compactMap(\.restingHeartRateBpm)) ?? raw.restingHeartRateBpm ?? 58

        var components: [Double] = []
        var contributors: [MetricContributor] = []
        if let meanHR = raw.daytimeMeanHeartRateBpm {
            let hrElevation = max(0, meanHR - baselineRHR)
            components.append(clamp((hrElevation / 32.0) * 78.0, min: 12, max: 95))
            contributors.append(MetricContributor(
                id: "stress-hr-elevation",
                label: "日间心率相对静息偏离",
                valueText: "\(Int(meanHR.rounded())) bpm",
                baselineDeltaText: "+\(Int(hrElevation.rounded())) bpm",
                impact: hrElevation >= 20 ? .negative : .neutral
            ))
        }
        if let hrv = raw.hrvMs, baselineHRV > 1 {
            let drop = (baselineHRV - hrv) / baselineHRV
            components.append(clamp(44.0 + drop * 65.0, min: 12, max: 92))
            contributors.append(MetricContributor(
                id: "stress-hrv-drop",
                label: "HRV 自主神经抑制",
                valueText: "\(Int(hrv.rounded())) ms",
                baselineDeltaText: "基线 \(Int(baselineHRV.rounded())) ms",
                impact: drop > 0.12 ? .negative : .positive
            ))
        }
        if let strainVal = strain.value {
            components.append(clamp(Double(strainVal) * 0.65 + 15.0, min: 10, max: 88))
            contributors.append(MetricContributor(
                id: "stress-strain-load",
                label: "当日运动负荷牵引",
                valueText: "\(strainVal) 分",
                impact: .neutral
            ))
        }

        let value = Int(clamp(components.reduce(0, +) / Double(max(components.count, 1)), min: 5, max: 98).rounded())
        let badge = value >= 65 ? "压力偏高" : (value >= 35 ? "负荷可控" : "放松平稳")
        return MetricScore(
            kind: .stress,
            value: value,
            availability: .available,
            badge: badge,
            subtitle: badge,
            algorithmVersion: .scoreV2,
            contributors: contributors
        )
    }

    private static func computeEnergy(
        recovery: MetricScore,
        sleep: MetricScore,
        strain: MetricScore,
        stress: MetricScore,
        raw: DailyRawMetrics
    ) -> MetricScore {
        guard recovery.value != nil || sleep.value != nil else {
            return MetricScore(
                kind: .energy,
                value: nil,
                availability: .missing(reason: "需要恢复或睡眠数据才能计算能量电量"),
                badge: "待同步",
                subtitle: "缺少晨起基础数据"
            )
        }

        let rec = Double(recovery.value ?? sleep.value ?? 60)
        let slp = Double(sleep.value ?? recovery.value ?? 65)
        let morningCharge = clamp(rec * 0.64 + slp * 0.36, min: 20, max: 100)

        let strainDrain = Double(strain.value ?? 0) * 0.42
        let stressDrain = Double(stress.value ?? 25) * 0.16
        let current = Int(clamp(morningCharge - strainDrain - stressDrain, min: 8, max: 99).rounded())
        let morningInt = Int(morningCharge.rounded())
        let badge = current >= 65 ? "电量充足" : (current >= 38 ? "节奏均衡" : "建议省电")
        let contributors: [MetricContributor] = [
            MetricContributor(
                id: "energy-morning-charge",
                label: "晨起储备电量",
                valueText: "\(morningInt)",
                weight: 1.0,
                impact: morningInt >= 70 ? .positive : .neutral
            ),
            MetricContributor(
                id: "energy-strain-drain",
                label: "活动负荷消耗",
                valueText: "-\(Int(strainDrain.rounded()))",
                impact: strainDrain >= 25 ? .negative : .neutral
            ),
            MetricContributor(
                id: "energy-stress-drain",
                label: "生理压力耗电",
                valueText: "-\(Int(stressDrain.rounded()))",
                impact: stressDrain >= 10 ? .negative : .neutral
            ),
        ]

        return MetricScore(
            kind: .energy,
            value: current,
            availability: .available,
            badge: badge,
            subtitle: "晨起 \(morningInt)",
            baselineDelta: raw.steps != nil ? (current - morningInt) : nil,
            algorithmVersion: .scoreV2,
            contributors: contributors
        )
    }

    /// Generates an authentic circadian Body Battery waveform (overnight charging rise, workout drop, daytime drain).
    private static func buildEnergyCurve(
        dayStart: Date,
        energy: MetricScore,
        recovery: MetricScore,
        strain: MetricScore,
        raw: DailyRawMetrics,
        calendar: Calendar
    ) -> [EnergyCurvePoint] {
        guard let currentVal = energy.value else { return [] }
        let morningPeak = clamp(Double(recovery.value ?? currentVal) * 0.68 + 26.0, min: 40, max: 98)
        let workoutHour = raw.workouts.first.map { calendar.component(.hour, from: $0.startDate) }
        let hours = [0, 3, 6, 8, 10, 12, 14, 16, 18, 20, 22]

        var prev = max(18.0, morningPeak * 0.45)
        return hours.map { hour in
            let v: Double
            if hour <= 6 {
                // Overnight sleep charging phase
                let p = Double(hour) / 6.0
                v = prev + (morningPeak - prev) * p
            } else {
                let p = Double(hour - 6) / 16.0
                var target = morningPeak - (morningPeak - Double(currentVal)) * pow(p, 0.9)
                if let wh = workoutHour, abs(hour - wh) <= 2 {
                    target -= (hour >= wh ? 9.0 : 0.0)
                } else if hour == 13 || hour == 14 {
                    // Post-lunch gentle plateau
                    target += 3.5
                }
                let _ = strain
                v = target
            }
            let clamped = Int(clamp(v, min: 6, max: 100).rounded())
            prev = Double(clamped)
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart
            return EnergyCurvePoint(hour: hour, value: clamped, date: date)
        }
    }

    /// Generates 12 two-hour autonomic stress bins across the 24-hour cycle anchored by real workout & rest periods.
    private static func buildStressTimeline(
        raw: DailyRawMetrics,
        stress: MetricScore,
        calendar: Calendar
    ) -> [StressTimelineBin] {
        guard let baseStress = stress.value else { return [] }
        let workoutHour = raw.workouts.first.map { calendar.component(.hour, from: $0.startDate) }
        let hours = stride(from: 0, through: 22, by: 2)

        return hours.map { hour in
            let binValue: Int
            if hour < 6 {
                // Restorative sleep hours stay low unless stressed
                binValue = Int(clamp(Double(baseStress) * 0.35 + Double(hour), min: 10, max: 40))
            } else if let wh = workoutHour, abs(hour - wh) <= 1 {
                binValue = Int(clamp(Double(baseStress) * 1.45 + 12, min: 55, max: 96))
            } else if hour >= 9 && hour <= 18 {
                let midWave = sin(Double(hour) * 0.65) * 12.0
                binValue = Int(clamp(Double(baseStress) * 0.95 + midWave, min: 22, max: 85))
            } else {
                binValue = Int(clamp(Double(baseStress) * 0.58, min: 14, max: 60))
            }

            let level: StressLevel
            if binValue < 28 {
                level = .rest
            } else if binValue < 48 {
                level = .low
            } else if binValue < 70 {
                level = .medium
            } else {
                level = .elevated
            }
            return StressTimelineBin(hour: hour, value: binValue, level: level)
        }
    }

    private static func buildFactualSummary(
        recovery: MetricScore,
        sleep: MetricScore,
        strain: MetricScore,
        raw: DailyRawMetrics
    ) -> String {
        guard let rec = recovery.value else {
            return raw.hasAuthorizedHealthData
                ? "正在等待今天的第一组夜间恢复样本。"
                : "授权读取 Apple 健康后，BodySeek 会自动基于个人 28 天基线进行评估。"
        }
        var parts = ["恢复 \(rec)（\(recovery.badge)）"]
        if sleep.value != nil { parts.append("睡眠 \(sleep.subtitle)") }
        if let st = strain.value { parts.append("今日负荷 \(st)") }
        return parts.joined(separator: " · ")
    }

    private static func buildEvidenceSummary(
        recovery: MetricScore,
        sleep: MetricScore,
        strain: MetricScore,
        raw: DailyRawMetrics
    ) -> String {
        var parts: [String] = []
        if let hrv = raw.hrvMs { parts.append("HRV \(Int(hrv.rounded())) ms") }
        if let rhr = raw.restingHeartRateBpm { parts.append("静息心率 \(Int(rhr.rounded())) bpm") }
        if sleep.value != nil { parts.append("睡眠 \(sleep.subtitle)") }
        if let st = strain.value { parts.append("负荷 \(st)") }
        return parts.isEmpty ? "暂无可归因生理采样" : parts.joined(separator: " · ")
    }

    // MARK: - Math Helpers

    public static func median(_ values: [Double]) -> Double? {
        percentile(values, 0.5)
    }

    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let pos = clamp(p, min: 0, max: 1) * Double(sorted.count - 1)
        let low = Int(floor(pos))
        let high = Int(ceil(pos))
        if low == high { return sorted[low] }
        let weight = pos - Double(low)
        return sorted[low] * (1 - weight) + sorted[high] * weight
    }

    private static func clamp(_ val: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(upper, Swift.max(lower, val))
    }
}
