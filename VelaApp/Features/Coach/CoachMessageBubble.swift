import SwiftUI
import SwiftData

// MARK: - CoachChatMessage
struct CoachChatMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
}

/// Presentation-only split for a completed Coach answer. The first concise
/// paragraph/line is promoted as a conclusion while the full evidence remains
/// visible underneath; model output and stored content are never rewritten.
enum CoachResponseLayout {
    static func split(_ raw: String, isStreaming: Bool) -> (lead: String?, detail: String?) {
        guard !isStreaming else { return (nil, raw) }

        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return (nil, nil) }

        // Older sessions can contain provider protocol fragments when a tool
        // call was interrupted. Never promote or prettify those fragments as
        // a user-facing conclusion; keep the existing raw rendering path so
        // the caller can apply its normal recovery/error treatment.
        let internalMarkers = ["<|", "tool_calls", "function_call", "DSML", "[ARTIFACT:"]
        if internalMarkers.contains(where: { normalized.localizedCaseInsensitiveContains($0) }) {
            return (nil, normalized)
        }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 2, let first = paragraphs.first, first.count <= 220 {
            let detail = paragraphs.dropFirst().joined(separator: "\n\n")
            return (first, detail.isEmpty ? nil : detail)
        }

        // Some answers use one conclusion line followed by bullets instead of
        // a blank line. Lift that line while preserving every remaining line.
        let lines = normalized.components(separatedBy: "\n")
        if lines.count >= 2,
           let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty,
           first.count <= 160,
           !first.hasPrefix("#"),
           !first.hasPrefix("-"),
           !first.hasPrefix("•"),
           !first.hasPrefix("*") {
            let detail = lines.dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (first, detail.isEmpty ? nil : detail)
        }

        return (nil, normalized)
    }
}

// MARK: - CoachThinkingParser

struct ParsedMessageParts: Equatable {
    var thinkingContent: String?
    var mainContent: String
    var isStillThinking: Bool
}

enum CoachThinkingParser {
    /// 解析包含 `<think>...</think>` 的消息内容
    static func parse(_ raw: String, isStreaming: Bool = false) -> ParsedMessageParts {
        let thinkOpenTag = "<think>"
        let thinkCloseTag = "</think>"

        guard let openRange = raw.range(of: thinkOpenTag, options: .caseInsensitive) else {
            return ParsedMessageParts(thinkingContent: nil, mainContent: raw, isStillThinking: false)
        }

        let afterOpen = raw[openRange.upperBound...]

        if let closeRange = afterOpen.range(of: thinkCloseTag, options: .caseInsensitive) {
            let thinkingText = String(afterOpen[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let mainText = String(afterOpen[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedMessageParts(
                thinkingContent: thinkingText.isEmpty ? nil : thinkingText,
                mainContent: mainText,
                isStillThinking: false
            )
        } else {
            // 尚未闭合（仍在思考阶段）
            let thinkingText = String(afterOpen).trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedMessageParts(
                thinkingContent: thinkingText.isEmpty ? nil : thinkingText,
                mainContent: "",
                isStillThinking: isStreaming
            )
        }
    }
}

// MARK: - CoachThinkingView

struct CoachThinkingView: View {
    let thinkingText: String
    let isStreaming: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = false
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isStreaming ? "brain.filled.head.profile" : "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isStreaming ? VelaTheme.accent : VelaTheme.rhythmInkSecondary)
                        .scaleEffect(isStreaming && !reduceMotion ? (pulse ? 1.15 : 0.9) : 1.0)
                        .animation(
                            isStreaming && !reduceMotion
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : nil,
                            value: pulse
                        )

                    Text(isStreaming ? "深度思考中..." : "已深度思考")
                        .font(VelaTheme.caption2().weight(.medium))
                        .foregroundStyle(isStreaming ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)

                    Spacer(minLength: 4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VelaTheme.rhythmMist.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                if isStreaming {
                    pulse = true
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                pulse = streaming
            }

            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(VelaTheme.accent.opacity(0.35))
                        .frame(width: 2)
                        .padding(.vertical, 2)

                    MarkdownText(
                        markdown: thinkingText,
                        font: VelaTheme.caption2(),
                        color: VelaTheme.rhythmInkSecondary,
                        isStreaming: isStreaming
                    )
                    .lineSpacing(2)
                }
                .padding(.leading, 4)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - CoachRecoveryActionButton
struct CoachRecoveryActionButton: View {
    let action: LLMErrorRecoveryAction
    var perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Label(action.title, systemImage: action.systemImage)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(VelaTheme.accent.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(VelaTheme.accent.opacity(0.22), lineWidth: 0.8)
                )
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel(action.title)
    }
}

// MARK: - CoachDataCoverageStrip
struct CoachDataCoverageStrip: View {
    let model: DataCoverageSummaryModel
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: model.actionSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(VelaTheme.rhythmMist))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.compactDisplayTitle)
                        .font(VelaTheme.footnote().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.status == .low
                         ? "低覆盖时 Coach 会保守回答"
                         : model.topBlockers.isEmpty ? "关键数据可用于本轮判断" : "缺口：\(model.topBlockers.joined(separator: "、"))")
                    .font(VelaTheme.caption1().weight(.medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Coach \(model.compactDisplayTitle)")
    }

    private var accent: Color {
        switch model.status {
        case .high: return VelaTheme.energyColor
        case .moderate: return VelaTheme.accent
        case .low: return VelaTheme.strainColor
        case .unknown: return VelaTheme.muted
        }
    }
}

// MARK: - AppleIntelligenceLoaderDots
struct AppleIntelligenceLoaderDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(VelaTheme.rhythmDeep)
                .frame(width: 6, height: 6)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.3 : 0.75))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            Circle()
                .fill(VelaTheme.accent)
                .frame(width: 6, height: 6)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.3 : 0.75))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.2), value: pulse)
            Circle()
                .fill(VelaTheme.rhythmInkSecondary)
                .frame(width: 6, height: 6)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.3 : 0.75))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.4), value: pulse)
        }
        .onAppear {
            pulse = !reduceMotion
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            pulse = !shouldReduceMotion
        }
        .onDisappear {
            pulse = false
        }
    }
}

// MARK: - MiniBubble
// MARK: - MiniStreamingBubble
// MARK: - Message Segment Parsing Helpers
enum MessageSegment: Identifiable {
    var id: String {
        switch self {
        case .text(let t): return "text-\(t.hashValue)"
        case .artifact(let type, let key): return "artifact-\(type)-\(key)"
        }
    }
    case text(String)
    case artifact(type: String, key: String)
}

func parseMessageContent(_ content: String) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    var currentIndex = content.startIndex
    
    while let range = content[currentIndex...].range(of: "\\[ARTIFACT:[^\\]]+\\]", options: .regularExpression) {
        let prefix = content[currentIndex..<range.lowerBound]
        if !prefix.isEmpty {
            segments.append(.text(String(prefix)))
        }
        
        let tag = content[range]
        let cleanTag = tag.dropFirst().dropLast() // "ARTIFACT:correlation:hrv_vs_sleep"
        let parts = cleanTag.components(separatedBy: ":")
        if parts.count >= 2 {
            let type = parts[1]
            let key = parts.count >= 3 ? parts[2...].joined(separator: ":") : ""
            segments.append(.artifact(type: type, key: key))
        } else {
            segments.append(.text(String(tag)))
        }
        
        currentIndex = range.upperBound
    }
    
    let suffix = content[currentIndex...]
    if !suffix.isEmpty {
        segments.append(.text(String(suffix)))
    }
    
    return segments.isEmpty ? [.text(content)] : segments
}

// MARK: - ArtifactRendererView
struct ArtifactRendererView: View {
    let type: String
    let key: String
    
    @Environment(\.modelContext) private var modelContext
    @State private var artifactRecord: CoachArtifactRecord? = nil
    @State private var localStatusOverride: String? = nil
    
    var body: some View {
        Group {
            if let record = artifactRecord {
                if record.artifact.type == .trainingAdjustment {
                    trainingAdjustmentDiffCard(for: record)
                } else {
                    CoachArtifactCard(artifact: record.artifact, compact: true) { action in
                        handleArtifactAction(action, artifact: record.artifact)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("Loading card...", "加载建议卡片..."))
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                }
                .padding(.vertical, 6)
                .onAppear {
                    loadRecord()
                }
            }
        }
    }

    @ViewBuilder
    private func trainingAdjustmentDiffCard(for record: CoachArtifactRecord) -> some View {
        let activePlan = try? modelContext.fetch(
            FetchDescriptor<TrainingPlanRecord>(predicate: #Predicate { $0.isActive })
        ).first
        let proposals = (try? modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>())) ?? []
        let matchingProposal = proposals.first(where: {
            $0.id.uuidString == key ||
            $0.agentRunId == record.sourceContextHash ||
            ($0.status == AdaptationStatus.proposed.rawValue && activePlan != nil && $0.planId == activePlan?.id)
        })

        let originalTitle = matchingProposal?.originalDayTitle ?? activePlan?.days.first(where: { !$0.isCompleted })?.title ?? record.artifact.title
        let adjustment = matchingProposal?.adjustment ?? record.artifact.decision ?? "reduce"
        let reason = matchingProposal?.reason ?? record.artifact.reasons.first?.explanation ?? record.artifact.summary
        let alternative = matchingProposal?.suggestedAlternative ?? (record.artifact.summary.isEmpty ? nil : record.artifact.summary)

        let resolvedStatus: String = {
            if let override = localStatusOverride {
                return override
            }
            if let matchingProposal {
                return matchingProposal.status
            }
            if record.status == CoachArtifactStatus.acted.rawValue {
                return AdaptationStatus.accepted.rawValue
            }
            if record.status == CoachArtifactStatus.dismissed.rawValue {
                return AdaptationStatus.rejected.rawValue
            }
            return AdaptationStatus.proposed.rawValue
        }()

        PlanProposalDiffCard(
            originalTitle: originalTitle,
            adjustment: adjustment,
            reason: reason,
            suggestedAlternative: alternative,
            status: resolvedStatus,
            planTitle: activePlan?.title,
            onAccept: {
                TodayTrainingPlanAdaptationDecision.acceptArtifact(
                    record,
                    in: activePlan,
                    proposal: matchingProposal,
                    modelContext: modelContext
                )
                localStatusOverride = AdaptationStatus.accepted.rawValue
                try? modelContext.save()
                VelaHaptic.success()
                VelaAppState.shared.markLocalDataChanged()
            },
            onReject: {
                TodayTrainingPlanAdaptationDecision.rejectArtifact(
                    record,
                    proposal: matchingProposal
                )
                localStatusOverride = AdaptationStatus.rejected.rawValue
                try? modelContext.save()
                VelaHaptic.light()
                VelaAppState.shared.markLocalDataChanged()
            }
        )
    }
    
    private func loadRecord() {
        guard let id = UUID(uuidString: key) else { return }
        let descriptor = FetchDescriptor<CoachArtifactRecord>(
            predicate: #Predicate<CoachArtifactRecord> { $0.id == id }
        )
        if let record = try? modelContext.fetch(descriptor).first {
            self.artifactRecord = record
        }
    }
    
    private func handleArtifactAction(_ action: CoachArtifactAction, artifact: CoachArtifact) {
        VelaAppState.shared.logDebug("[ArtifactRendererView] handleArtifactAction: type=\(action.type), payload=\(action.payload)")
        if action.type == "start_check_in", let raw = action.payload["workout_id"], let id = UUID(uuidString: raw) {
            VelaAppState.shared.routeToPostWorkoutCheckIn(workoutID: id)
        } else if action.type == "open_recovery_detail" {
            VelaAppState.shared.routeToRecoveryDetail()
        } else if action.type == "accept_training_adjustment" || action.type == "accept_adaptation" {
            if let record = artifactRecord {
                let activePlan = try? modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(predicate: #Predicate { $0.isActive })).first
                let proposals = (try? modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>())) ?? []
                let matchingProposal = proposals.first(where: {
                    $0.id.uuidString == key ||
                    $0.agentRunId == record.sourceContextHash ||
                    ($0.status == AdaptationStatus.proposed.rawValue && activePlan != nil && $0.planId == activePlan?.id)
                })
                TodayTrainingPlanAdaptationDecision.acceptArtifact(
                    record,
                    in: activePlan,
                    proposal: matchingProposal,
                    modelContext: modelContext
                )
                localStatusOverride = AdaptationStatus.accepted.rawValue
                try? modelContext.save()
                VelaHaptic.success()
                VelaAppState.shared.markLocalDataChanged()
            }
        } else if action.type == "reject_training_adjustment" || action.type == "reject_adaptation" {
            if let record = artifactRecord {
                let proposals = (try? modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>())) ?? []
                let matchingProposal = proposals.first(where: {
                    $0.id.uuidString == key ||
                    $0.agentRunId == record.sourceContextHash
                })
                TodayTrainingPlanAdaptationDecision.rejectArtifact(record, proposal: matchingProposal)
                localStatusOverride = AdaptationStatus.rejected.rawValue
                try? modelContext.save()
                VelaHaptic.light()
                VelaAppState.shared.markLocalDataChanged()
            }
        } else if action.type.contains("training") || action.type.contains("workout") {
            VelaAppState.shared.routeToTraining()
        } else if action.type.contains("check") || action.type.contains("journal") {
            VelaAppState.shared.present(.journal)
        } else {
            VelaAppState.shared.routeToCoach(question: action.label)
        }
    }
}

// MARK: - CoachFollowUpChipsView

struct CoachFollowUpChipsView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        VelaHaptic.selection()
                        onSelect(suggestion)
                    } label: {
                        Label(suggestion, systemImage: "arrow.turn.down.right")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .padding(.horizontal, 12)
                            .frame(minHeight: VelaTheme.minimumHitTarget)
                            .background(
                                Capsule()
                                    .fill(VelaTheme.rhythmCanvasRaised)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.cardPress)
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
