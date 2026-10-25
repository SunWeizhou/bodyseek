import SwiftUI

// MARK: - Training Rhythm Surface

/// Training is a decision surface, not an in-session logger. The iPhone owns
/// the next-focus decision and its boundaries; Apple Watch owns execution.
struct TrainingHeroSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let todaySession: TrainingDay?
    let todayPlan: DailyOperatingPlanRecord?
    /// Canonical projection from `DailyIntelligenceAssemblyModule`; the persisted
    /// plan remains the preferred payload when its matching record is available.
    let dailyDecision: DailyTrainingDecision?
    let activePlan: TrainingPlanRecord?
    let rotationFocus: String?
    let preferredSessionMinutes: Int
    let summary: RecentTrainingSummary
    let evidenceMetrics: [String]
    let heatmapWeeks: [TrainingHeatmapWeek]
    let futureRecommendations: [RotationDayRecommendation]
    let aiFutureDays: [RotationDayRecommendation]?
    let isPlanningWithAI: Bool
    /// 联通专项批次 2：主流程一句话个人洞察（身体模型断言；nil = 不显示）。
    let personalInsight: String?
    let selectedDate: Date
    let dashboard: DashboardSummary
    var onRefresh: (() async -> Void)?
    let onRequestAIPlan: () -> Void
    let onDiscussWithCoach: () -> Void

    @State private var isRevealed = false
    @State private var showEvidence = false
    @State private var showRhythm = false

    private var payload: DailyOperatingPlanPayload? {
        todayPlan?.operatingPlanPayload
    }

    private var decision: DailyTrainingDecisionType {
        payload?.decision ?? dailyDecision?.decision ?? .reduce
    }

    private var focus: TrainingRotationFocus? {
        TrainingRotationFocus.resolve(
            from: [todaySession?.title, todaySession?.focus, activePlan?.title, rotationFocus]
                .compactMap { $0 }
                .joined(separator: " ")
        )
    }

    private var focusLine: String {
        if decision == .rest { return "优先恢复 · 轻活动" }
        if let focus { return "下一站 · \(focus.title)" }
        return "自由训练"
    }

    private var boundaryLine: String {
        [volumeText, "RPE \(rpeText)", durationText]
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }

    private var compactBoundaryLine: String {
        [volumeText, "RPE \(rpeText)"]
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            decisionSummaryRow
                .padding(.top, 20)

            if let personalInsight, !personalInsight.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text(personalInsight)
                        .font(VelaTheme.footnote().weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                .padding(.horizontal, VelaTheme.compactCardPadding)
                .padding(.vertical, VelaTheme.space2)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                )
                .padding(.top, 14)
            }

            Button(action: onDiscussWithCoach) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(width: 28, height: 28)
                        .background(VelaTheme.rhythmDeep, in: Circle())

                    Text("和 Vela 调整训练计划")
                        .font(VelaTheme.callout().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                }
                .padding(.horizontal, VelaTheme.space3)
                .padding(.vertical, VelaTheme.space2)
                .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                }
            }
            .buttonStyle(.cardPress)
            .padding(.top, 14)
        }
        .padding(.horizontal, VelaTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(alignment: .top) {
            TrainingAmbientField(decision: decision)
                .frame(height: 360)
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !isRevealed else { return }
            if reduceMotion {
                isRevealed = true
            } else {
                withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                    isRevealed = true
                }
            }
        }
    }

    private var planStateLabel: String {
        guard todayPlan != nil || dailyDecision != nil else { return "采用保守边界" }
        switch decision {
        case .keep: return "保持计划"
        case .reduce: return "建议减量"
        case .swap: return "建议换部位"
        case .rest: return "恢复优先"
        }
    }

    private var volumeText: String {
        let multiplier = payload?.volumeMultiplier ?? dailyDecision?.volumeMultiplier ?? 0.60
        return "容量 \(Int((multiplier * 100).rounded()))%"
    }

    private var rpeText: String {
        let cap = payload?.intensityCap ?? dailyDecision?.intensityCap ?? 7
        return "≤ \(cap)"
    }

    private var durationText: String {
        guard decision != .rest else { return "轻活动" }
        return todaySession.map { "\($0.durationMinutes) 分" } ?? "\(preferredSessionMinutes) 分"
    }

    private var boundaryItems: [String] {
        [volumeText, "RPE \(rpeText)", durationText]
            .filter { $0 != "--" && $0 != "RPE --" }
    }

    /// Decision first: one focus and a few execution boundaries. Supporting
    /// history and evidence stay behind progressive disclosure.
    private var decisionSummaryRow: some View {
        VStack(alignment: .leading, spacing: VelaTheme.space3) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision == .rest ? "今天" : "下一站")
                            .font(VelaTheme.caption1().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Text(planStateLabel)
                            .font(VelaTheme.caption2().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VelaTheme.rhythmMist, in: Capsule())
                            .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(decision == .rest ? "今天" : "下一站")
                            .font(VelaTheme.caption1().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Text(planStateLabel)
                            .font(VelaTheme.caption2().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VelaTheme.rhythmMist, in: Capsule())
                            .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? VelaTheme.minimumHitTarget : 0, alignment: .leading)

            Text(decision == .rest ? "恢复" : (focus?.title ?? "设置训练轮转"))
                .font(VelaTheme.title2().weight(.semibold))
                .tracking(-0.4)
                .foregroundStyle(VelaTheme.rhythmInk)
                .minimumScaleFactor(0.8)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        boundaryPills
                    }
                } else {
                    HStack(spacing: 8) {
                        boundaryPills
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var boundaryPills: some View {
        ForEach(boundaryItems, id: \.self) { item in
            Text(item)
                .font(VelaTheme.callout().weight(.semibold).monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInk)
                .padding(.horizontal, VelaTheme.space3)
                .padding(.vertical, VelaTheme.space2)
                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? VelaTheme.minimumHitTarget : 0, alignment: .leading)
                .background(VelaTheme.rhythmCanvasRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
        }
    }

    var rhythmDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                    showRhythm.toggle()
                }
            } label: {
                HStack {
                    Text("最近 5 周训练节律")
                        .font(VelaTheme.callout().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .rotationEffect(.degrees(showRhythm ? 180 : 0))
                }
                .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showRhythm ? "已展开" : "已折叠")

            if showRhythm {
                TrainingRhythmHeatmap(
                    weeks: heatmapWeeks,
                    revealProgress: isRevealed ? 1 : 0
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 训练规划卡：「今天（今日决定）+ 明 + 后」，本地推荐器即时给出，
    /// 可点「Vela 规划」让 Coach 结合数据复核。
    @ViewBuilder
    var futureRecommendationStrip: some View {
        let cards = aiFutureDays ?? Array(futureRecommendations.prefix(2))
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("训练规划")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)

                    if let aiDays = aiFutureDays, !aiDays.isEmpty {
                        Text("Vela 建议")
                            .font(VelaTheme.caption2().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VelaTheme.rhythmDeep, in: Capsule())
                    }

                    Spacer(minLength: 6)

                    Button(action: onRequestAIPlan) {
                        HStack(spacing: 4) {
                            if isPlanningWithAI {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: aiFutureDays == nil ? "sparkles" : "arrow.clockwise")
                                    .font(VelaTheme.caption2().weight(.semibold))
                            }
                            Text(aiFutureDays == nil ? "Vela 规划" : "重新生成")
                                .font(VelaTheme.caption2().weight(.semibold))
                        }
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(VelaTheme.rhythmCanvasRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlanningWithAI)
                    .frame(minHeight: VelaTheme.minimumHitTarget)
                    .accessibilityLabel("让 Vela 结合数据规划训练")
                }

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: VelaTheme.cardGap) {
                            todayPlanCard()
                            ForEach(Array(cards.prefix(2).enumerated()), id: \.offset) { _, recommendation in
                                futurePlanCard(recommendation)
                            }
                        }
                    } else {
                        HStack(spacing: VelaTheme.cardGap) {
                            todayPlanCard()
                            ForEach(Array(cards.prefix(2).enumerated()), id: \.offset) { _, recommendation in
                                futurePlanCard(recommendation)
                            }
                        }
                    }
            }
        }
    }

    /// 今日计划日的动作清单（plannedExercisesJSON 解码——「练什么」的具体内容）。
    private var todayExercises: [WorkoutTemplateExercise] {
        guard let todaySession,
              let data = todaySession.plannedExercisesJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([WorkoutTemplateExercise].self, from: data) else {
            return []
        }
        return list
    }

    /// 具体动作预览行：前 2 个动作的组×次 + 剩余数 + 时长。
    private var todayExerciseLine: String {
        guard !todayExercises.isEmpty else { return "" }
        let preview = todayExercises.prefix(2).map { "\($0.name) \($0.targetSets)×\($0.targetReps)" }
        var line = preview.joined(separator: " · ")
        if todayExercises.count > 2 { line += " +\(todayExercises.count - 2)" }
        if let session = todaySession { line += " · \(session.durationMinutes) 分" }
        return line
    }

    /// 今天卡片：今日决策 + 目标部位/休息 + 具体动作/边界。
    private func todayPlanCard() -> some View {
        let isRest = decision == .rest
        let groupsText = isRest ? "休息" : (focus?.shortTitle ?? "训练")
        let primaryNote: String = {
            if isRest { return "优先恢复 · 轻活动" }
            if !todayExerciseLine.isEmpty { return todayExerciseLine }
            return focusLine
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("今天")
                    .font(VelaTheme.footnote().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(planStateLabel)
                    .font(VelaTheme.caption2().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(VelaTheme.rhythmMist, in: Capsule())
                    .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
            }
            Text(groupsText)
                .font(VelaTheme.headline().weight(.bold))
                .foregroundStyle(isRest ? VelaTheme.rhythmInk : VelaTheme.rhythmDeep)
            Text(primaryNote)
                .font(VelaTheme.footnote())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VelaTheme.compactCardPadding)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
    }

    private func futurePlanCard(_ recommendation: RotationDayRecommendation) -> some View {
        let label: String
        switch recommendation.dayOffset {
        case 1: label = "明天"
        case 2: label = "后天"
        default: label = "第\(recommendation.dayOffset)天"
        }
        let isRest = recommendation.groups.isEmpty
        let groupsText = isRest
            ? "休息"
            : recommendation.groups.map(TrainingHeatmapData.shortLabel).joined(separator: "+")

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(VelaTheme.footnote().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                if recommendation.source == "ai" {
                    Text("AI")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(VelaTheme.rhythmMist, in: Capsule())
                        .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                }
            }
            Text(groupsText)
                .font(VelaTheme.headline().weight(.bold))
                .foregroundStyle(isRest ? VelaTheme.rhythmInk : VelaTheme.rhythmDeep)
            Text(isRest ? recommendation.note : shortNote(recommendation.note))
                .font(VelaTheme.footnote())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VelaTheme.compactCardPadding)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
    }

    /// 「依据：48h 2 组 · 7 天 6 组」→ 卡内短文案「48h 2组 · 7天 6组」。
    private func shortNote(_ note: String) -> String {
        note
            .replacingOccurrences(of: "依据：", with: "")
            .replacingOccurrences(of: " · ", with: " · ")
    }

    private var watchExecutionNote: some View {
        HStack(spacing: 11) {
            Image(systemName: "applewatch")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 32, height: 32)
                .background(VelaTheme.rhythmMist, in: Circle())

            Text("Apple Watch 记录，结束后自动同步")
                .font(VelaTheme.footnote().weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 「为什么」证据层：一行最强依据 + 点环/点箭头展开完整理由与评分。
    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                    showEvidence.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(VelaTheme.rhythmDeep)
                        .frame(width: 2, height: 13)
                    Text(evidenceLine)
                        .font(VelaTheme.callout().weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .rotationEffect(.degrees(showEvidence ? 90 : 0))
                }
                .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("今日训练依据，\(evidenceLine)")

            if showEvidence {
                VStack(alignment: .leading, spacing: 8) {
                    // 联通专项批次 2：主流程一句话个人洞察（身体模型断言）。
                    if let personalInsight {
                        NavigationLink(destination: BodyModelDetailView(
                            selectedDate: selectedDate,
                            dashboard: dashboard,
                            onRefresh: onRefresh
                        )) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(VelaTheme.caption1().weight(.semibold))
                                    .foregroundStyle(VelaTheme.rhythmDeep)
                                    .padding(.top, 2)
                                Text(personalInsight)
                                    .font(VelaTheme.callout().weight(.medium))
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(VelaTheme.caption2().weight(.semibold))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if !decisionReasons.isEmpty {
                        ForEach(Array(decisionReasons.enumerated()), id: \.offset) { _, reason in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(VelaTheme.rhythmInkSecondary)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(reason)
                                    .font(VelaTheme.callout())
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !evidenceMetrics.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(evidenceMetrics, id: \.self) { metric in
                                Text(metric)
                                    .font(VelaTheme.caption1().weight(.semibold).monospacedDigit())
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(VelaTheme.rhythmCanvasRaised, in: Capsule())
                                    .overlay(Capsule().strokeBorder(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                            }
                        }
                    }
                }
                .padding(12)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 一行最强依据（决策理由优先，其次局部疲劳，无数据时用保守边界说明）。
    private var evidenceLine: String {
        if let first = decisionReasons.first {
            return first
        }
        if let top = summary.localFatigue.values.max(by: { $0.setsLast7d < $1.setsLast7d }),
           top.setsLast7d > 0 {
            return "\(localizedMuscleGroup(top.muscleGroup)) 7 天 \(top.setsLast7d) 组，今天优先避开或减量"
        }
        return "数据积累中，先按保守边界执行"
    }

    private var decisionReasons: [String] {
        let persisted = todayPlan?.operatingPlanReasons ?? []
        return persisted.isEmpty ? (dailyDecision?.reasons ?? []) : persisted
    }
}

private struct TrainingAmbientField: View {
    let decision: DailyTrainingDecisionType

    var body: some View {
        VelaTheme.rhythmCanvas
    }
}

private enum TrainingRotationFocus: String, CaseIterable, Identifiable {
    case back, chest, shoulders, legs, accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: "背部"
        case .chest: "胸部"
        case .shoulders: "肩部"
        case .legs: "腿部"
        case .accessories: "手臂与核心"
        }
    }

    var shortTitle: String {
        switch self {
        case .back: "背"
        case .chest: "胸"
        case .shoulders: "肩"
        case .legs: "腿"
        case .accessories: "臂"
        }
    }

    static func resolve(from raw: String) -> TrainingRotationFocus? {
        let value = raw.lowercased()
        if ["back", "pull", "背", "划船", "下拉"].contains(where: value.contains) { return .back }
        if ["chest", "push", "胸", "卧推"].contains(where: value.contains) { return .chest }
        if ["shoulder", "deltoid", "肩", "推举"].contains(where: value.contains) { return .shoulders }
        if ["leg", "quad", "hamstring", "glute", "腿", "蹲"].contains(where: value.contains) { return .legs }
        if ["arm", "biceps", "triceps", "core", "abs", "手臂", "腹", "核心"].contains(where: value.contains) { return .accessories }
        return nil
    }
}

/// 未来一天的最佳训练部位推荐（结合真实肌群疲劳 + 恢复状态 + 轮转交替）。
struct RotationDayRecommendation: Equatable {
    let dayOffset: Int       // 1=明天, 2=后天, 3=大后天
    let groups: [String]     // 肌群键；空数组 = 建议休息/暂无数据
    let note: String
    var source: String = "local"   // "local" 本机推荐器 / "ai" Coach 参与
}

/// 纯函数推荐器：不依赖计划，无计划同样成立。
enum TrainingRotationRecommender {
    static func upcomingDays(
        localFatigue: [String: LocalMuscleFatigue],
        decision: DailyTrainingDecisionType,
        recoveryScore: Double?,
        recoveryRestThreshold: Double = 50,
        rotationFocuses: [String] = TrainingRotationResolver.defaultFocuses,
        currentFocus: String? = nil,
        days: Int = 3,
        calendar: Calendar = .current
    ) -> [RotationDayRecommendation] {
        // 候选：疲劳高（避开）的肌群排除；其余按 48h 组数升序（最近练得少的优先）。
        let ranked = localFatigue
            .map(\.value)
            .filter { $0.fatigueLevel != "high" }
            .sorted {
                if $0.setsLast48h != $1.setsLast48h { return $0.setsLast48h < $1.setsLast48h }
                return $0.setsLast7d < $1.setsLast7d
            }

        var recommendations: [RotationDayRecommendation] = []
        var lastPick: String?
        let order = rotationFocuses.isEmpty ? TrainingRotationResolver.defaultFocuses : rotationFocuses
        let normalizedCurrent = currentFocus.map(TrainingRotationResolver.normalize)
        let currentIndex = normalizedCurrent.flatMap { order.firstIndex(of: $0) } ?? -1
        var rotationIndex = decision == .rest ? max(0, currentIndex) : (currentIndex + 1 + order.count) % order.count
        var pendingRecoveryDay = false
        if let recoveryScore, recoveryScore < recoveryRestThreshold, decision != .rest {
            pendingRecoveryDay = true
        }

        for offset in 1...days {
            if pendingRecoveryDay {
                recommendations.append(RotationDayRecommendation(
                    dayOffset: offset,
                    groups: [],
                    note: "恢复偏低，建议休息或轻活动"
                ))
                pendingRecoveryDay = false
                continue
            }
            let rotationPick: String? = if normalizedCurrent != nil || ranked.isEmpty {
                (0..<order.count)
                    .map { order[(rotationIndex + $0) % order.count] }
                    .first { focus in
                        !TrainingRotationResolver.muscleKeys(for: focus).contains { key in
                            localFatigue[key]?.fatigueLevel == "high"
                        } && focus != lastPick
                    }
            } else {
                nil
            }
            let preferred = ranked.first { $0.muscleGroup != lastPick } ?? ranked.first
            if let focus = rotationPick {
                lastPick = focus
                rotationIndex = ((order.firstIndex(of: focus) ?? rotationIndex) + 1) % order.count
                let fatigue = localFatigue[focus]
                let note = fatigue.map { "依据：48h \($0.setsLast48h) 组 · 7 天 \($0.setsLast7d) 组" }
                    ?? "按你的轮转继续"
                recommendations.append(RotationDayRecommendation(
                    dayOffset: offset,
                    groups: [focus],
                    note: note
                ))
            } else if let pick = preferred {
                lastPick = pick.muscleGroup
                recommendations.append(RotationDayRecommendation(
                    dayOffset: offset,
                    groups: [pick.muscleGroup],
                    note: "依据：48h \(pick.setsLast48h) 组 · 7 天 \(pick.setsLast7d) 组"
                ))
            } else {
                recommendations.append(RotationDayRecommendation(
                    dayOffset: offset,
                    groups: [order[rotationIndex]],
                    note: "按你的轮转继续"
                ))
                rotationIndex = (rotationIndex + 1) % order.count
            }
        }
        return recommendations
    }
}

/// 日历热力图的一天：真实训练强度分档 + 当天练过的肌群 + 有氧时长。
struct TrainingHeatmapDay: Equatable {
    let date: Date
    let tier: Int          // 0 无训练 / 1 轻度 / 2 中度 / 3 高
    let groups: [String]   // 力量肌群键（仅 App 内手动力量记录可解析出肌群）
    let cardioMinutes: Double
    let activityNames: [String]  // 当天训练类型（力量训练/跑步/骑行…）
    let isFuture: Bool
}

struct TrainingHeatmapWeek: Equatable {
    let days: [TrainingHeatmapDay]
}

/// 热力图数据构建（纯函数，可测试）：周一起始的 N 周网格。
protocol TrainingActivityDay {
    var date: Date { get }
    var workoutCount: Int? { get }
    var workoutDuration: Double? { get }
}

extension DailyHealthSummaryRecord: TrainingActivityDay {}
extension DailyHealthSnapshot: TrainingActivityDay {}

enum TrainingHeatmapData {
    static func weeks<Day: TrainingActivityDay>(
        endingAt: Date,
        weeks: Int = 5,
        records: [Day],
        workouts: [StrengthWorkoutRecord],
        summaries: [WorkoutSummary] = [],
        calendar: Calendar = .current
    ) -> [TrainingHeatmapWeek] {
        let endDay = calendar.startOfDay(for: endingAt)
        // 网格以「本周周日」为终点回推 N 周：每行周一起始，覆盖今天，
        // 本周剩余未来天用弱化色占位。
        let weekday = calendar.component(.weekday, from: endDay)   // 1=周日..7=周六
        let daysToSunday = (8 - weekday) % 7
        let lastSunday = calendar.date(byAdding: .day, value: daysToSunday, to: endDay) ?? endDay
        let firstDay = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: lastSunday) ?? lastSunday

        var groupsByDay: [Date: Set<String>] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startedAt)
            guard day >= firstDay, day <= endDay else { continue }
            let analysis = TrainingAnalyticsService().summarizeWorkout(workout.dto)
            for key in analysis.muscleGroupSets.keys {
                groupsByDay[day, default: []].insert(key)
            }
        }
        // 有氧分钟 + 当天训练类型：非力量类按天聚合分钟，所有类型记名字
        //（修复：此前 HK 同步来的力量/有氧既不进肌群也不进名字 → 点击显示「休息」）。
        var cardioByDay: [Date: Double] = [:]
        var namesByDay: [Date: [String]] = [:]
        for summary in summaries {
            let day = calendar.startOfDay(for: summary.start)
            guard day >= firstDay, day <= endDay else { continue }
            if isStrength(summary) {
                var names = namesByDay[day] ?? []
                if !names.contains("力量训练") { names.append("力量训练") }
                namesByDay[day] = names
            } else {
                cardioByDay[day, default: 0] += summary.end.timeIntervalSince(summary.start) / 60
                var names = namesByDay[day] ?? []
                let display = summary.activityName.isEmpty ? "训练" : summary.activityName
                if !names.contains(display) { names.append(display) }
                namesByDay[day] = names
            }
        }
        var recordsByDay: [Date: Day] = [:]
        for record in records {
            recordsByDay[calendar.startOfDay(for: record.date)] = record
        }

        var weeksOut: [TrainingHeatmapWeek] = []
        var current: [TrainingHeatmapDay] = []
        var day = firstDay
        for _ in 0..<(weeks * 7) {
            let isFuture = day > endDay
            let tier = isFuture ? 0 : Self.tier(
                workoutCount: recordsByDay[day]?.workoutCount,
                workoutDuration: recordsByDay[day]?.workoutDuration
            )
            let groups = groupsByDay[day].map { Array($0) } ?? []
            let cardio = cardioByDay[day] ?? 0
            let names = namesByDay[day] ?? []
            current.append(TrainingHeatmapDay(
                date: day,
                tier: tier,
                groups: groups,
                cardioMinutes: cardio,
                activityNames: names,
                isFuture: isFuture
            ))
            if current.count == 7 {
                weeksOut.append(TrainingHeatmapWeek(days: current))
                current = []
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return weeksOut
    }

    /// 力量类判定：本地力量日志/训记导入/手动记录/HK 合并镜像，或活动名含 strength/力量。
    static func isStrength(_ summary: WorkoutSummary) -> Bool {
        if let source = summary.source,
           ["strengthLog", "xunji", "manual", "healthKit+xunji", "healthKit+strengthLog"].contains(source) {
            return true
        }
        let name = summary.activityName.lowercased()
        return name.contains("strength") || name.contains("力量")
    }

    /// 周热力图和月热力图共用这一档。只看训练次数和时长。
    static func tier(workoutCount: Int?, workoutDuration: Double?) -> Int {
        let count = workoutCount ?? 0
        let duration = workoutDuration ?? 0
        if count >= 3 { return 3 }
        if count == 2 { return 2 }
        if count == 1 { return 1 }
        if duration > 45 { return 2 }
        if duration > 15 { return 1 }
        return 0
    }

    static func tier(for record: DailyHealthSummaryRecord?) -> Int {
        guard let record else { return 0 }
        return tier(workoutCount: record.workoutCount, workoutDuration: record.workoutDuration)
    }

    static func monthDayTiers(
        snapshots: [DailyHealthSnapshot],
        previousMonthStart: Date,
        currentMonthStart: Date,
        nextMonthStart: Date,
        calendar: Calendar = .current
    ) -> (previous: [Int: Int], current: [Int: Int]) {
        var previous: [Int: Int] = [:]
        var current: [Int: Int] = [:]
        for snapshot in snapshots where snapshot.date >= previousMonthStart && snapshot.date < nextMonthStart {
            let day = calendar.component(.day, from: snapshot.date)
            let tier = tier(workoutCount: snapshot.workoutCount, workoutDuration: snapshot.workoutDuration)
            if calendar.isDate(snapshot.date, equalTo: previousMonthStart, toGranularity: .month) {
                previous[day] = tier
            } else if calendar.isDate(snapshot.date, equalTo: currentMonthStart, toGranularity: .month) {
                current[day] = tier
            }
        }
        return (previous, current)
    }

    static func shortLabel(_ key: String) -> String {
        switch key.lowercased() {
        case "chest": return "胸"
        case "back": return "背"
        case "shoulders": return "肩"
        case "quads", "hamstrings", "glutes", "legs": return "腿"
        case "biceps", "triceps", "core", "abs", "arms", "accessories": return "臂"
        case "other": return "其"
        default: return String(key.prefix(2))
        }
    }
}

/// 训练节律日历热力图：最近几周训练强度色块，今天描边，点格子看当天练了什么。
private struct TrainingRhythmHeatmap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let weeks: [TrainingHeatmapWeek]
    let revealProgress: CGFloat

    @State private var selectedDay: TrainingHeatmapDay?

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 6) {
                        ForEach(week.days, id: \.date) { day in
                            cell(day)
                        }
                    }
                }
            }
            .opacity(revealProgress)

            // 固定高度详情区：选中显示当天内容，否则显示图例——不跳布局。
            ZStack {
                if let selected = selectedDay {
                    selectedInfo(selected)
                        .transition(.opacity)
                } else {
                    legend
                        .transition(.opacity)
                }
            }
            .frame(minHeight: VelaTheme.minimumHitTarget)
        }
    }

    private var legend: some View {
        HStack(spacing: 7) {
            Text("最近 5 周训练")
                .font(.caption2.weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
            legendCell(color: VelaTheme.rhythmMist.opacity(0.6), label: "无")
            legendCell(color: VelaTheme.rhythmGlow.opacity(0.55), label: "轻")
            legendCell(color: VelaTheme.rhythmGlow, label: "中")
            legendCell(color: VelaTheme.rhythmDeep, label: "高")
            Spacer()
            Text("点格子看当天")
                .font(.caption2)
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
        }
    }

    private func selectedInfo(_ day: TrainingHeatmapDay) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(VelaTheme.rhythmDeep)
                .frame(width: 6, height: 6)
            Text(detailText(day))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("再点取消")
                .font(.caption2)
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(VelaTheme.rhythmCanvasRaised.opacity(0.95), in: Capsule())
    }

    private func legendCell(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.8))
        }
    }

    private func cell(_ day: TrainingHeatmapDay) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        return Button {
                withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                    if day.isFuture {
                        selectedDay = nil
                    } else {
                        selectedDay = selectedDay == day ? nil : day
                    }
                }
            } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(cellColor(day))
                    .frame(height: 26)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(VelaTheme.rhythmInk, lineWidth: VelaTheme.hairlineWidth)
                        }
                        if selectedDay == day {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(VelaTheme.rhythmInkSecondary, lineWidth: VelaTheme.hairlineWidth)
                        }
                    }
                    .opacity(day.isFuture ? 0.14 : 1)
                    .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(detailText(day))
            .accessibilityValue(day.isFuture ? "未来日期" : (selectedDay == day ? "已选中" : "未选中"))
    }

    private func cellColor(_ day: TrainingHeatmapDay) -> Color {
        switch day.tier {
        case 3: return VelaTheme.rhythmDeep
        case 2: return VelaTheme.rhythmGlow
        case 1: return VelaTheme.rhythmGlow.opacity(0.55)
        default: return VelaTheme.rhythmMist.opacity(0.6)
        }
    }

    private func detailText(_ day: TrainingHeatmapDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        let dateText = formatter.string(from: day.date)

        var parts: [String] = []
        if !day.groups.isEmpty {
            let names = day.groups.map { localizedMuscleGroup($0) }.joined(separator: "、")
            parts.append("力量 \(names)")
        } else if day.activityNames.contains("力量训练") {
            parts.append("力量训练")
        }
        if day.cardioMinutes > 0 {
            parts.append("有氧 \(Int(day.cardioMinutes.rounded())) 分")
        }
        if parts.isEmpty, !day.activityNames.isEmpty {
            parts.append(day.activityNames.prefix(2).joined(separator: "、"))
        }
        if parts.isEmpty {
            return "\(dateText) · 休息"
        }
        return "\(dateText) · \(parts.joined(separator: " · "))"
    }
}

// MARK: - Local fatigue landscape

struct TrainingMuscleLandscape: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: RecentTrainingSummary
    /// 肌群键 → 最近 7 天逐日有效组数（index 0 = 最旧），数据加载时预计算。
    var muscleDailySets: [String: [Int]] = [:]
    /// 疲劳计算的锚定日（跟随页面浏览日期）。
    var endingAt: Date = Date()

    @State private var expandedGroup: String?

    private var groups: [(name: String, key: String, fatigue: LocalMuscleFatigue)] {
        summary.localFatigue
            .map { (localizedMuscleGroup($0.key), $0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.fatigue.fatigueLevel == rhs.fatigue.fatigueLevel {
                    return lhs.fatigue.setsLast7d > rhs.fatigue.setsLast7d
                }
                return fatigueRank(lhs.fatigue.fatigueLevel) > fatigueRank(rhs.fatigue.fatigueLevel)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VelaRhythmSectionHeader(
                eyebrow: "",
                title: "局部训练状态",
                actionTitle: nil,
                action: {}
            )

            if groups.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("完成并同步训练后，这里会判断各部位是否适合再次训练。")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    statusSummaryChips

                    VStack(spacing: 0) {
                        ForEach(Array(groups.prefix(6).enumerated()), id: \.offset) { index, group in
                            muscleRow(group)
                            if index < min(groups.count, 6) - 1 {
                                Rectangle()
                                    .fill(VelaTheme.rhythmMist)
                                    .frame(height: 0.75)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                }
            }
        }
    }

    /// 概览胶囊：可练 / 留量 / 避开的部位数量（真实计数，非装饰）。
    private var statusSummaryChips: some View {
        let counts = Dictionary(grouping: groups, by: { $0.fatigue.fatigueLevel })
            .mapValues(\.count)
        return HStack(spacing: 8) {
            statusChip(label: "可练", count: counts["low"] ?? 0, color: VelaTheme.rhythmDeep)
            statusChip(label: "留量", count: counts["moderate"] ?? 0, color: VelaTheme.rhythmWarm)
            statusChip(label: "避开", count: counts["high"] ?? 0, color: VelaTheme.statePoor)
            Spacer(minLength: 0)
        }
    }

    private func statusChip(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(VelaTheme.rhythmMist.opacity(0.6), in: Capsule())
    }

    private func muscleRow(_ group: (name: String, key: String, fatigue: LocalMuscleFatigue)) -> some View {
        let isExpanded = expandedGroup == group.key
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                    expandedGroup = isExpanded ? nil : group.key
                }
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            muscleSummary(group)
                            HStack(spacing: 10) {
                                fatigueBar(group)
                                fatigueStatus(group, isExpanded: isExpanded)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            muscleSummary(group)
                                .layoutPriority(1)
                            fatigueBar(group)
                            fatigueStatus(group, isExpanded: isExpanded)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            .accessibilityLabel("\(group.name)，\(fatigueLabel(group.fatigue.fatigueLevel))，过去四十八小时 \(group.fatigue.setsLast48h) 组，七天 \(group.fatigue.setsLast7d) 组")

            if isExpanded {
                MuscleExpandedPanel(
                    fatigue: group.fatigue,
                    dailySets: muscleDailySets[group.key] ?? [],
                    endingAt: endingAt
                )
                .padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func muscleSummary(_ group: (name: String, key: String, fatigue: LocalMuscleFatigue)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Text("48 小时 \(group.fatigue.setsLast48h) 组 · 7 天 \(group.fatigue.setsLast7d) 组")
                .font(.caption.weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fatigueBar(_ group: (name: String, key: String, fatigue: LocalMuscleFatigue)) -> some View {
        GeometryReader { proxy in
            let ratio = min(1, CGFloat(group.fatigue.setsLast7d) / 24)
            ZStack(alignment: .leading) {
                Capsule().fill(VelaTheme.rhythmMist).frame(height: 5)
                Capsule().fill(fatigueColor(group.fatigue.fatigueLevel))
                    .frame(width: max(5, proxy.size.width * ratio), height: 5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)
    }

    private func fatigueStatus(
        _ group: (name: String, key: String, fatigue: LocalMuscleFatigue),
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Text(fatigueLabel(group.fatigue.fatigueLevel))
                .font(.caption.weight(.semibold))
                .foregroundStyle(fatigueColor(group.fatigue.fatigueLevel))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .fixedSize()
    }

    private func fatigueRank(_ value: String) -> Int {
        switch value {
        case "high": return 3
        case "moderate": return 2
        default: return 1
        }
    }

    private func fatigueLabel(_ value: String) -> String {
        switch value {
        case "high": return "避开"
        case "moderate": return "留量"
        default: return "可练"
        }
    }

    private func fatigueColor(_ value: String) -> Color {
        switch value {
        case "high": VelaTheme.statePoor
        case "moderate": VelaTheme.rhythmWarm
        default: VelaTheme.rhythmDeep
        }
    }
}

/// 展开后的单肌群面板：建议 + 7 天逐日组数 + 下次可练时间。
private struct MuscleExpandedPanel: View {
    let fatigue: LocalMuscleFatigue
    let dailySets: [Int]
    let endingAt: Date

    private var maxDaily: Int {
        max(1, dailySets.max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(fatigue.recommendation)
                .font(.footnote.weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            dailyBars

            HStack(spacing: 8) {
                Label("下次可练：\(nextTrainingText)", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer(minLength: 4)
                Text("7 天容量 \(Int(fatigue.volumeLast7d.rounded())) kg")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmMist.opacity(0.45), in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
    }

    /// 最近 7 天逐日组数迷你柱（真实组数，空天为弱化占位）。
    private var dailyBars: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(dailySets.enumerated()), id: \.offset) { index, sets in
                VStack(spacing: 3) {
                    Text(sets > 0 ? "\(sets)" : "")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .frame(minHeight: 14)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(sets > 0 ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist.opacity(0.7))
                        .frame(height: max(4, CGFloat(sets) / CGFloat(maxDaily) * 34))
                    Text(dayLabel(index))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayLabel(_ index: Int) -> String {
        // 数组 index 0 = 锚定日 6 天前，最后一个 = 锚定日（endingAt）当天。
        guard dailySets.count > 0, index >= 0, index < dailySets.count else { return "" }
        let daysAgo = dailySets.count - 1 - index
        switch daysAgo {
        case 0: return "今"
        case 1: return "昨"
        default:
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: endingAt)) ?? endingAt
            let weekday = calendar.component(.weekday, from: day)   // 1=周日..7=周六
            let labels = ["日", "一", "二", "三", "四", "五", "六"]
            return labels[weekday - 1]
        }
    }

    private var nextTrainingText: String {
        switch fatigue.fatigueLevel {
        case "high": return "至少再休息 24–48 小时"
        case "moderate": return "明天可安排低容量"
        default: return "恢复信号允许时今天可练"
        }
    }
}

struct TrainingAnalysisPortal: View {
    let sessions: Int
    let totalDuration: String
    let cardioStatus: String
    /// 30 天耗力趋势（归一化折线点，可为空）。
    var sparkline: [CGPoint] = []
    /// 窗口内个人纪录数（去重后）。
    var prCount: Int = 0

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                    Text("深入分析")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("\(sessions) 次力量 · \(totalDuration) · 有氧\(cardioStatus)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
                if prCount > 0 {
                    Text("个人纪录 \(prCount) 项")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VelaTheme.rhythmDeep.opacity(0.12), in: Capsule())
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                PortalSparkline(points: sparkline)
                    .frame(width: 62, height: 30)
                Text("30 天耗力")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(15)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
    }
}

/// 迷你耗力趋势线：无数据时显示弱化虚线，不伪造曲线。
private struct PortalSparkline: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else {
                var dash = Path()
                dash.move(to: CGPoint(x: 6, y: size.height / 2))
                dash.addLine(to: CGPoint(x: size.width - 6, y: size.height / 2))
                context.stroke(dash, with: .color(VelaTheme.rhythmMist), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                return
            }
            var path = Path()
            for (index, point) in points.enumerated() {
                let x = point.x * size.width
                let y = point.y * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [VelaTheme.rhythmGlow, VelaTheme.rhythmDeep]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            if let last = points.last {
                let center = CGPoint(x: last.x * size.width, y: last.y * size.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
                    with: .color(VelaTheme.rhythmDeep)
                )
            }
        }
    }
}

struct TrainingPostWorkoutPrompt: View {
    let workout: WorkoutSummary
    let onAnnotate: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "applewatch")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 38, height: 38)
                .background(VelaTheme.rhythmMist, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("这次训练感觉如何？")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("\(workout.activityName) · \(workout.start.formatted(date: .omitted, time: .shortened)) · 可跳过")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("补充体感", action: onAnnotate)
                .font(.callout.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
        }
        .padding(14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
    }
}

/// 训练计划的建议入口：显示本机 BodyInterpreter 与 AI 练后边界生成的
/// 待确认提案数，点击进入计划页完成确认（ADR 0008：确认前不修改计划）。
struct TrainingProposalPortal: View {
    let proposals: [TrainingPlanAdaptationRecord]

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 44, height: 44)
                .background(VelaTheme.rhythmMist, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(proposals.isEmpty ? "当前没有待确认调整" : "\(proposals.count) 条待确认调整")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(previewLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("去确认")
                .font(.callout.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
    }

    private var previewLine: String {
        guard let first = proposals.first else {
            return "当前计划无需调整。Vela 只提出方案，任何修改都由你确认后生效。"
        }
        return "\(adjustmentLabel(first.adjustment)) · \(first.originalDayTitle) · \(first.reason)"
    }

    private func adjustmentLabel(_ adjustment: String) -> String {
        switch adjustment {
        case "keep": return "保持边界"
        case "reduce": return "建议减量"
        case "swap": return "建议替换"
        case "rest": return "建议休息"
        case "reschedule": return "建议改期"
        case "deloadWeek": return "建议减载周"
        default: return adjustment
        }
    }
}

struct TrainingPlanPortal: View {
    let planTitle: String?
    let nextFocus: String?
    let completedDays: Int
    let totalDays: Int
    /// 活跃计划的完整训练日序列（轮转条数据源）。
    var days: [TrainingDay] = []
    /// 今天解析到的计划日标题（轮转条高亮）。
    var todayTitle: String?
    /// 待用户确认的调整提案数（BodyInterpreter / AI 练后边界共用同一提案区）。
    var pendingProposalCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .stroke(VelaTheme.rhythmMist, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: completion)
                        .stroke(
                            VelaTheme.rhythmDeep,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(totalDays > 0 ? "\(completedDays)" : "—")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(planTitle ?? "建立你的训练轮转")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineLimit(2)

                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            if !days.isEmpty {
                rotationStrip
                    .padding(.top, 13)
            }

            if pendingProposalCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("\(pendingProposalCount) 条调整提案待你确认")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(VelaTheme.rhythmDeep.opacity(0.10), in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
                .padding(.top, 12)
            }
        }
        .padding(15)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
    }

    /// 计划训练日序列条：完成=实心勾、今天=描边、未来=弱化，最多 7 个 + 溢出计数。
    private var rotationStrip: some View {
        HStack(spacing: 7) {
            ForEach(Array(days.prefix(7).enumerated()), id: \.element.id) { _, day in
                rotationChip(day)
            }
            if days.count > 7 {
                Text("+\(days.count - 7)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func rotationChip(_ day: TrainingDay) -> some View {
        let isToday = todayTitle != nil && day.title == todayTitle && !day.isCompleted
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(day.isCompleted ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist.opacity(0.75))
                if day.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                } else {
                    Text(rotationShortLabel(day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? VelaTheme.rhythmDeep : VelaTheme.rhythmInkSecondary)
                }
            }
            .frame(width: 26, height: 26)
            .overlay {
                if isToday {
                    Circle()
                        .stroke(VelaTheme.rhythmInk, lineWidth: VelaTheme.hairlineWidth)
                }
            }
            Text("\(day.dayNumber)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(day.dayNumber) 训练日：\(day.title)，\(day.isCompleted ? "已完成" : isToday ? "今天" : "未完成")")
    }

    private func rotationShortLabel(_ day: TrainingDay) -> String {
        if day.focus == "rest" { return "休" }
        if let focus = TrainingRotationFocus.resolve(from: "\(day.title) \(day.focus)") {
            return focus.shortTitle
        }
        switch day.focus {
        case "cardio": return "有氧"
        case "flexibility", "mobility": return "活"
        default: return String(day.title.prefix(1))
        }
    }

    private var completion: CGFloat {
        guard totalDays > 0 else { return 0 }
        return min(1, CGFloat(completedDays) / CGFloat(totalDays))
    }

    private var detail: String {
        if let nextFocus, !nextFocus.isEmpty { return "当前建议：\(nextFocus)" }
        if totalDays > 0 { return "\(completedDays) / \(totalDays) 个训练日已完成" }
        return "让 Vela 根据恢复与偏好生成可调整计划"
    }
}

// MARK: - Training Status Section

/// 训练页的「恢复 / 负荷 / 压力」三指标状态条：始终展示、可点进详情，
/// 并同时把 Body State、身体模型与健康档案接到训练决策现场。
/// 三个指标与 `TrainingDecisionKernel` 使用同一 `DashboardSummary` 值，
/// 不在视图层另算口径。
struct TrainingStatusSection: View {
    let selectedDate: Date
    let dashboard: DashboardSummary
    let decision: DailyTrainingDecision?
    let onDiscussWithCoach: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var bodyState: BodyState { dashboard.bodyState }
    private var bodyModelState: BodyModelState? { dashboard.bodyModelState }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VelaRhythmSectionHeader(
                eyebrow: "",
                title: "训练状态",
                actionTitle: "问 Vela",
                action: onDiscussWithCoach
            )

            Text("\(readinessTitle(bodyState.readiness)) · \(statusDecisionTitle)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(VelaTheme.rhythmDeep.opacity(0.10), in: Capsule())

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        statusMetricCards
                    }
                } else {
                    HStack(spacing: 10) {
                        statusMetricCards
                    }
                }
            }

            VStack(spacing: 0) {
                NavigationLink(destination: BodyModelDetailView(
                    selectedDate: selectedDate,
                    dashboard: dashboard,
                    onRefresh: nil
                )) {
                    contextRow(
                        icon: "waveform.path.ecg",
                        title: "身体模型",
                        value: bodyModelMaturityTitle(bodyModelState?.maturity.overall),
                        detail: bodyModelState?.insightLine() ?? "正在从健康数据、训练事实与手记中学习你的个人反应。"
                    )
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(VelaTheme.rhythmMist)
                    .frame(height: 0.75)
                    .padding(.leading, 48)

                NavigationLink(destination: AccountSettingsView(dashboard: dashboard)) {
                    contextRow(
                        icon: "heart.text.square",
                        title: "生理特征档案",
                        value: profileSummary,
                        detail: "已参与评分与训练建议；手动值优先，Apple 健康兜底。"
                    )
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(VelaTheme.rhythmMist)
                    .frame(height: 0.75)
                    .padding(.leading, 48)

                NavigationLink(destination: UserWikiArchiveView()) {
                    contextRow(
                        icon: "books.vertical",
                        title: "长期健康档案",
                        value: bodyModelState == nil ? "待建立" : "已建档",
                        detail: "目标、约束与稳定模式由 Vela 记忆并供 Coach 引用。"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            }
        }
    }

    private var profileSummary: String {
        var values: [String] = []
        if let age = dashboard.extendedMetrics.age { values.append("\(age) 岁") }
        if let sex = dashboard.extendedMetrics.biologicalSex {
            values.append(sex == "male" ? "男" : sex == "female" ? "女" : "性别其他")
        }
        if let height = dashboard.extendedMetrics.heightCm { values.append("\(Int(height)) cm") }
        if let weight = dashboard.bodyMetrics.weightKilograms {
            values.append(String(format: "%.1f kg", weight))
        }
        return values.isEmpty ? "等待 Apple 健康或手动填写" : values.joined(separator: " · ")
    }

    private var recoveryDetail: String {
        guard dashboard.recovery.hasData else { return "等待 HRV / 静息心率基线" }
        let thresholds = PersonalBaselineEngine.resolveThresholds()
        let score = dashboard.recovery.score
        if score < thresholds.recoveryRest { return "低于休息阈值，恢复优先" }
        if score < thresholds.recoveryCaution { return "谨慎区间，训练保留余力" }
        return "支持计划训练"
    }

    private var strainDetail: String {
        guard dashboard.strain.hasData else { return "等待训练与活动负荷" }
        switch dashboard.strain.targetStatus {
        case .belowTarget: return "低于建议负荷区间"
        case .withinTarget: return "位于建议负荷区间"
        case .aboveTarget: return "高于区间，停止加量"
        }
    }

    private var stressDetail: String {
        guard dashboard.stress.hasData else { return "等待夜间生理信号" }
        let score = dashboard.stress.stressIndex
        if score > 75 { return "偏高，今天恢复优先" }
        if score >= 45 { return "中等，减少额外刺激" }
        return "处于可控区间"
    }

    @ViewBuilder
    private var statusMetricCards: some View {
        metricCard(
            metric: .recovery,
            title: "恢复",
            value: dashboard.recovery.formattedScore,
            detail: recoveryDetail,
            context: "越高越好",
            color: VelaTheme.rhythmInk
        )
        metricCard(
            metric: .strain,
            title: "负荷",
            value: dashboard.strain.formattedScore,
            detail: strainDetail,
            context: dashboard.strain.hasData
                ? "目标 \(dashboard.strain.recommendedRange.lowerBound)-\(dashboard.strain.recommendedRange.upperBound)"
                : "越高负荷越大",
            color: VelaTheme.rhythmInk
        )
        metricCard(
            metric: .stress,
            title: "压力",
            value: dashboard.stress.formattedScore,
            detail: stressDetail,
            context: "越高越需关注",
            color: VelaTheme.rhythmInk
        )
    }

    private func metricCard(
        metric: VelaMetricDetailView.MetricType,
        title: String,
        value: String,
        detail: String,
        context: String,
        color: Color
    ) -> some View {
        NavigationLink(destination: VelaMetricDetailView(
            metric: metric,
            selectedDate: selectedDate,
            dashboardSnapshot: dashboard
        )) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.75))
                }
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .monospacedDigit()
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(context)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.75))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("\(title) \(value)，\(detail)")
    }

    private func contextRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 32, height: 32)
                .background(VelaTheme.rhythmMist, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .lineLimit(2)
                }
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
        }
        .padding(.vertical, 11)
        .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func readinessTitle(_ readiness: BodyReadiness) -> String {
        switch readiness {
        case .ready: return "身体状态良好"
        case .caution: return "身体状态谨慎"
        case .recovering: return "身体状态恢复中"
        case .unknown: return "身体状态待评估"
        }
    }

    private var statusDecisionTitle: String {
        if let decision { return decisionTitle(decision) }
        switch dashboard.trainingDecision.kind {
        case .train: return "今日按计划训练"
        case .maintain: return "今日控制训练量"
        case .downshift: return "今日降低训练要求"
        case .rest, .recovery: return "今日恢复优先"
        case .protectSleep: return "优先保护睡眠"
        }
    }

    private func decisionTitle(_ decision: DailyTrainingDecision) -> String {
        switch decision.decision {
        case .keep: return "今日保持计划"
        case .reduce: return "今日建议减量"
        case .swap: return "今日建议换部位"
        case .rest: return "今日恢复优先"
        }
    }

    private func bodyModelMaturityTitle(_ level: BodyModelMaturityLevel?) -> String {
        switch level {
        case .seed: return "种子期"
        case .learning: return "学习期"
        case .stable: return "稳定期"
        case nil: return "建立中"
        }
    }
}

// MARK: - Training History Portal

struct TrainingHistoryPortal: View {
    let workouts: [WorkoutSummary]

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 44, height: 44)
                .background(VelaTheme.rhythmMist, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(workouts.isEmpty ? "等待训练记录同步" : "最近 \(min(workouts.count, 3)) 次训练")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(previewLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("查看全部")
                .font(.callout.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
    }

    private var previewLine: String {
        workouts.prefix(3).map { workout in
            let minutes = max(1, Int(workout.end.timeIntervalSince(workout.start) / 60))
            return "\(workout.activityName) \(minutes) 分"
        }.joined(separator: " · ")
    }
}

/// 训练历史完整列表：训练事实统一入口，提供详情与 Coach 分析两个去向。
struct TrainingHistoryView: View {
    let dashboard: DashboardSummary
    let recentWorkouts: [WorkoutSummary]
    let strengthWorkout: (WorkoutSummary) -> StrengthWorkoutRecord?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if recentWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        Text("暂无可读取的训练记录")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("Apple 健康、训记与力量补录合并后，会出现在这里。")
                            .font(.footnote)
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                } else {
                    RecentWorkoutsSection(
                        recentWorkouts: recentWorkouts,
                        limit: nil,
                        strengthWorkout: strengthWorkout,
                        dashboard: dashboard
                    )
                }

                Button {
                    VelaAppState.shared.routeToCoach(question: historyCoachQuestion, surface: .training)
                } label: {
                    Label("让 Vela 分析训练历史", systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: VelaTheme.minimumHitTarget)
                        .background(VelaTheme.rhythmDeep, in: Capsule())
                }
                .buttonStyle(.cardPress)
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("训练历史")
        .velaRhythmDetailChrome()
    }

    private var historyCoachQuestion: String {
        let recovery = dashboard.recovery.formattedScore
        let strain = dashboard.strain.formattedScore
        let stress = dashboard.stress.formattedScore
        return "请结合我过去 30 天的训练历史（\(recentWorkouts.count) 次可读记录）、恢复 \(recovery)、负荷 \(strain)、压力 \(stress) 和身体模型，分析训练趋势并给出下一次训练建议。"
    }
}
