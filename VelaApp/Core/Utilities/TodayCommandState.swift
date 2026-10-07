import Foundation

enum ReadinessDecisionKind: String, Codable, Hashable, CaseIterable {
    case keep
    case reduce
    case swap
    case recover
}

struct TodayHealthSignal: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var value: String
    var interpretation: String
}

struct TodayAction: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Hashable, CaseIterable {
        case training
        case recovery
        case checkIn
        case coach
        case insight
    }

    var id: String
    var kind: Kind
    var title: String
    var detail: String
    var destination: String
    var isPrimary: Bool
}

struct ReadinessDecision: Codable, Hashable, Sendable {
    var decision: ReadinessDecisionKind
    var confidence: Double
    var reasons: [String]
    var supportingSignals: [TodayHealthSignal]
    var userOverrideAvailable: Bool

    var displayTitle: String {
        switch decision {
        case .keep: return "按计划训练"
        case .reduce: return "降低容量"
        case .swap: return "替换训练"
        case .recover: return "恢复优先"
        }
    }
}

struct TodayCommandState: Codable, Hashable, Sendable {
    var date: Date
    var bodyStateTitle: String
    var summary: String
    var readinessDecision: ReadinessDecision
    var keySignals: [TodayHealthSignal]
    var actions: [TodayAction]
    var coachArtifact: CoachArtifact?
    var dataConfidence: DataConfidence
}

/// 决策反馈回灌：按同类历史反馈的准确率校准置信度（服务 Trusted Decision Day 北极星）。
/// DailyDecisionFeedbackRecord 此前只写不回，本校准器把它接回决策展示。
enum DecisionFeedbackCalibrator {
    /// Input-evidence policy only; the confidence and volume formulas are unchanged.
    static let evidencePolicyVersion = "feedback-evidence-asof.v2"
    static let minimumSamples = 3
    static let recencyWindowDays = 28

    /// Today's evidence stops at evaluation time. A completed historical day
    /// includes that whole local calendar day, including DST transitions.
    /// Future days have no available feedback evidence.
    static func evidenceCutoff(
        for selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: now)
        guard selectedDay <= today else { return nil }
        if selectedDay == today { return now }
        guard let interval = calendar.dateInterval(of: .day, for: selectedDay) else { return nil }
        return Date(timeIntervalSinceReferenceDate: interval.end.timeIntervalSinceReferenceDate.nextDown)
    }

    static func calibratedConfidence(
        base: Double,
        decision: ReadinessDecisionKind,
        records: [DailyDecisionFeedbackRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let cutoff = now.addingTimeInterval(-Double(recencyWindowDays) * 86_400)
        let rated = records.filter {
            matches(decision: decision, recordDecisionType: $0.decisionType)
                && $0.accuracyRating != nil
                && $0.createdAt >= cutoff
                && $0.createdAt <= now
                && $0.updatedAt <= now
        }
        guard rated.count >= minimumSamples else { return base }
        // PR9：「部分准确」按 0.5 计分，不再被误判为不准确。
        // 校准只降不升（上限 1.0）：自报反馈不得把置信度抬到数据驱动基线之上。
        let score = rated.reduce(0.0) { partial, record in
            switch record.accuracyRating {
            case "accurate": return partial + 1.0
            case "partly": return partial + 0.5
            default: return partial
            }
        }
        let accuracy = score / Double(rated.count)
        // 校准乘数：100% 准确 → 1.0；0% → 0.6 下限（样本有限，不完全归零）。
        let multiplier = 0.6 + 0.4 * accuracy
        return min(1.0, base * multiplier)
    }

    /// PR1 修复：写入路径存的是 DailyTrainingDecisionType（case `.rest`），
    /// 而本校准器按 ReadinessDecisionKind（case `.recover`）匹配。
    /// 归一化 `rest → recover`，恢复/休息日的反馈不再被静默丢弃。
    private static func matches(decision: ReadinessDecisionKind, recordDecisionType: String?) -> Bool {
        let normalized = recordDecisionType == "rest" ? "recover" : recordDecisionType
        return normalized == decision.rawValue
    }

    /// 算法打通（批次 C）：正式计划（DailyTrainingDecisionType）也吃同一份反馈校准，
    /// 在 DailyOperatingPlanCoordinator.upsert 持久化时应用——所有展示面自动一致。
    static func calibratedPlanConfidence(
        base: Double,
        decision: DailyTrainingDecisionType,
        records: [DailyDecisionFeedbackRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let kind: ReadinessDecisionKind
        switch decision {
        case .rest: kind = .recover
        case .keep: kind = .keep
        case .reduce: kind = .reduce
        case .swap: kind = .swap
        }
        return calibratedConfidence(base: base, decision: kind, records: records, now: now, calendar: calendar)
    }

    /// 深度专项批次 6：近 28 天反馈的中文摘要（AI 阈值审阅与 Coach 提示词共用）。
    static func feedbackSummary(
        records: [DailyDecisionFeedbackRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let cutoff = now.addingTimeInterval(-Double(recencyWindowDays) * 86_400)
        // An edited record has no versioned history: do not project its newer
        // rating backward even when the original record was created earlier.
        let recent = records.filter {
            $0.accuracyRating != nil && $0.createdAt >= cutoff
                && $0.createdAt <= now && $0.updatedAt <= now
        }
        let byDecision = Dictionary(grouping: recent, by: \.decisionType)
        var lines: [String] = []
        for (decision, group) in byDecision.sorted(by: { $0.key < $1.key }) {
            let accurate = group.filter { $0.accuracyRating == "accurate" }.count
            let partly = group.filter { $0.accuracyRating == "partly" }.count
            lines.append("\(decision): \(group.count) 条反馈（准确 \(accurate)、部分准确 \(partly)）")
        }
        return lines.isEmpty ? "近 28 天暂无决策反馈。" : lines.joined(separator: "；")
    }
}

enum TodayCommandBuilder {
    /// 算法打通（批次 A）：`trainingDecision`（TrainingDecisionKernel 输出）提供时，
    /// 今日页的 readiness 结论直接投影自它——今日页/训练页/计划页共用同一结论源，
    /// 不再各自跑一套判定树。未提供时保留旧判定树作为兜底（缓存首帧等边界场景）。
    static func build(
        from dashboard: DashboardSummary,
        recentStrengthSummary: RecentTrainingSummary? = nil,
        coachArtifact: CoachArtifact? = nil,
        generatedAt: Date = Date(),
        confirmedObservations: [String] = [],
        trainingDecision: DailyTrainingDecision? = nil
    ) -> TodayCommandState {
        let signals = keySignals(from: dashboard, recentStrengthSummary: recentStrengthSummary)
        let decision: (decision: ReadinessDecisionKind, confidence: Double, reasons: [String])
        if let trainingDecision {
            decision = projectedDecision(from: trainingDecision, dashboard: dashboard)
        } else {
            decision = readinessDecision(from: dashboard, signals: signals, recentStrengthSummary: recentStrengthSummary)
        }
        let actions = actions(for: decision.decision, dashboard: dashboard)
        let artifact = coachArtifact ?? localMorningBrief(from: dashboard, decision: decision, generatedAt: generatedAt)
        let confidence = aggregateConfidence(dashboard: dashboard, signals: signals)

        var summaryText: String
        if let trainingDecision, !trainingDecision.userFacingSummary.isEmpty {
            summaryText = trainingDecision.userFacingSummary
        } else {
            summaryText = summary(for: decision.decision, dashboard: dashboard)
        }
        // C2：已确认的个人反应规律直接进入今日计划文案（本地规则引擎也能用，不只 AI 知道）。
        if !confirmedObservations.isEmpty {
            let compact = confirmedObservations.prefix(2).joined(separator: "；")
            summaryText += "\n\n参考你的长期记录：" + compact
        }
        return TodayCommandState(
            date: dashboard.date,
            bodyStateTitle: title(for: decision.decision, dashboard: dashboard),
            summary: summaryText,
            readinessDecision: ReadinessDecision(
                decision: decision.decision,
                confidence: decision.confidence,
                reasons: decision.reasons,
                supportingSignals: signals,
                userOverrideAvailable: true
            ),
            keySignals: Array(signals.prefix(5)),
            actions: actions,
            coachArtifact: artifact,
            dataConfidence: confidence
        )
    }

    /// kernel 决策 → readiness 结论（rest ↔ recover 归一）。
    /// 置信度仍用数据驱动的加权公式（rec/sleep/stress），由 DecisionFeedbackCalibrator 校准。
    private static func projectedDecision(
        from trainingDecision: DailyTrainingDecision,
        dashboard: DashboardSummary
    ) -> (decision: ReadinessDecisionKind, confidence: Double, reasons: [String]) {
        let kind: ReadinessDecisionKind
        switch trainingDecision.decision {
        case .rest: kind = .recover
        case .keep: kind = .keep
        case .reduce: kind = .reduce
        case .swap: kind = .swap
        }
        let recConf = dashboard.recovery.hasData ? numericConfidence(dashboard.recovery.confidence) : 0.0
        let sleepConf = dashboard.sleepScore.hasData ? numericConfidence(dashboard.sleepScore.confidence) : 0.0
        let stressConf = dashboard.stress.hasData ? numericConfidence(dashboard.stress.confidence) : 0.0
        let weighted = min(1.0, 0.50 * recConf + 0.30 * sleepConf + 0.20 * stressConf)
        let reasons = trainingDecision.reasons.isEmpty
            ? ["按今日身体信号给出的训练决策。"]
            : trainingDecision.reasons
        return (kind, weighted, reasons)
    }

    private static func numericConfidence(_ confidence: MetricConfidence) -> Double {
        switch confidence {
        case .high: return 1.0
        case .medium: return 0.7
        case .low: return 0.4
        }
    }

    public static func readinessDecision(
        from dashboard: DashboardSummary,
        signals: [TodayHealthSignal],
        recentStrengthSummary: RecentTrainingSummary?
    ) -> (decision: ReadinessDecisionKind, confidence: Double, reasons: [String]) {
        var reasons: [String] = []
        if !dashboard.recovery.hasData {
            return (.reduce, 0.0, ["恢复基线数据不足，先按保守方案执行。"])
        }

        let recConf = dashboard.recovery.hasData ? numericConfidence(dashboard.recovery.confidence) : 0.0
        let sleepConf = dashboard.sleepScore.hasData ? numericConfidence(dashboard.sleepScore.confidence) : 0.0
        let stressConf = dashboard.stress.hasData ? numericConfidence(dashboard.stress.confidence) : 0.0

        // Weighted by per-source confidence, capped at 1.0, with no artificial
        // floor: sparse or low-confidence data must surface as genuinely low
        // readiness confidence rather than being coerced upward. Previously a
        // `max(0.3, …)` floor hid missing/low data, presenting pseudo-calibrated
        // certainty to the user.
        let computedConf = min(1.0, 0.50 * recConf + 0.30 * sleepConf + 0.20 * stressConf)
        let dynamicConfidence = computedConf

        if let first = dashboard.recovery.reasons.first {
            reasons.append(first)
        }
        // Layer 2：三年长线证据（只作为理由补充，不改变决策分支）。
        // 深度专项批次 1：此前只取 .first（恒为 RHR 一行），
        // 改为前两行（RHR + HRV），让三年视角在决策理由里可见。
        if let report = dashboard.longTermBaselines {
            let lines = LongTermBaselineEngine.contextLines(report).prefix(2)
            for line in lines {
                reasons.append("长线参照：\(line)")
            }
            // 深度专项批次 3：同月三年 MAD 带（只报低于下限的保守信号）。
            if let hrv = dashboard.recoveryMetrics.hrvMilliseconds,
               let band = report.monthlyHRV?.band(for: Calendar.current.component(.month, from: dashboard.date)),
               band.mad > 0,
               hrv < band.median - 1.5 * band.mad {
                reasons.append("长线参照：HRV \(Int(hrv.rounded())) ms 低于同期三年 \(band.month) 月带下限（约 \(Int((band.median - 1.5 * band.mad).rounded())) ms）")
            }
        }
        let thresholds = PersonalBaselineEngine.resolveThresholds()
        if dashboard.recovery.score < thresholds.recoveryRest {
            reasons.append("Recovery \(Int(dashboard.recovery.score.rounded())) is below the recovery-day threshold (\(thresholds.source)).")
            return (.recover, dynamicConfidence, reasons)
        }
        if dashboard.sleepScore.hasData, dashboard.sleepScore.score < thresholds.sleepRest {
            reasons.append("Sleep score \(Int(dashboard.sleepScore.score.rounded())) is limiting readiness (\(thresholds.source)).")
            return (.recover, dynamicConfidence, reasons)
        }
        if dashboard.stress.hasData, dashboard.stress.stressIndex > 75 {
            reasons.append("Physiological stress is elevated.")
            return (.recover, dynamicConfidence, reasons)
        }
        if !dashboard.sleepScore.hasData || !dashboard.stress.hasData {
            // 关键上下文缺失时保守降级，避免在信息不足时给出「可训练」结论。
            reasons.append("睡眠或压力数据缺失，按保守方案执行。")
            return (.reduce, dynamicConfidence, reasons)
        }
        if let summary = recentStrengthSummary,
           summary.localFatigue.values.contains(where: { $0.fatigueLevel == "high" }) {
            reasons.append("Local muscle fatigue is high from recent strength work.")
            return (.swap, dynamicConfidence, reasons)
        }
        if dashboard.recovery.score < thresholds.recoveryCaution
            || (dashboard.sleepScore.hasData && dashboard.sleepScore.score < thresholds.sleepCaution) {
            reasons.append("Recovery or sleep is not low enough for rest, but not strong enough for full volume (\(thresholds.source)).")
            return (.reduce, dynamicConfidence, reasons)
        }
        if dashboard.strain.hasData, dashboard.strain.score > Double(dashboard.strain.recommendedRange.upperBound) {
            reasons.append("Current strain is already above today's target range.")
            return (.reduce, dynamicConfidence, reasons)
        }

        if reasons.isEmpty {
            reasons.append("Recovery, sleep, and strain are within an actionable range.")
        }
        return (.keep, dynamicConfidence, reasons)
    }

    private static func keySignals(
        from dashboard: DashboardSummary,
        recentStrengthSummary: RecentTrainingSummary?
    ) -> [TodayHealthSignal] {
        var signals: [TodayHealthSignal] = []
        signals.append(TodayHealthSignal(
            id: "recovery",
            title: "Recovery",
            value: dashboard.recovery.hasData ? "\(Int(dashboard.recovery.score.rounded()))" : "--",
            interpretation: dashboard.recovery.reasons.first ?? "恢复数据仍在建立基线。"
        ))
        signals.append(TodayHealthSignal(
            id: "sleep",
            title: "Sleep",
            value: dashboard.sleepScore.hasData ? "\(Int(dashboard.sleepScore.score.rounded()))" : "--",
            interpretation: dashboard.sleepScore.reasons.first ?? "睡眠数据不足。"
        ))
        let hrvValue = dashboard.recoveryMetrics.hrvMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "--"
        signals.append(TodayHealthSignal(
            id: "hrv",
            title: "HRV vs baseline",
            value: hrvValue,
            interpretation: hrvInterpretation(dashboard)
        ))
        let rhrValue = dashboard.recoveryMetrics.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--"
        signals.append(TodayHealthSignal(
            id: "rhr",
            title: "Resting HR",
            value: rhrValue,
            interpretation: rhrInterpretation(dashboard)
        ))
        signals.append(TodayHealthSignal(
            id: "strain",
            title: "Training load",
            value: dashboard.strain.hasData ? "\(Int(dashboard.strain.score.rounded()))" : "--",
            interpretation: dashboard.strain.reasons.first ?? "负荷数据不足。"
        ))
        if let summary = recentStrengthSummary, !summary.muscleGroupSets.isEmpty {
            let top = summary.muscleGroupSets.sorted { $0.value > $1.value }.first
            signals.append(TodayHealthSignal(
                id: "local_fatigue",
                title: "Local fatigue",
                value: top.map { "\($0.key) \($0.value) sets" } ?? "--",
                interpretation: "近期肌群组数会影响今天是否换部位或减量。"
            ))
        }
        return signals
    }

    private static func actions(for decision: ReadinessDecisionKind, dashboard: DashboardSummary) -> [TodayAction] {
        // 注：kind 用于今日页图标与路由，detail 用于 coach 问题预填——二者是活的，
        // 与 D7/D8 的死字段不同，保留。
        switch decision {
        case .keep:
            return [
                TodayAction(id: "start_training", kind: .training, title: "开始今日训练", detail: "按计划执行，训练中保留 1-2 次余力。", destination: "training", isPrimary: true),
                TodayAction(id: "why_this", kind: .insight, title: "查看证据", detail: "打开 HRV、睡眠、负荷和恢复解释。", destination: "evidence", isPrimary: false)
            ]
        case .reduce:
            return [
                TodayAction(id: "reduce_volume", kind: .training, title: "训练容量降低 20%", detail: "保留动作模式，减少组数或 RPE。", destination: "training", isPrimary: true),
                TodayAction(id: "check_in", kind: .checkIn, title: "记录疲劳/酸痛", detail: "把主观反馈写入今天的上下文。", destination: "journal", isPrimary: false)
            ]
        case .swap:
            return [
                TodayAction(id: "swap_workout", kind: .training, title: "替换训练部位", detail: "避开高疲劳肌群，改做低冲击训练。", destination: "training", isPrimary: true),
                TodayAction(id: "ask_coach_swap", kind: .coach, title: "让 Coach 改计划", detail: dashboard.trainingDecision.coachQuestion, destination: "coach", isPrimary: false)
            ]
        case .recover:
            return [
                TodayAction(id: "recovery_plan", kind: .recovery, title: "执行恢复日", detail: "轻量 activity、补水、晚间提前睡眠。", destination: "recovery", isPrimary: true),
                TodayAction(id: "why_this", kind: .insight, title: "为什么这样安排", detail: "查看 HRV、RHR、睡眠和压力证据。", destination: "evidence", isPrimary: false)
            ]
        }
    }

    private static func localMorningBrief(
        from dashboard: DashboardSummary,
        decision: (decision: ReadinessDecisionKind, confidence: Double, reasons: [String]),
        generatedAt: Date
    ) -> CoachArtifact {
        CoachArtifact(
            type: .morningBrief,
            title: "今日身体简报",
            summary: summary(for: decision.decision, dashboard: dashboard),
            createdAt: generatedAt,
            relatedDate: dashboard.date,
            decision: decision.decision.rawValue,
            confidence: decision.confidence,
            reasons: decision.reasons.prefix(3).map {
                CoachArtifactReason(signal: "readiness", value: decision.decision.rawValue, explanation: $0)
            },
            actions: actions(for: decision.decision, dashboard: dashboard).map {
                CoachArtifactAction(type: $0.destination, label: $0.title, payload: ["action_id": $0.id])
            },
            sourceContextHash: ContentHash.hash("\(dashboard.date.timeIntervalSince1970)-\(dashboard.recovery.score)-\(dashboard.sleepScore.score)-\(dashboard.strain.score)")
        )
    }

    private static func title(for decision: ReadinessDecisionKind, dashboard: DashboardSummary) -> String {
        switch decision {
        case .keep: return "状态可训练"
        case .reduce: return "可训练，但建议减量"
        case .swap: return "建议换训练内容"
        case .recover: return "恢复优先"
        }
    }

    private static func summary(for decision: ReadinessDecisionKind, dashboard: DashboardSummary) -> String {
        let recovery = Int(dashboard.recovery.score.rounded())
        let sleep = Int(dashboard.sleepScore.score.rounded())
        let strain = Int(dashboard.strain.score.rounded())
        switch decision {
        case .keep:
            return "恢复 \(recovery)、睡眠 \(sleep)、负荷 \(strain)。今天可以按计划训练，保持技术质量。"
        case .reduce:
            return "恢复 \(recovery)、睡眠 \(sleep)、负荷 \(strain)。今天不需要完全休息，但应降低容量或强度。"
        case .swap:
            return "恢复 \(recovery)、睡眠 \(sleep)、负荷 \(strain)。近期局部疲劳偏高，建议替换训练内容。"
        case .recover:
            return "恢复 \(recovery), 睡眠 \(sleep)、负荷 \(strain)。今天优先恢复，避免高强度训练。"
        }
    }

    private static func hrvInterpretation(_ dashboard: DashboardSummary) -> String {
        guard let hrv = dashboard.recoveryMetrics.hrvMilliseconds,
              let baseline = dashboard.recoveryBaseline.hrvMilliseconds,
              baseline > 0 else {
            return "HRV 基线仍在建立。"
        }
        let delta = (hrv - baseline) / baseline
        if delta < -0.10 { return "HRV 低于个人基线，今天宜结合睡眠和主观状态保守安排训练。" }
        if delta > 0.10 { return "HRV 高于个人基线，恢复信号较积极。" }
        return "HRV 接近个人基线。"
    }

    private static func rhrInterpretation(_ dashboard: DashboardSummary) -> String {
        guard let rhr = dashboard.recoveryMetrics.restingHeartRate,
              let baseline = dashboard.recoveryBaseline.restingHeartRate else {
            return "静息心率基线仍在建立。"
        }
        if rhr >= baseline + 4 { return "静息心率高于基线，可能存在恢复压力。" }
        if rhr <= baseline - 3 { return "静息心率低于基线，恢复信号较好。" }
        return "静息心率接近基线。"
    }

    private static func aggregateConfidence(dashboard: DashboardSummary, signals: [TodayHealthSignal]) -> DataConfidence {
        if !dashboard.recovery.hasData { return .unavailable }
        if dashboard.recoveryMetrics.hrvMilliseconds == nil || dashboard.recoveryMetrics.restingHeartRate == nil {
            return .low
        }
        if [dashboard.recovery.confidence, dashboard.sleepScore.confidence, dashboard.strain.confidence].contains(.low) {
            return .low
        }
        if [dashboard.recovery.confidence, dashboard.sleepScore.confidence, dashboard.strain.confidence].contains(.medium) {
            return .medium
        }
        return .high
    }
}
