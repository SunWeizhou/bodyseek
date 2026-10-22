import SwiftUI
import SwiftData

// MARK: - Plan Proposal Diff Card (P2)

/// 训练调整对比卡片：清晰对比原定训练与调整方案、生理推导依据，并提供闭环采纳操作。
struct PlanProposalDiffCard: View {
    let originalTitle: String
    let adjustment: String
    let reason: String
    let suggestedAlternative: String?
    var status: String = "proposed" // proposed, accepted, rejected
    var planTitle: String? = nil
    var onAccept: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 头部标题与状态胶囊
            headerRow

            // 2. 原计划 vs 调整后 对比容器 (Diff Container)
            diffContainer

            // 3. 生理推导依据与解释
            rationaleBox

            // 4. 交互操作栏 / 状态确认条
            actionBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardStandard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardStandard, style: .continuous)
                .stroke(status == "proposed" ? VelaTheme.rhythmDeep.opacity(0.3) : VelaTheme.rhythmMist, lineWidth: 0.85)
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmDeep)

            Text("Vela 计划调整提案")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmDeep)

            Spacer()

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case AdaptationStatus.accepted.rawValue:
            Label("已采纳", systemImage: "checkmark.circle.fill")
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(VelaTheme.rhythmInk.opacity(0.12), in: Capsule())
        case AdaptationStatus.rejected.rawValue:
            Label("已保持原计划", systemImage: "arrow.uturn.backward")
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.meta)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(VelaTheme.rhythmMist, in: Capsule())
        default:
            Label("待确认", systemImage: "clock.badge.exclamationmark")
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.softGold)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(VelaTheme.softGold.opacity(0.14), in: Capsule())
        }
    }

    private var diffContainer: some View {
        VStack(spacing: 10) {
            // 原定安排 (Before)
            HStack(spacing: 10) {
                Text("原计划")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.meta)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(VelaTheme.rhythmMist.opacity(0.8), in: Capsule())

                Text(originalTitle.isEmpty ? "今日训练" : originalTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)

                Spacer()

                Text("计划中")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }

            // 对比指示箭头 (Transition)
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmDeep.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(VelaTheme.rhythmCanvasRaised))
                    .overlay(Circle().stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
                Spacer()
            }

            // 建议调整 (After)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("调整后")
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VelaTheme.rhythmDeep, in: Capsule())

                    Text(adaptationLabel(adjustment))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)

                    Spacer()

                    adjustmentChip(adjustment)
                }

                if let alternative = suggestedAlternative, !alternative.isEmpty {
                    Text(alternative)
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(2)
                        .padding(.leading, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(VelaTheme.rhythmCanvas.opacity(0.6), in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.rhythmMist.opacity(0.6), lineWidth: 0.6)
        }
    }

    private var rationaleBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("生理依据与推导理由")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }

            Text(reason)
                .font(.system(.footnote, design: .default))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmMist.opacity(0.28), in: RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous))
    }

    @ViewBuilder
    private var actionBar: some View {
        if status == AdaptationStatus.proposed.rawValue {
            HStack(spacing: 10) {
                Button {
                    onAccept?()
                } label: {
                    Label("采纳调整", systemImage: "checkmark")
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
                        .background(VelaTheme.rhythmDeep, in: Capsule())
                }
                .buttonStyle(.cardPress)

                Button {
                    onReject?()
                } label: {
                    Label("保持原计划", systemImage: "xmark")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
                        .background(VelaTheme.rhythmMist, in: Capsule())
                }
                .buttonStyle(.cardPress)
            }

            Text("Vela 只提出方案；采纳后才会改变训练轮转。")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(VelaTheme.meta)
        } else if status == AdaptationStatus.accepted.rawValue {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("已采纳并更新至训练轮转")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(VelaTheme.meta)
                Text("已保持原计划执行")
                    .font(.system(.footnote, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.meta)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func adaptationLabel(_ adj: String) -> String {
        switch adj {
        case "keep": return "按计划执行，但保留余力"
        case "reduce": return "建议减量"
        case "swap": return "建议换成主动恢复"
        case "rest": return "建议安排休息"
        case "reschedule": return "建议改期"
        case "deloadWeek": return "建议本周减载"
        default: return adj
        }
    }

    private func adjustmentChipInfo(_ adj: String) -> (title: String, color: Color) {
        switch adj {
        case "rest":
            return ("休息日", VelaTheme.rhythmInk)
        case "reduce":
            return ("减量", VelaTheme.tagOrange)
        case "swap":
            return ("主动恢复", VelaTheme.accent)
        case "deloadWeek":
            return ("减载周", VelaTheme.tagPurple)
        default:
            return ("调整", VelaTheme.rhythmDeep)
        }
    }

    private func adjustmentChip(_ adj: String) -> some View {
        let info = adjustmentChipInfo(adj)
        return Text(info.title)
            .font(.system(.caption2, design: .default, weight: .bold))
            .foregroundStyle(info.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(info.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Today Training Plan Adaptation Card

/// The pending training-plan proposal belongs in the Today decision scene so
/// the user can act on the evidence while it is still relevant.
struct TodayTrainingPlanAdaptationCard: View {
    let activePlan: TrainingPlanRecord
    let pendingProposal: TrainingPlanAdaptationRecord

    @Environment(\.modelContext) private var modelContext
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlanProposalDiffCard(
                originalTitle: pendingProposal.originalDayTitle,
                adjustment: pendingProposal.adjustment,
                reason: pendingProposal.reason,
                suggestedAlternative: pendingProposal.suggestedAlternative,
                status: pendingProposal.status,
                planTitle: activePlan.title,
                onAccept: { accept(pendingProposal, in: activePlan) },
                onReject: { reject(pendingProposal) }
            )

            if let actionError {
                Text(actionError)
                    .font(.footnote)
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
    }

    private func accept(
        _ proposal: TrainingPlanAdaptationRecord,
        in plan: TrainingPlanRecord
    ) {
        let originalDays = plan.days
        let originalStatus = proposal.status
        let originalAcceptedAt = proposal.acceptedAt
        guard TodayTrainingPlanAdaptationDecision.accept(proposal, in: plan) else {
            actionError = "提案未能应用，请稍后重试。"
            return
        }
        do {
            try modelContext.save()
            actionError = nil
            VelaHaptic.success()
            VelaAppState.shared.markLocalDataChanged()
        } catch {
            plan.days = originalDays
            proposal.status = originalStatus
            proposal.acceptedAt = originalAcceptedAt
            actionError = "提案保存失败，请稍后重试。"
        }
    }

    private func reject(_ proposal: TrainingPlanAdaptationRecord) {
        TodayTrainingPlanAdaptationDecision.reject(proposal)
        do {
            try modelContext.save()
            actionError = nil
            VelaHaptic.light()
            VelaAppState.shared.markLocalDataChanged()
        } catch {
            proposal.status = AdaptationStatus.proposed.rawValue
            proposal.rejectedAt = nil
            actionError = "提案状态保存失败，请稍后重试。"
        }
    }
}

/// Shared state transition for the Today card and its tests. Plan mutation is
/// deliberately delegated to AdaptiveTrainingManager (ADR 0008); this helper
/// only records the user's explicit decision after that mutation succeeds.
enum TodayTrainingPlanAdaptationDecision {
    @discardableResult
    static func accept(
        _ proposal: TrainingPlanAdaptationRecord,
        in plan: TrainingPlanRecord,
        at date: Date = Date()
    ) -> Bool {
        guard proposal.status == AdaptationStatus.proposed.rawValue,
              AdaptiveTrainingManager().applyAdaptation(proposal, to: plan, at: date) else {
            return false
        }
        proposal.status = AdaptationStatus.accepted.rawValue
        proposal.acceptedAt = date
        return true
    }

    static func reject(
        _ proposal: TrainingPlanAdaptationRecord,
        at date: Date = Date()
    ) {
        guard proposal.status == AdaptationStatus.proposed.rawValue else { return }
        proposal.status = AdaptationStatus.rejected.rawValue
        proposal.rejectedAt = date
    }

    @discardableResult
    static func acceptArtifact(
        _ artifactRecord: CoachArtifactRecord,
        in plan: TrainingPlanRecord?,
        proposal: TrainingPlanAdaptationRecord? = nil,
        modelContext: ModelContext? = nil,
        at date: Date = Date()
    ) -> Bool {
        if let proposal, let plan {
            let success = accept(proposal, in: plan, at: date)
            if success {
                artifactRecord.status = CoachArtifactStatus.acted.rawValue
            }
            return success
        } else if let plan, let day = plan.days.first(where: { !$0.isCompleted }) {
            let adj = AdaptiveTrainingEngine.Adjustment(rawValue: artifactRecord.decision ?? "reduce") ?? .reduce
            let newProposal = TrainingPlanAdaptationRecord(
                planId: plan.id,
                dayId: day.id,
                adjustment: adj,
                reason: artifactRecord.summary,
                suggestedAlternative: nil,
                status: .proposed,
                originalDayTitle: day.title,
                agentRunId: artifactRecord.sourceContextHash
            )
            modelContext?.insert(newProposal)
            let success = accept(newProposal, in: plan, at: date)
            if success {
                artifactRecord.status = CoachArtifactStatus.acted.rawValue
            }
            return success
        } else {
            artifactRecord.status = CoachArtifactStatus.acted.rawValue
            return true
        }
    }

    static func rejectArtifact(
        _ artifactRecord: CoachArtifactRecord,
        proposal: TrainingPlanAdaptationRecord? = nil,
        at date: Date = Date()
    ) {
        if let proposal {
            reject(proposal, at: date)
        }
        artifactRecord.status = CoachArtifactStatus.dismissed.rawValue
    }
}

extension TodayTrainingPlanAdaptationCard: @preconcurrency Equatable {
    @MainActor
    static func == (lhs: TodayTrainingPlanAdaptationCard, rhs: TodayTrainingPlanAdaptationCard) -> Bool {
        lhs.activePlan.id == rhs.activePlan.id &&
        lhs.activePlan.updatedAt == rhs.activePlan.updatedAt &&
        lhs.pendingProposal.id == rhs.pendingProposal.id &&
        lhs.pendingProposal.status == rhs.pendingProposal.status &&
        lhs.pendingProposal.adjustment == rhs.pendingProposal.adjustment &&
        lhs.pendingProposal.reason == rhs.pendingProposal.reason &&
        lhs.pendingProposal.suggestedAlternative == rhs.pendingProposal.suggestedAlternative
    }
}
