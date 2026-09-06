import SwiftUI

struct MetricRecommendationPresentation: Equatable {
    var title: String
    var detail: String
    var evidence: String
    var symbol: String
}

enum MetricRecommendationPolicy {
    static func make(
        metric: VelaMetricDetailView.MetricType,
        dashboard: DashboardSummary,
        valueText: String,
        hasData: Bool
    ) -> MetricRecommendationPresentation {
        guard hasData else {
            return MetricRecommendationPresentation(
                title: "先补齐数据，再做判断",
                detail: "当前没有足够的真实读数。同步 Apple 健康后，Vela 才会给出这个指标的趋势和行动建议。",
                evidence: "当前值 -- · 不使用估算值",
                symbol: "arrow.triangle.2.circlepath"
            )
        }

        switch metric {
        case .recovery:
            let score = dashboard.recovery.score
            if score < 45 {
                return recommendation("恢复优先，降低训练成本", "避免追求训练量；如要训练，以低强度、短时长和动作质量为上限。", valueText, "heart.text.square")
            }
            if score < 75 {
                return recommendation("可以训练，但要保留余力", "按计划的保守版本执行，保留 2 次左右余力，并观察热身后的主观状态。", valueText, "gauge.with.dots.needle.50percent")
            }
            return recommendation("恢复信号支持计划训练", "可以执行计划，同时仍以动作质量、疼痛和异常不适作为即时停止条件。", valueText, "checkmark.circle")

        case .sleep:
            let score = dashboard.sleepScore.score
            if score < 60 {
                return recommendation("今晚优先修复睡眠", "今天避免过晚高强度训练和过晚进食，固定上床时间，给睡眠留出完整窗口。", valueText, "moon.zzz")
            }
            if score < 80 {
                return recommendation("保护今晚的睡眠节奏", "睡眠基本可用但仍有改进空间；保持规律入睡，并减少临睡前额外刺激。", valueText, "bed.double")
            }
            return recommendation("保持当前睡眠节奏", "当前睡眠信号较好，优先维持相近的入睡、起床和睡眠时长。", valueText, "moon.stars")

        case .strain:
            let score = dashboard.strain.score
            guard let range = dashboard.strain.explicitRecommendedRange else {
                return recommendation("个体化负荷边界仍在建立", "先按身体感受与既有计划安排活动。", "负荷 \(valueText)", "scope")
            }
            let lower = range.lowerBound
            let upper = range.upperBound
            if score > upper {
                return recommendation("今天停止继续加量", "当前负荷已经超过参考区间；后续活动以轻松完成和恢复为主。", "负荷 \(valueText) · 参考 \(Int(lower))–\(Int(upper))", "stop.circle")
            }
            if score < lower {
                return recommendation("负荷低于今日参考区间", "若恢复和睡眠允许，可按计划完成活动；不需为了数字追加负荷。", "负荷 \(valueText) · 参考 \(Int(lower))–\(Int(upper))", "figure.walk")
            }
            return recommendation("负荷位于参考区间", "无需为了数字继续加量；完成计划后把重点转向补水、进食和恢复。", "负荷 \(valueText) · 参考 \(Int(lower))–\(Int(upper))", "scope")

        case .stress:
            let score = dashboard.stress.stressIndex
            if score >= 70 {
                return recommendation("安排一个低刺激恢复窗口", "先做 5–10 分钟安静呼吸或轻松步行，再决定是否继续高要求任务或训练。", valueText, "wind")
            }
            if score >= 45 {
                return recommendation("减少额外刺激", "当前压力信号偏高；把高认知负荷、咖啡因和高强度训练错开。", valueText, "waveform.path.ecg")
            }
            return recommendation("压力信号处于可控区间", "保持当前节奏，并结合连续趋势判断，而不是追逐单次低值。", valueText, "leaf")

        case .energy:
            let score = dashboard.energy.currentEnergy
            if score < 35 {
                return recommendation("保留能量，避免透支", "优先补水、规律进食和低强度活动；高强度训练应服从恢复与睡眠建议。", valueText, "battery.25percent")
            }
            if score < 70 {
                return recommendation("把能量留给最重要的任务", "当前储备适中，先完成优先训练或工作，减少不必要的额外消耗。", valueText, "battery.50percent")
            }
            return recommendation("能量储备支持主要计划", "可以执行今天的主要任务，但不要把较高能量分理解为无限负荷许可。", valueText, "battery.100percent")

        case .hrv:
            return recommendation("围绕个人基线观察变化", "HRV 个体差异很大；连续偏离个人基线比与他人比较更有意义。", valueText, "waveform.path.ecg")
        case .rhr:
            return recommendation("关注连续偏离，而非单次波动", "结合 HRV、睡眠、体温和主观状态观察静息心率趋势。", valueText, "heart")
        case .weight, .bodyFat:
            return recommendation("用 4 周趋势判断变化", "尽量在相近时间和条件下测量；不要根据单日水分波动调整训练或饮食。", valueText, "chart.line.uptrend.xyaxis")
        case .respiratoryRate:
            return recommendation("与夜间个人基线比较", "连续偏离更值得关注；同时查看睡眠、体温与主观不适记录。", valueText, "lungs")
        case .bloodOxygen:
            return recommendation("结合趋势和测量条件解读", "单次腕上读数可能受佩戴和运动影响；持续异常或伴随不适时应寻求专业意见。", valueText, "drop")
        case .steps:
            return recommendation("用轻松步行补足日常活动", "把步数分散到全天，不必在高负荷或低恢复时为了目标集中补步。", valueText, "shoeprints.fill")
        case .activeCalories:
            return recommendation("把活动消耗放回负荷背景", "活动热量是估算值；结合训练负荷、恢复和饮食目标判断，不单独追高。", valueText, "flame")
        case .activeMinutes:
            return recommendation("优先稳定累计，而不是一次补齐", "将活跃时间分散到一周，并让高强度时段服从恢复与睡眠状态。", valueText, "clock.badge.checkmark")
        }
    }

    private static func recommendation(
        _ title: String,
        _ detail: String,
        _ evidence: String,
        _ symbol: String
    ) -> MetricRecommendationPresentation {
        MetricRecommendationPresentation(
            title: title,
            detail: detail,
            evidence: evidence,
            symbol: symbol
        )
    }
}

enum EvidenceFormat {
    case integer(String)
    case decimal(String)
    case signedDecimal(String)
}


extension VelaMetricDetailView {
    var metricRecommendation: MetricRecommendationPresentation {
        MetricRecommendationPolicy.make(
            metric: metric,
            dashboard: dashboard,
            valueText: dynamicValueText,
            hasData: hasMetricData
        )
    }

    var currentMetricResult: MetricResult? {
        switch metric {
        case .recovery, .hrv, .rhr: return dashboard.recovery
        case .sleep: return dashboard.sleepScore
        case .strain, .steps, .activeCalories, .activeMinutes: return dashboard.strain
        case .stress: return dashboard.stress
        case .energy: return dashboard.energy
        case .weight, .bodyFat, .respiratoryRate, .bloodOxygen: return nil
        }
    }

    var metricDirectionLabel: String {
        if let result = currentMetricResult, metric.isScoredHealthDomain {
            switch result.direction {
            case .higherIsBetter: return "越高越好"
            case .higherIsLoad: return "越高负荷越大"
            case .higherNeedsAttention: return "越高越需关注"
            }
        }
        switch metric {
        case .hrv: return "相对基线解读"
        case .rhr, .respiratoryRate, .bloodOxygen: return "偏离基线更重要"
        case .weight, .bodyFat: return "关注长期趋势"
        case .steps, .activeCalories, .activeMinutes: return "结合个人目标"
        default: return "结合趋势解读"
        }
    }

    var metricConfidenceLabel: String {
        guard hasMetricData else { return "不可用" }
        guard let result = currentMetricResult, metric.isScoredHealthDomain else {
            return "原始读数"
        }
        switch result.confidence {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var metricCoverageLabel: String {
        guard hasMetricData else { return "暂无数据" }
        guard let result = currentMetricResult, metric.isScoredHealthDomain else {
            return "今日可用"
        }
        switch result.dataCoverage {
        case .unavailable: return "不可用"
        case .partial: return "部分"
        case .substantial: return "主要数据"
        case .complete: return "完整"
        }
    }

    var metricUpdatedAtLabel: String {
        if observedAtForMetric == nil,
           hasMetricData,
           [.hrv, .rhr, .bloodOxygen].contains(metric) {
            return "观测时间未知"
        }
        let date = observedAtForMetric ?? currentMetricResult?.lastUpdated ?? effectiveDate
        let timestamp = date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "zh_CN"))
        )
        return "更新于 \(timestamp)"
    }

    private var observedAtForMetric: Date? {
        switch metric {
        case .hrv: return dashboard.recoveryMetrics.hrvObservedAt
        case .rhr: return dashboard.recoveryMetrics.rhrObservedAt
        case .bloodOxygen: return dashboard.extendedMetrics.oxygenSaturationObservedAt
        default: return nil
        }
    }

    var metricMissingSummary: String? {
        guard hasMetricData else { return "缺少可用读数；当前页面不会用 0 或默认值代替。" }
        guard let result = currentMetricResult,
              metric.isScoredHealthDomain,
              !result.missingInputs.isEmpty else { return nil }
        let labels = result.missingInputs.prefix(3).map(displayMissingInput)
        return "仍缺少：\(labels.joined(separator: "、"))。当前结果已降低证据覆盖度。"
    }

    private func displayMissingInput(_ input: String) -> String {
        let normalized = input.lowercased()
        if normalized.contains("hrv") { return "HRV" }
        if normalized.contains("rhr") || normalized.contains("resting") { return "静息心率" }
        if normalized.contains("sleep") || normalized.contains("bedtime") || normalized.contains("wake") { return "完整睡眠" }
        if normalized.contains("workout") { return "训练记录" }
        if normalized.contains("step") { return "步数" }
        if normalized.contains("energy") { return "活动能量" }
        if normalized.contains("resp") { return "呼吸率" }
        if normalized.contains("temp") { return "腕温" }
        if normalized.contains("spo2") || normalized.contains("oxygen") { return "血氧" }
        return "部分输入"
    }

    var displayDateText: String {
        let dateToUse = selectedPoint?.date ?? effectiveDate
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        if selectedRange == .threeYears {
            formatter.dateFormat = "yyyy年M月"
        } else {
            formatter.dateFormat = Calendar.current.isDateInToday(dateToUse) ? "今天，M月d日" : "M月d日"
        }
        return formatter.string(from: dateToUse)
    }

    var chartPoints: [ChartPoint] {
        let snapshots = dailyRecords.map { $0.toSnapshot() }
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: effectiveDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        let start = calendar.date(byAdding: .day, value: -selectedRange.days, to: end) ?? end
        
        let filtered = snapshots
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
            
        let points: [ChartPoint] = filtered.compactMap { snap -> ChartPoint? in
            guard let val = metricValue(for: snap) else { return nil }
            return ChartPoint(date: snap.date, value: val)
        }

        guard selectedRange == .threeYears else { return points }
        let monthly: [Date: [ChartPoint]] = Dictionary(grouping: points) { point in
            calendar.date(
                from: calendar.dateComponents([.year, .month], from: point.date)
            ) ?? calendar.startOfDay(for: point.date)
        }
        var monthlyPoints: [ChartPoint] = []
        monthlyPoints.reserveCapacity(monthly.count)
        for (month, values) in monthly {
            let sum = values.reduce(0.0) { partial, point in
                partial + point.value
            }
            monthlyPoints.append(ChartPoint(
                date: month,
                value: sum / Double(values.count)
            ))
        }
        return monthlyPoints.sorted { $0.date < $1.date }
    }

    func metricValue(for snapshot: DailyHealthSnapshot) -> Double? {
        switch metric {
        case .strain: return snapshot.strainScore
        case .recovery: return snapshot.recoveryScore
        case .sleep: return snapshot.sleepScore
        case .stress: return snapshot.stressIndex
        case .energy: return snapshot.currentEnergy ?? snapshot.energyBank
        case .hrv: return snapshot.hrvAverage
        case .rhr: return snapshot.restingHeartRate
        case .weight: return snapshot.bodyWeight
        case .bodyFat: return snapshot.bodyFatPercent
        case .respiratoryRate: return snapshot.respiratoryRate
        case .bloodOxygen: return snapshot.oxygenSaturation
        case .steps: return snapshot.steps
        case .activeCalories: return snapshot.activeCalories
        case .activeMinutes: return snapshot.activeMinutes ?? snapshot.workoutDuration
        }
    }

    var selectedPoint: ChartPoint? {
        guard let rawSelectedDate else { return nil }
        return chartPoints.min(by: {
            abs($0.date.timeIntervalSince(rawSelectedDate)) < abs($1.date.timeIntervalSince(rawSelectedDate))
        })
    }

    func formattedValue(_ score: Double) -> String {
        switch metric {
        case .hrv:
            return "\(Int(score)) ms"
        case .rhr:
            return "\(Int(score)) bpm"
        case .stress:
            return "\(Int(score))"
        case .weight:
            return String(format: "%.1f kg", score)
        case .bodyFat:
            return String(format: "%.1f%%", score)
        case .bloodOxygen:
            return "\(Int(score))%"
        case .respiratoryRate:
            return "\(Int(score))/min"
        case .steps:
            return "\(Int(score))"
        case .activeCalories:
            return "\(Int(score)) kcal"
        case .activeMinutes:
            return "\(Int(score))m"
        default:
            return VelaMinimalFormatting.roundedPercentage(score)
        }
    }

    var isBarChart: Bool {
        switch metric {
        case .steps, .activeCalories, .activeMinutes, .strain:
            return true
        default:
            return false
        }
    }

    var selectedDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(effectiveDate) ? "今天，M月d日" : "M月d日"
        return formatter.string(from: effectiveDate)
    }

    var selectedFullDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: effectiveDate)
    }

    var metricShareText: String {
        "\(selectedFullDateText) Vela \(navTitle): \(dynamicValueText) (\(metricSubtitle))"
    }

    var metricInfoText: String {
        "该页面展示由 Apple 健康数据和本地评分引擎生成的\(navTitle)摘要。暂无数据时不会展示估算值。"
    }

    var navTitle: String {
        switch metric {
        case .strain:   "耗力"
        case .recovery: "恢复"
        case .sleep:    "睡眠"
        case .stress:   "压力"
        case .energy:   "能量"
        case .hrv:      "心率变异性"
        case .rhr:      "静息心率"
        case .weight:           "体重"
        case .bodyFat:          "体脂"
        case .respiratoryRate:  "呼吸率"
        case .bloodOxygen:      "血氧"
        case .steps:            "今日步数"
        case .activeCalories:   "活动消耗"
        case .activeMinutes:    "活跃时长"
        }
    }

    var metricColor: Color {
        // Core-domain colors provide stable identity across Today, Trends and
        // details. State is expressed separately through labels and markers.
        switch metric {
        case .strain: return VelaTheme.strainColor
        case .recovery: return VelaTheme.recoveryColor
        case .sleep: return VelaTheme.sleepColor
        case .stress: return VelaTheme.stressColor
        case .energy: return VelaTheme.energyColor
        case .hrv, .rhr, .respiratoryRate, .bloodOxygen, .weight, .bodyFat,
             .steps, .activeCalories, .activeMinutes:
            return VelaTheme.brand
        }
    }

    private func dashboardResult(for metric: MetricType) -> MetricResult {
        switch metric {
        case .strain: return dashboard.strain
        case .recovery: return dashboard.recovery
        case .sleep: return dashboard.sleepScore
        case .stress: return dashboard.stress
        case .energy: return dashboard.energy
        default: return dashboard.recovery
        }
    }

    var dynamicScore: Double {
        if let selectedPoint {
            return selectedPoint.value
        }
        switch metric {
        case .strain:
            return dashboard.strain.hasData ? dashboard.strain.score : 0
        case .recovery:
            return dashboard.recovery.hasData ? dashboard.recovery.score : 0
        case .sleep:
            return dashboard.sleepScore.hasData ? dashboard.sleepScore.score : 0
        case .stress:
            return dashboard.stress.hasData ? dashboard.stress.stressIndex : 0
        case .energy:
            return dashboard.energy.hasData ? dashboard.energy.currentEnergy : 0
        case .hrv:
            return dashboard.recoveryMetrics.hrvMilliseconds ?? 0
        case .rhr:
            return dashboard.recoveryMetrics.restingHeartRate ?? 0
        case .weight:
            return dashboard.bodyMetrics.weightKilograms ?? 0
        case .bodyFat:
            return dashboard.bodyMetrics.bodyFatPercentage ?? 0
        case .respiratoryRate:
            return dashboard.recoveryMetrics.respiratoryRate ?? 0
        case .bloodOxygen:
            return dashboard.extendedMetrics.oxygenSaturation ?? 0
        case .steps:
            return dashboard.strain.metrics["steps_raw"] ?? 0
        case .activeCalories:
            return dashboard.strain.metrics["active_energy_raw"] ?? 0
        case .activeMinutes:
            return dashboard.strain.metrics["exercise_minutes_raw"] ?? 0
        }
    }

    var dynamicValueText: String {
        guard hasMetricData else { return "--" }
        switch metric {
        case .hrv:
            return "\(Int(dynamicScore)) ms"
        case .rhr:
            return "\(Int(dynamicScore)) bpm"
        case .stress:
            return "\(Int(dynamicScore))"
        case .weight:
            return String(format: "%.1f kg", dynamicScore)
        case .bodyFat:
            return String(format: "%.1f%%", dynamicScore)
        case .bloodOxygen:
            return "\(Int(dynamicScore))%"
        case .respiratoryRate:
            return "\(Int(dynamicScore))/min"
        case .steps:
            return "\(Int(dynamicScore))"
        case .activeCalories:
            return "\(Int(dynamicScore)) kcal"
        case .activeMinutes:
            return "\(Int(dynamicScore))m"
        default:
            return VelaMinimalFormatting.roundedPercentage(dynamicScore)
        }
    }

    var metricSubtitle: String {
        guard hasMetricData else { return "暂无数据" }
        switch metric {
        case .strain:
            guard let range = dashboard.strain.explicitRecommendedRange else {
                return "参考区间建立中"
            }
            if dynamicScore < range.lowerBound { return "低于参考区间" }
            if dynamicScore > range.upperBound { return "高于参考区间" }
            return "处于参考区间"
        case .recovery:
            return scoreBandLabel(dashboard.recovery.band) + "恢复"
        case .sleep:
            return scoreBandLabel(dashboard.sleepScore.band) + "睡眠"
        case .stress:
            return stressBandLabel(dashboard.stress.band) + "压力"
        case .energy:
            return energyStatusLabel(dashboard.energy.status)
        case .hrv:
            return "正常范围"
        case .rhr:
            return "正常范围"
        case .weight:
            return "生理特征"
        case .bodyFat:
            return "身体组成"
        case .respiratoryRate:
            return "呼吸频率"
        case .bloodOxygen:
            return "血氧饱和度"
        case .steps:
            return "每日活动量"
        case .activeCalories:
            return "运动消耗"
        case .activeMinutes:
            return "活跃时长"
        }
    }

    var hasMetricData: Bool {
        switch metric {
        case .strain: return dashboard.strain.hasData
        case .recovery: return dashboard.recovery.hasData
        case .sleep: return dashboard.sleepScore.hasData
        case .stress: return dashboard.stress.hasData
        case .energy: return dashboard.energy.hasData
        case .hrv: return dashboard.recoveryMetrics.hrvMilliseconds != nil
        case .rhr: return dashboard.recoveryMetrics.restingHeartRate != nil
        case .weight: return dashboard.bodyMetrics.weightKilograms != nil
        case .bodyFat: return dashboard.bodyMetrics.bodyFatPercentage != nil
        case .respiratoryRate: return dashboard.recoveryMetrics.respiratoryRate != nil
        case .bloodOxygen: return dashboard.extendedMetrics.oxygenSaturation != nil
        case .steps: return dashboard.strain.metrics["steps_raw"] != nil
        case .activeCalories: return dashboard.strain.metrics["active_energy_raw"] != nil
        case .activeMinutes: return dashboard.strain.metrics["exercise_minutes_raw"] != nil
        }
    }

    // Double Highlights Mapping
    var leftIcon: String {
        switch metric {
        case .strain:   return "timer"
        case .sleep:    return "bed.double.fill"
        case .stress:   return "waveform.path.ecg"
        case .weight:           return "scalemass.fill"
        case .bodyFat:          return "figure.arms.open"
        case .respiratoryRate:  return "lungs.fill"
        case .bloodOxygen:      return "drop.fill"
        case .steps:            return "shoeprints.fill"
        case .activeCalories:   return "flame.fill"
        case .activeMinutes:    return "clock.fill"
        default:        return "heart.fill"
        }
    }

    var leftTitle: String {
        switch metric {
        case .strain:   return "时长"
        case .sleep:    return "卧床时间"
        case .stress:   return "上次心率变异性"
        case .recovery: return "昨日 RHR"
        case .energy:   return "日间最高"
        case .hrv:      return "基线平均"
        case .rhr:      return "基线平均"
        case .weight:           return "我的体重"
        case .bodyFat:          return "当前体脂"
        case .respiratoryRate:  return "基线平均"
        case .bloodOxygen:      return "血氧基线"
        case .steps:            return "昨日步数"
        case .activeCalories:   return "活动消耗"
        case .activeMinutes:    return "昨日活跃"
        }
    }

    var leftValue: String {
        switch metric {
        case .strain:
            return dashboard.strain.metrics["exercise_minutes_raw"].map { "\(Int($0))分钟" } ?? "--"
        case .sleep:
            if let bed = dashboard.sleepSummary.bedtime, let wake = dashboard.sleepSummary.wakeTime {
                // 卧床时间跨午夜（bed/wake 存同一日历日）时差值可为负，+24h 取模。
                var diffMin = Int(wake.timeIntervalSince(bed) / 60)
                if diffMin < 0 { diffMin += 24 * 60 }
                return VelaMinimalFormatting.duration(minutes: diffMin)
            }
            return "--"
        case .stress:
            return dashboard.recoveryMetrics.hrvMilliseconds.map { "\(Int($0)) ms" } ?? "--"
        case .recovery:
            return dashboard.recoveryMetrics.restingHeartRate.map { "\(Int($0)) bpm" } ?? "--"
        case .energy:
            return dashboard.energy.hasData ? "\(Int(dashboard.energy.morningEnergy)) 分" : "--"
        case .hrv:
            return dashboard.recoveryBaseline.hrvMilliseconds.map { "\(Int($0)) ms" } ?? "--"
        case .rhr:
            return dashboard.recoveryBaseline.restingHeartRate.map { "\(Int($0)) bpm" } ?? "--"
        case .weight:
            return dashboard.bodyMetrics.weightKilograms.map { String(format: "%.1f kg", $0) } ?? "--"
        case .bodyFat:
            return dashboard.bodyMetrics.bodyFatPercentage.map { String(format: "%.1f%%", $0) } ?? "--"
        case .respiratoryRate:
            return dashboard.recoveryBaseline.respiratoryRate.map { "\(Int($0))/min" } ?? "待建立"
        case .bloodOxygen:
            return dashboard.extendedMetrics.oxygenSaturation.map { "\(Int($0))%" } ?? "--"
        case .steps:
            return dashboard.strain.metrics["steps_raw"].map { "\(Int($0)) 步" } ?? "--"
        case .activeCalories:
            return dashboard.strain.metrics["active_energy_raw"].map { "\(Int($0)) kcal" } ?? "--"
        case .activeMinutes:
            return dashboard.strain.metrics["exercise_minutes_raw"].map { "\(Int($0)) 分钟" } ?? "--"
        }
    }

    var leftSubtitle: String? {
        if metric == .stress {
            return "更新时间: \(dashboard.stress.lastUpdated.formatted(date: .omitted, time: .shortened))"
        }
        return nil
    }

    var rightIcon: String {
        switch metric {
        case .strain:   return "flame.fill"
        case .sleep:    return "clock.fill"
        case .stress:   return "heart.fill"
        case .weight:           return "figure.body.strength"
        case .bodyFat:          return "scalemass.fill"
        case .respiratoryRate:  return "waveform.path.ecg"
        case .bloodOxygen:      return "sparkles"
        case .steps:            return "target"
        case .activeCalories:   return "flame.circle.fill"
        case .activeMinutes:    return "figure.run"
        default:        return "bolt.fill"
        }
    }

    var rightTitle: String {
        switch metric {
        case .strain:   return "总能量"
        case .sleep:    return "睡眠时长"
        case .stress:   return "上次心率"
        case .recovery: return "今日 HRV"
        case .energy:   return "日间最低"
        case .hrv:      return "今日读数"
        case .rhr:      return "今日读数"
        case .weight:           return "体脂率"
        case .bodyFat:          return "当前体重"
        case .respiratoryRate:  return "今日读数"
        case .bloodOxygen:      return "今日读数"
        case .steps:            return "今日步数"
        case .activeCalories:   return "当天负荷"
        case .activeMinutes:    return "今日活跃"
        }
    }

    var rightValue: String {
        switch metric {
        case .strain:
            return dashboard.strain.metrics["active_energy_raw"].map { "\(Int($0)) kcal" } ?? "--"
        case .sleep:
            let mins = dashboard.sleepSummary.totalSleepMinutes
            if mins > 0 {
                return VelaMinimalFormatting.duration(minutes: mins)
            }
            return "--"
        case .stress:
            return dashboard.recoveryMetrics.restingHeartRate.map { "\(Int($0)) bpm" } ?? "--"
        case .recovery:
            return dashboard.recoveryMetrics.hrvMilliseconds.map { "\(Int($0)) ms" } ?? "--"
        case .energy:
            return dashboard.energy.hasData ? "\(Int(dashboard.energy.currentEnergy)) 分" : "--"
        case .hrv:
            return dashboard.recoveryMetrics.hrvMilliseconds.map { "\(Int($0)) ms" } ?? "--"
        case .rhr:
            return dashboard.recoveryMetrics.restingHeartRate.map { "\(Int($0)) bpm" } ?? "--"
        case .weight:
            return dashboard.bodyMetrics.bodyFatPercentage.map { String(format: "%.1f%%", $0) } ?? "--"
        case .bodyFat:
            return dashboard.bodyMetrics.weightKilograms.map { String(format: "%.1f kg", $0) } ?? "--"
        case .respiratoryRate:
            return dashboard.recoveryMetrics.respiratoryRate.map { "\(Int($0))/min" } ?? "--"
        case .bloodOxygen:
            return dashboard.extendedMetrics.oxygenSaturation.map { "\(Int($0))%" } ?? "--"
        case .steps:
            return dashboard.strain.metrics["steps_raw"].map { "\(Int($0)) 步" } ?? "--"
        case .activeCalories:
            return dashboard.strain.hasData ? "\(Int(dashboard.strain.score.rounded())) / 100" : "--"
        case .activeMinutes:
            return dashboard.strain.metrics["exercise_minutes_raw"].map { "\(Int($0)) 分钟" } ?? "--"
        }
    }

    var rightSubtitle: String? {
        if metric == .stress {
            return "更新时间: \(dashboard.stress.lastUpdated.formatted(date: .omitted, time: .shortened))"
        }
        return nil
    }

    var hasCompleteSleepTimes: Bool {
        return dashboard.sleepSummary.bedtime != nil && dashboard.sleepSummary.wakeTime != nil
    }

    var bedtimeHour: Int {
        if let bed = dashboard.sleepSummary.bedtime {
            return Calendar.current.component(.hour, from: bed)
        }
        return 0
    }
    var bedtimeMinute: Int {
        if let bed = dashboard.sleepSummary.bedtime {
            return Calendar.current.component(.minute, from: bed)
        }
        return 0
    }
    var wakeHour: Int {
        if let wake = dashboard.sleepSummary.wakeTime {
            return Calendar.current.component(.hour, from: wake)
        }
        return 0
    }
    var wakeMinute: Int {
        if let wake = dashboard.sleepSummary.wakeTime {
            return Calendar.current.component(.minute, from: wake)
        }
        return 0
    }
    var bedtimeText: String {
        guard dashboard.sleepSummary.bedtime != nil else { return "--" }
        return VelaMinimalFormatting.clockTime(hour: bedtimeHour, minute: bedtimeMinute)
    }
    var wakeTimeText: String {
        guard dashboard.sleepSummary.wakeTime != nil else { return "--" }
        return VelaMinimalFormatting.clockTime(hour: wakeHour, minute: wakeMinute)
    }
    var targetBedtimeText: String {
        return VelaMinimalFormatting.clockTime(hour: targetBedtimeHour, minute: targetBedtimeMinute)
    }
    var sleepTargetMinutes: Int {
        return Int((sleepTargetHours * 60.0).rounded())
    }
    var primarySleepStartText: String {
        guard let bedtime = dashboard.sleepSummary.bedtime else { return "暂无睡眠开始时间" }
        return bedtime.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "zh_Hans_CN"))
        )
    }

    var guidanceText: String {
        guard hasMetricData else { return "完成 Apple 健康同步后，这里会展示基于真实数据的分析。" }
        return metricReasons.first ?? "当前指标已更新，请结合趋势和限制因素查看。"
    }

    var trendItems: [TrendItem] {
        CoreMetricTrendMapper.seriesList(
            for: metric,
            findings: dashboard.healthTrends,
            snapshots: dailyRecords.map { $0.toSnapshot() },
            endingAt: effectiveDate
        )
    }

    var evidenceItems: [EvidenceItem] {
        switch metric {
        case .strain:
            return [
                evidence("训练负荷", dashboard.strain.metrics["workout_load"], .decimal(""), "训练本身贡献"),
                evidence("日常活动", dashboard.strain.metrics["activity_load"], .decimal(""), "已降低重复计入权重"),
                evidence("今日总负荷", dashboard.strain.metrics["daily_load"], .decimal(""), "训练与非训练活动合计"),
                evidence("负荷比", dashboard.strain.metrics["training_load_ratio"], .decimal("x"), "近期 7 天 / 28 天等效")
            ]
        case .recovery:
            return [
                evidence("HRV 偏离", dashboard.recovery.metrics["hrv_z_score"], .signedDecimal(" z"), "相对个人基线"),
                evidence("RHR 偏离", dashboard.recovery.metrics["rhr_z_score"], .signedDecimal(" z"), "相对个人基线"),
                evidence("呼吸率偏离", dashboard.recovery.metrics["respiratory_rate_z"], .signedDecimal(" z"), "相对个人基线"),
                evidence("体温偏离", dashboard.recovery.metrics["body_temp_delta"], .signedDecimal("°C"), "夜间体温变化"),
                evidence("血氧", dashboard.recovery.metrics["spo2"] ?? dashboard.extendedMetrics.oxygenSaturation, .decimal("%"), "SpO₂"),
                // 联通专项批次 1：副交感张力指数（此前算了但任何地方都不展示）。
                evidence("副交感张力", dashboard.recovery.metrics["parasympathetic_tone_index"], .signedDecimal(""), "HRV 高频成分启发式")
            ]
        case .sleep:
            return [
                evidence("睡眠效率", dashboard.sleepScore.metrics["sleep_efficiency"], .decimal("%"), "睡眠 / 卧床"),
                evidence("REM 占比", dashboard.sleepScore.metrics["rem_pct"], .decimal("%"), "快速眼动睡眠"),
                evidence("深睡占比", dashboard.sleepScore.metrics["deep_pct"], .decimal("%"), "深度睡眠"),
                evidence("清醒时间", dashboard.sleepScore.metrics["awake_minutes"], .integer(" 分钟"), "睡眠期间"),
                evidence("清醒次数", dashboard.sleepScore.metrics["awake_episode_count"], .integer(" 次"), "睡眠期间")
            ]
        case .stress:
            return [
                evidence("心率压力", dashboard.stress.metrics["rhr_stress"], .integer(""), "静息心率维度"),
                evidence("HRV 压力", dashboard.stress.metrics["hrv_stress"], .integer(""), "自主神经维度"),
                evidence("呼吸压力", dashboard.stress.metrics["resp_stress"], .integer(""), "呼吸率维度"),
                evidence("睡眠债压力", dashboard.stress.metrics["sleep_debt_stress"], .integer(""), "睡眠影响"),
                // 联通专项批次 1：补齐此前缺失的两个压力因子。
                evidence("体温压力", dashboard.stress.metrics["temp_stress"], .integer(""), "夜间体温维度"),
                evidence("负荷压力", dashboard.stress.metrics["load_stress"], .integer(""), "近期负荷维度")
            ]
        case .energy:
            return [
                evidence("ATL", dashboard.energy.metrics["atl"], .decimal(""), "7 天急性负荷"),
                evidence("CTL", dashboard.energy.metrics["ctl"], .decimal(""), "42 天慢性负荷"),
                evidence("TSB", dashboard.energy.metrics["tsb"], .signedDecimal(""), "CTL - ATL"),
                evidence("ACWR", dashboard.energy.metrics["acwr"], .decimal("x"), "急性 / 慢性负荷")
            ]
        case .hrv:
            return [
                evidence("今日 HRV", dashboard.recoveryMetrics.hrvMilliseconds, .integer(" ms"), "Apple 健康读数"),
                evidence("个人基线", dashboard.recoveryBaseline.hrvMilliseconds, .integer(" ms"), "用于比较"),
                evidence("基线偏离", dashboard.recovery.metrics["hrv_z_score"], .signedDecimal(" z"), "恢复评分输入")
            ]
        case .rhr:
            return [
                evidence("今日 RHR", dashboard.recoveryMetrics.restingHeartRate, .integer(" bpm"), "Apple 健康读数"),
                evidence("个人基线", dashboard.recoveryBaseline.restingHeartRate, .integer(" bpm"), "用于比较"),
                evidence("基线偏离", dashboard.recovery.metrics["rhr_z_score"], .signedDecimal(" z"), "恢复评分输入")
            ]
        case .weight:
            return [
                evidence("体重", dashboard.bodyMetrics.weightKilograms, .decimal(" kg"), "最近一次读数"),
                evidence("体脂率", dashboard.bodyMetrics.bodyFatPercentage, .decimal("%"), "身体组成"),
                evidence("BMI", dashboard.extendedMetrics.bmi, .decimal(""), "身高体重换算")
            ]
        case .bodyFat:
            return [
                evidence("体脂率", dashboard.bodyMetrics.bodyFatPercentage, .decimal("%"), "最近一次读数"),
                evidence("体重", dashboard.bodyMetrics.weightKilograms, .decimal(" kg"), "身体组成参考"),
                evidence("去脂体重", dashboard.bodyMetrics.leanBodyMassKilograms, .decimal(" kg"), "身体组成参考")
            ]
        case .respiratoryRate:
            return [
                evidence("今日呼吸率", dashboard.recoveryMetrics.respiratoryRate, .decimal("/min"), "Apple 健康读数"),
                evidence("个人基线", dashboard.recoveryBaseline.respiratoryRate, .decimal("/min"), "用于比较"),
                evidence("基线偏离", dashboard.recovery.metrics["respiratory_rate_z"], .signedDecimal(" z"), "恢复评分输入")
            ]
        case .bloodOxygen:
            return [
                evidence("血氧", dashboard.extendedMetrics.oxygenSaturation, .decimal("%"), "SpO₂ 最近读数"),
                evidence("恢复输入", dashboard.recovery.metrics["spo2"], .decimal("%"), "恢复评分引用"),
                evidence("呼吸率", dashboard.recoveryMetrics.respiratoryRate, .decimal("/min"), "呼吸健康参考")
            ]
        case .steps, .activeCalories, .activeMinutes:
            return [
                evidence("今日步数", dashboard.strain.metrics["steps_raw"], .integer(" 步"), "日常活动"),
                evidence("活动消耗", dashboard.strain.metrics["active_energy_raw"], .integer(" kcal"), "活动能量"),
                evidence("活跃时长", dashboard.strain.metrics["exercise_minutes_raw"], .integer(" 分钟"), "锻炼分钟"),
                evidence("日常活动负荷", dashboard.strain.metrics["activity_load"], .decimal(""), "避免与训练负荷重复计算")
            ]
        }
    }

    func evidence(
        _ title: String,
        _ value: Double?,
        _ format: EvidenceFormat,
        _ detail: String
    ) -> EvidenceItem {
        EvidenceItem(id: title, title: title, value: evidenceText(value, format: format), detail: detail)
    }

    func evidenceText(_ value: Double?, format: EvidenceFormat) -> String {
        guard let value else { return "--" }
        switch format {
        case let .integer(suffix):
            return "\(Int(value.rounded()))\(suffix)"
        case let .decimal(suffix):
            return String(format: "%.1f%@", value, suffix)
        case let .signedDecimal(suffix):
            return String(format: "%+.1f%@", value, suffix)
        }
    }

    var limitingFactors: [String] {
        let reasons = Array(metricReasons.prefix(3))
        return reasons.isEmpty ? ["暂无可用分析原因"] : reasons
    }

    var metricReasons: [String] {
        switch metric {
        case .strain:
            return dashboard.strain.reasons
        case .sleep:
            return dashboard.sleepScore.reasons
        case .stress:
            return dashboard.stress.reasons
        case .recovery, .hrv, .rhr:
            return dashboard.recovery.reasons
        case .energy:
            return dashboard.energy.reasons
        case .weight, .bodyFat, .respiratoryRate, .bloodOxygen:
            return [
                "生理体征偏离正常基线时，应当与睡眠、体能负荷与日间自觉症状综合关联评估。",
                "确保每天在相近时间完成测量，以便建立可信度更高的趋势分析基线。"
            ]
        case .steps, .activeCalories, .activeMinutes:
            return [
                "运动负荷与能量摄入可能影响次日恢复；结合连续几天的趋势比单次读数更有参考价值。",
                "高负荷日后可根据饥饿感、训练安排和个人目标，保证规律进食、补水与休息。"
            ]
        }
    }

    func scoreBandLabel(_ band: MetricBand) -> String {
        switch band {
        case .veryLow: return "很低"
        case .low: return "低"
        case .normal: return "正常"
        case .high: return "高"
        case .veryHigh: return "很高"
        }
    }

    func stressBandLabel(_ band: MetricBand) -> String {
        switch band {
        case .veryLow: return "平静"
        case .low: return "正常"
        case .normal: return "偏高"
        case .high, .veryHigh: return "高"
        }
    }

    func energyStatusLabel(_ status: EnergyBankStatus) -> String {
        switch status {
        case .depleted: return "耗竭"
        case .low: return "偏低"
        case .stable: return "稳定"
        case .strong: return "充足"
        }
    }

    func strainTargetLabel(_ target: StrainTargetStatus) -> String {
        switch target {
        case .belowTarget: return "低于目标"
        case .withinTarget: return "在目标范围"
        case .aboveTarget: return "高于目标"
        }
    }
}
