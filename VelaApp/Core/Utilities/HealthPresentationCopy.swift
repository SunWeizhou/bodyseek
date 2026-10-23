import Foundation

/// Shared Chinese copy for score-detail missing inputs.
/// Engine keys stay distinct; the UI list must not collapse them into one label.
enum MissingInputLabel {
    static func chineseLabel(for rawKey: String) -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "部分输入" }
        if let mapped = exactLabels[key] { return mapped }
        let folded = key.lowercased()
        if let match = exactLabels.first(where: { $0.key.lowercased() == folded }) {
            return match.value
        }
        return humanizedFallback(key)
    }

    /// First `limit` unique labels, walking keys in order. Duplicate labels are skipped
    /// so a later distinct key can still appear.
    static func uniqueLabels(for keys: [String], limit: Int = 3) -> [String] {
        var seen = Set<String>()
        var labels: [String] = []
        for key in keys {
            let label = chineseLabel(for: key)
            guard seen.insert(label).inserted else { continue }
            labels.append(label)
            if labels.count >= limit { break }
        }
        return labels
    }

    static func summary(
        for keys: [String],
        emptyValueMessage: String? = nil,
        hasValue: Bool,
        suffix: String = ""
    ) -> String? {
        if !hasValue {
            return emptyValueMessage
        }
        guard !keys.isEmpty else { return nil }
        let labels = uniqueLabels(for: keys)
        guard !labels.isEmpty else { return nil }
        return "仍缺少：\(labels.joined(separator: "、"))。\(suffix)"
            .trimmingCharacters(in: .whitespaces)
    }

    private static let exactLabels: [String: String] = [
        "totalSleepMinutes": "睡眠总时长",
        "inBedMinutes": "在床时长",
        "remMinutes": "REM 时长",
        "deepMinutes": "深睡时长",
        "awakeMinutes": "夜间清醒时长",
        "awakeEpisodeCount": "醒来次数",
        "todayBedtime": "当日入睡时间",
        "recentBedtimesHistory": "近期入睡时间历史",
        "wakeTime": "起床时间",
        "hrvToday": "今日 HRV",
        "hrvHistory": "HRV 历史",
        "hrvBaseline": "HRV 基线",
        "restingHeartRateToday": "今日静息心率",
        "rhrHistory": "静息心率历史",
        "quietHRToday": "今日安静心率",
        "quietHRBaseline": "安静心率基线",
        "quietWindow": "安静窗口",
        "respRateBaseline": "呼吸率基线",
        "bodyTempDelta": "腕温变化",
        "sleepScore": "睡眠分",
        "recoveryScore": "恢复分",
        "strainScore": "负荷分",
        "stressIndex": "压力指数",
        "priorStrainYesterday": "昨日负荷",
        "todayLoad": "今日负荷",
        "trainingLoadHistory": "训练负荷历史",
        "overnightStabilitySignals": "夜间稳定信号",
        "workouts": "训练记录",
        "activeEnergyToday": "今日活动能量",
        "exerciseMinutesToday": "今日锻炼分钟",
        "stepCount": "步数"
    ]

    private static func humanizedFallback(_ key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: #"([a-z0-9])([A-Z])"#,
                with: "$1 $2",
                options: .regularExpression
            )
        let trimmed = spaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? key : trimmed
    }
}

/// How many days in a window actually carry a score. Once the minimum is met
/// the count is stated against the window, not against the minimum.
enum TrendSampleCopy {
    static func text(sampleCount: Int, requiredSampleCount: Int, horizon: HealthTrendHorizon) -> String {
        if sampleCount >= requiredSampleCount {
            return "历史 \(horizon.windowDays) 天中 \(min(sampleCount, horizon.windowDays)) 天有评分，不含当天"
        }
        return "基线历史 \(sampleCount)/\(requiredSampleCount) 天，不含当天"
    }
}

/// Personal Baseline Deviation is "unusual for you", never a good/bad alarm.
enum BaselineDeviationCopy {
    static let unusualFallback = "偏离个人基线"
    static let belowUsual = "低于平时"
    static let aboveUsual = "高于平时"

    static func relativeToUsual(percent: Double?) -> String? {
        guard let percent, percent.isFinite else { return nil }
        if percent < 0 { return belowUsual }
        if percent > 0 { return aboveUsual }
        return nil
    }

    static func relativeToUsual(current: Double?, baseline: Double?) -> String? {
        guard let current, let baseline, current.isFinite, baseline.isFinite else { return nil }
        if current < baseline { return belowUsual }
        if current > baseline { return aboveUsual }
        return nil
    }

    static func label(for finding: HealthTrendFinding) -> String? {
        relativeToUsual(percent: finding.currentDeviationPercent)
            ?? relativeToUsual(current: finding.currentValue, baseline: finding.baselineValue)
    }
}

enum ConfidenceBadgeCopy {
    static func label(confidence: DataConfidence? = nil, score: Double? = nil) -> String {
        "置信度 \(level(confidence: confidence, score: score))"
    }

    static func level(confidence: DataConfidence? = nil, score: Double? = nil) -> String {
        if let score, score.isFinite {
            if score >= 0.75 { return "高" }
            if score >= 0.5 { return "中" }
            return "低"
        }
        switch confidence {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        case .unavailable, nil: return "未知"
        }
    }
}
