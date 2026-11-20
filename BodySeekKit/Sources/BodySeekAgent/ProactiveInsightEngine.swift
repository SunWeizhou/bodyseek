import BodySeekCore
import Foundation

public struct ProactiveInsight: Identifiable, Equatable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case threeDayDeviation
        case postWorkoutReview
        case morningTone
    }

    public enum Route: Equatable, Hashable, Sendable, Codable {
        case askCoach(prompt: String)
        case openWorkoutInbox
    }

    public let id: String
    public let dayKey: DayKey
    public let kind: Kind
    public let title: String
    public let body: String
    public let badge: String
    public let ctaTitle: String
    public let route: Route

    public init(
        id: String,
        dayKey: DayKey,
        kind: Kind,
        title: String,
        body: String,
        badge: String,
        ctaTitle: String,
        route: Route
    ) {
        self.id = id
        self.dayKey = dayKey
        self.kind = kind
        self.title = title
        self.body = body
        self.badge = badge
        self.ctaTitle = ctaTitle
        self.route = route
    }
}

/// Generates at most 2 concise proactive insights per day from real objective signals without hallucination.
public enum ProactiveInsightEngine {
    public static func generate(
        snapshot: BodySeekDashboardSnapshot,
        storedWorkouts: [StoredWorkoutRecord],
        enabled: Bool,
        dismissedIDs: Set<String> = [],
        maxCount: Int = 2
    ) -> [ProactiveInsight] {
        guard enabled, snapshot.isAuthorized else { return [] }

        let cap = min(2, max(0, maxCount))
        guard cap > 0 else { return [] }

        let dayKey = snapshot.today.dayKey
        var candidates: [ProactiveInsight] = []

        if let deviation = detectThreeDayDeviation(historyDays: snapshot.historyDays, dayKey: dayKey) {
            candidates.append(deviation)
        }

        if let reviewReminder = detectPostWorkoutReview(
            storedWorkouts: storedWorkouts,
            dayKey: dayKey,
            referenceDate: snapshot.referenceDate
        ) {
            candidates.append(reviewReminder)
        }

        if let morning = makeMorningToneInsight(snapshot: snapshot, dayKey: dayKey) {
            candidates.append(morning)
        }

        return Array(
            candidates
                .filter { !dismissedIDs.contains($0.id) }
                .prefix(cap)
        )
    }

    private static func detectThreeDayDeviation(
        historyDays: [DailyComputedDay],
        dayKey: DayKey
    ) -> ProactiveInsight? {
        let sorted = historyDays.filter { $0.dayKey <= dayKey }.sorted { $0.dayKey < $1.dayKey }
        guard sorted.count >= 10 else { return nil }

        let trailing3 = Array(sorted.suffix(3))
        let priorBaseline = Array(sorted.dropLast(3).suffix(28))

        // Check HRV consecutive 3-day dip (>= 15% below personal 28d baseline)
        let recentHRVs = trailing3.compactMap(\.raw.hrvMs)
        let baseHRVs = priorBaseline.compactMap(\.raw.hrvMs)
        if recentHRVs.count == 3, baseHRVs.count >= 5 {
            let baseMean = baseHRVs.reduce(0, +) / Double(baseHRVs.count)
            if baseMean > 0, recentHRVs.allSatisfy({ $0 <= baseMean * 0.85 }) {
                let latestMean = Int((recentHRVs.reduce(0, +) / 3.0).rounded())
                let baseRounded = Int(baseMean.rounded())
                return ProactiveInsight(
                    id: "\(dayKey.isoString)::\(ProactiveInsight.Kind.threeDayDeviation.rawValue)",
                    dayKey: dayKey,
                    kind: .threeDayDeviation,
                    title: "连续 3 天 HRV 低于个人基线",
                    body: "近 3 日均值 \(latestMean) ms（个人基线约 \(baseRounded) ms），建议安排减量或主动恢复并关注睡眠。",
                    badge: "基线偏离",
                    ctaTitle: "与教练复盘",
                    route: .askCoach(prompt: "我连续3天HRV低于基线，结合近期负荷与睡眠，帮我调整今天训练")
                )
            }
        }

        // Check RHR consecutive 3-day elevation (>= +4 bpm above personal 28d baseline)
        let recentRHRs = trailing3.compactMap(\.raw.restingHeartRateBpm)
        let baseRHRs = priorBaseline.compactMap(\.raw.restingHeartRateBpm)
        if recentRHRs.count == 3, baseRHRs.count >= 5 {
            let baseMean = baseRHRs.reduce(0, +) / Double(baseRHRs.count)
            if recentRHRs.allSatisfy({ $0 >= baseMean + 4.0 }) {
                let latestMean = Int((recentRHRs.reduce(0, +) / 3.0).rounded())
                let baseRounded = Int(baseMean.rounded())
                return ProactiveInsight(
                    id: "\(dayKey.isoString)::\(ProactiveInsight.Kind.threeDayDeviation.rawValue)",
                    dayKey: dayKey,
                    kind: .threeDayDeviation,
                    title: "连续 3 天静息心率偏高",
                    body: "近 3 日静息心率均值 \(latestMean) bpm（个人基线约 \(baseRounded) bpm），可让教练排查负荷或补水/作息变化。",
                    badge: "基线偏离",
                    ctaTitle: "排查原因",
                    route: .askCoach(prompt: "我连续3天静息心率高于基线，帮我对照相似历史日与近7天负荷分析")
                )
            }
        }

        return nil
    }

    private static func detectPostWorkoutReview(
        storedWorkouts: [StoredWorkoutRecord],
        dayKey: DayKey,
        referenceDate: Date
    ) -> ProactiveInsight? {
        let cutoff = dayKey.startDate().addingTimeInterval(-7 * 86_400)
        let dayEnd = max(referenceDate, dayKey.startDate().addingTimeInterval(86_400))
        let pending = storedWorkouts
            .filter { $0.reviewState == .unreviewed && $0.end >= cutoff && $0.end <= dayEnd }
            .sorted { $0.start > $1.start }

        guard let latest = pending.first else { return nil }
        return ProactiveInsight(
            id: "\(dayKey.isoString)::\(ProactiveInsight.Kind.postWorkoutReview.rawValue)",
            dayKey: dayKey,
            kind: .postWorkoutReview,
            title: "有 \(pending.count) 条手表训练待一句话复盘",
            body: "最近一次「\(latest.type)」尚未标定主次肌群与 RPE，30 秒复盘后即可更新全身恢复热图。",
            badge: "练后复盘",
            ctaTitle: "去复盘",
            route: .openWorkoutInbox
        )
    }

    private static func makeMorningToneInsight(
        snapshot: BodySeekDashboardSnapshot,
        dayKey: DayKey
    ) -> ProactiveInsight? {
        let today = snapshot.today
        guard today.recovery.availability.isAvailable || today.sleep.availability.isAvailable else {
            return nil
        }

        let recText = today.recovery.value.map { "恢复 \($0) 分" } ?? "恢复待同步"
        let sleepHoursText = today.raw.sleepAsleepMinutes.map { String(format: "睡眠 %.1f h", Double($0) / 60.0) } ?? "睡眠待同步"
        let acwrText = snapshot.trainingLoad.acwrRatio.map { String(format: "ACWR %.2f（%@）", $0, snapshot.trainingLoad.zone.title) } ?? snapshot.trainingLoad.zone.title

        return ProactiveInsight(
            id: "\(dayKey.isoString)::\(ProactiveInsight.Kind.morningTone.rawValue)",
            dayKey: dayKey,
            kind: .morningTone,
            title: "晨间定调 · \(today.recovery.badge)",
            body: "今日\(recText)、\(sleepHoursText)，近 7 天 \(acwrText)。点击可让教练结合 3 层记忆排定今日节奏。",
            badge: "晨间定调",
            ctaTitle: "问教练",
            route: .askCoach(prompt: "结合我今天的客观恢复、睡眠与记忆，给出今日训练和作息定调建议")
        )
    }
}
