import SwiftUI

// MARK: - Shared data presentation states

enum VelaDataPresentationState: String, CaseIterable, Equatable {
    case loading
    case empty
    case partial
    case calibrating
    case stale
    case offline
    case error

    var systemImage: String {
        switch self {
        case .loading: "arrow.trianglehead.2.clockwise.rotate.90"
        case .empty: "waveform.path.ecg.rectangle"
        case .partial: "circle.lefthalf.filled"
        case .calibrating: "scope"
        case .stale: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .loading, .calibrating: VelaTheme.accent
        case .empty: VelaTheme.muted
        case .partial, .stale: VelaTheme.warn
        case .offline: VelaTheme.rhythmInk
        case .error: VelaTheme.danger
        }
    }

    var defaultTitle: String {
        switch self {
        case .loading: L10n.t("Updating data", "正在更新数据")
        case .empty: L10n.t("No data yet", "暂无数据")
        case .partial: L10n.t("Partial data", "数据不完整")
        case .calibrating: L10n.t("Calibrating", "正在建立基线")
        case .stale: L10n.t("Update recommended", "建议刷新数据")
        case .offline: L10n.t("Offline", "当前离线")
        case .error: L10n.t("Unable to load", "载入失败")
        }
    }
}

struct VelaStateCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: VelaDataPresentationState
    var title: String? = nil
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stateIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(title ?? state.defaultTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.fg)

                Text(message)
                    .font(VelaTheme.captionLarge())
                    .foregroundStyle(VelaTheme.fg2)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(state.tint)
                        .frame(minHeight: VelaTheme.minimumHitTarget)
                        .accessibilityHint(L10n.t("Attempts the suggested recovery action", "执行建议的恢复操作"))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(VelaTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.cardBg, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
        .accessibilityElement(children: action == nil ? .combine : .contain)
        .accessibilityLabel("\(title ?? state.defaultTitle)。\(message)")
    }

    @ViewBuilder
    private var stateIcon: some View {
        Group {
            if state == .loading && !reduceMotion {
                ProgressView()
                    .tint(state.tint)
            } else {
                Image(systemName: state.systemImage)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(state.tint)
            }
        }
            .frame(width: VelaTheme.circularControlSize, height: VelaTheme.circularControlSize)
            .background(VelaTheme.rhythmMist, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - StatusCapsule

struct StatusCapsule: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(label)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.fg2)

                Text(value)
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.fg)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(VelaTheme.cardBg)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.cardPress)
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let isUser: Bool
    let time: String
    var isStreaming = false

    @State private var showCopiedIndicator = false

    private var parsedParts: ParsedMessageParts {
        if isUser {
            return ParsedMessageParts(thinkingContent: nil, mainContent: text, isStillThinking: false)
        }
        return CoachThinkingParser.parse(text, isStreaming: isStreaming)
    }

    private var segments: [MessageSegment] {
        parseMessageContent(parsedParts.mainContent)
    }

    private var containsInternalProtocol: Bool {
        let markers = ["<|", "tool_calls", "function_call", "DSML"]
        return markers.contains {
            parsedParts.mainContent.localizedCaseInsensitiveContains($0)
        }
    }

    var body: some View {
        Group {
            if isUser {
                userMessage
            } else {
                analystMessage
            }
        }
        .transition(bubbleTransition)
    }

    private var userMessage: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 4) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        switch segment {
                        case .text(let content):
                            if !content.isEmpty {
                                MarkdownText(
                                    markdown: content,
                                    font: VelaTheme.body(),
                                    color: VelaTheme.rhythmInk,
                                    isStreaming: isStreaming
                                )
                                .lineSpacing(4)
                            }
                        case .artifact(let type, let key):
                            ArtifactRendererView(type: type, key: key)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(VelaTheme.surfaceFloating, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: 1)
                )

                if !time.isEmpty {
                    Text(time)
                        .font(.caption2)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    /// Vela's answer is prose, not a second chat bubble.
    private var analystMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BodySeek")
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                if let thinking = parsedParts.thinkingContent, !thinking.isEmpty {
                    CoachThinkingView(
                        thinkingText: thinking,
                        isStreaming: parsedParts.isStillThinking
                    )
                }

                if !parsedParts.mainContent.isEmpty || parsedParts.thinkingContent == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(segments) { segment in
                            switch segment {
                            case .text(let content):
                                if !content.isEmpty {
                                    assistantTextBlock(content)
                                }
                            case .artifact(let type, let key):
                                ArtifactRendererView(type: type, key: key)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isStreaming || !time.isEmpty {
                    analystControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func assistantTextBlock(_ content: String) -> some View {
        if containsInternalProtocol {
            Label("这条回复没有完成，请重新提问", systemImage: "arrow.clockwise.circle")
                .font(VelaTheme.footnote().weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(VelaTheme.rhythmMist, in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
        } else {
        let sections = CoachResponseLayout.split(content, isStreaming: isStreaming)
        VStack(alignment: .leading, spacing: 10) {
            if let lead = sections.lead {
                MarkdownText(
                    markdown: lead,
                    font: VelaTheme.body().weight(.semibold),
                    color: VelaTheme.rhythmInk,
                    isStreaming: false
                )
                .lineSpacing(6)
            }
            if let detail = sections.detail {
                MarkdownText(
                    markdown: detail,
                    font: VelaTheme.body(),
                    color: VelaTheme.rhythmInk,
                    isStreaming: isStreaming
                )
                .lineSpacing(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var analystControls: some View {
        HStack(spacing: 4) {
            if !time.isEmpty {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            Spacer(minLength: 4)

            if !isStreaming && !parsedParts.mainContent.isEmpty && !containsInternalProtocol {
                Button(action: copyToClipboard) {
                    Label(
                        showCopiedIndicator ? "已复制" : "复制",
                        systemImage: showCopiedIndicator ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(showCopiedIndicator ? VelaTheme.rhythmDeep : VelaTheme.rhythmInkSecondary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: VelaTheme.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cardPress)
                .accessibilityHint("复制这条 Vela 回复")
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = parsedParts.mainContent
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
            showCopiedIndicator = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                showCopiedIndicator = false
            }
        }
    }

    private var bubbleTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .scale(
            scale: 0.96,
            anchor: isUser ? .bottomTrailing : .bottomLeading
        )
        .combined(with: .opacity)
    }
}

// MARK: - TypingIndicator

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(VelaTheme.rhythmInkSecondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(reduceMotion ? 1 : (animate ? 1.0 : 0.4))
                    .opacity(reduceMotion ? 0.65 : (animate ? 1.0 : 0.3))
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                        value: animate
                    )
            }
        }
        // D: an assistant answer is prose, so the waiting state keeps only the
        // ink dots — no bubble chrome around them.
        .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
        .onAppear {
            animate = !reduceMotion
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            animate = !shouldReduceMotion
        }
        .onDisappear {
            animate = false
        }
    }
}

// MARK: - AppleIntelligenceOrb (legacy mono mark)

struct AppleIntelligenceOrb: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(VelaTheme.title2())
            .foregroundStyle(VelaTheme.rhythmInk)
            .frame(width: 68, height: 68)
            .background(VelaTheme.rhythmCanvasRaised, in: Circle())
            .overlay(Circle().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
            .accessibilityHidden(true)
    }
}

// MARK: - VelaInlineAlert

struct VelaInlineAlertCompat: View {
    let title: String
    let message: String
    var systemImage: String?
    var tint: Color = VelaTheme.accent

    var body: some View {
        HStack(spacing: 10) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.title3)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VelaTheme.fg)
                Text(message)
                    .font(VelaTheme.captionLarge())
                    .foregroundStyle(VelaTheme.fg2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd)
                .fill(VelaTheme.rhythmMist)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
    }
}
typealias VelaInlineAlert = VelaInlineAlertCompat
typealias VelaAppleInlineAlert = VelaInlineAlertCompat

// MARK: - VelaDataQualityRow

struct VelaDataQualityRowCompat: View {
    let title: String
    let subtitle: String
    var isAvailable: Bool = true
    var freshness: DataFreshness? = nil
    let qualityLabel: String
    let tint: Color

    var body: some View {
        let available = freshness.map { $0 != .missing } ?? isAvailable
        HStack(spacing: 12) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(available ? tint : VelaTheme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VelaTheme.fg)
                Text(subtitle)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.fg2)
            }
            Spacer()
            Text(qualityLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(available ? tint : VelaTheme.muted)
        }
        .padding(.vertical, 6)
    }
}
typealias VelaDataQualityRow = VelaDataQualityRowCompat
typealias VelaAppleDataQualityRow = VelaDataQualityRowCompat
