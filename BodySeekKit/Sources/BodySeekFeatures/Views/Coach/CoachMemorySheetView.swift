import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct CoachMemorySheetView: View {
    @Bindable var store: StoreOf<CoachFeature>

    public init(store: StoreOf<CoachFeature>) {
        self.store = store
    }

    public var body: some View {
        let now = Date()
        let profiles = store.state.activeTieredMemories(for: .profile, at: now)
        let constraints = store.state.activeTieredMemories(for: .activeConstraint, at: now)
        let verifiedPatterns = store.state.activeTieredMemories(for: .verifiedPattern, at: now)
        let candidateFindings = store.patternFindings.filter { $0.status == .candidate }

        return NavigationStack {
            List {
                Section("Profile · 长期偏好与目标 (\(profiles.count))") {
                    if profiles.isEmpty {
                        emptyHint("暂无长期目标或作息偏好。在对话中告知后点击提案卡片「确认写入」即可保存。")
                    } else {
                        ForEach(profiles) { record in
                            memoryRow(record, now: now)
                        }
                    }
                }
                .accessibilityIdentifier("coach-memory-section-profile")

                Section("Active Constraint · 短期约束与伤病 (\(constraints.count))") {
                    if constraints.isEmpty {
                        emptyHint("暂无有效期内的伤病或关节受限约束，到期后将自动退出注入上下文。")
                    } else {
                        ForEach(constraints) { record in
                            memoryRow(record, now: now)
                        }
                    }
                }
                .accessibilityIdentifier("coach-memory-section-constraint")

                Section("Verified Pattern · 已确认个人规律 (\(verifiedPatterns.count))") {
                    if verifiedPatterns.isEmpty {
                        emptyHint("仅有你主动确认过的统计规律才可进入 Verified Pattern。")
                    } else {
                        ForEach(verifiedPatterns) { record in
                            memoryRow(record, now: now)
                        }
                    }
                }
                .accessibilityIdentifier("coach-memory-section-pattern")

                if !candidateFindings.isEmpty {
                    Section("候选个人规律 · 待你确认 (\(candidateFindings.count))") {
                        ForEach(candidateFindings) { finding in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(finding.statement)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(BevelTheme.ink)
                                Text(String(format: "n=%d · 效应 %.2f (CI %.2f…%.2f) · %@", finding.sampleSize, finding.effect, finding.ciLow, finding.ciHigh, finding.method))
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                Button {
                                    store.send(.confirmCandidatePatternTapped(finding))
                                } label: {
                                    Label("确认为个人规律并写入记忆", systemImage: "checkmark.seal.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(BevelTheme.brand)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("memory-confirm-pattern-\(finding.id.uuidString)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .accessibilityIdentifier("coach-memory-sheet")
            .navigationTitle("三层长期记忆管理")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") {
                        store.send(.memorySheetPresented(false))
                    }
                    .accessibilityIdentifier("coach-memory-sheet-done")
                }
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(BevelTheme.inkSecondary)
    }

    private func memoryRow(_ record: TieredMemoryRecord, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.tier.titleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.brand)
                Spacer()
                if let exp = record.expiresAt {
                    let daysLeft = max(0, Int(ceil(exp.timeIntervalSince(now) / 86_400)))
                    Text(daysLeft == 0 ? "今日到期" : "剩余 \(daysLeft) 天")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(BevelTheme.energyColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(BevelTheme.energyColor)
                }
            }
            Text(record.content)
                .font(.subheadline)
                .foregroundStyle(BevelTheme.ink)
        }
        .swipeActions {
            Button("停用", role: .destructive) {
                store.send(.retireTieredMemoryTapped(record.id))
            }
        }
    }
}
