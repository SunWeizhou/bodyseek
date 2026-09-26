import Foundation
import SwiftUI
import SwiftData

struct MetricCoachCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let dashboard: DashboardSummary
    let focus: CoachContextFocus
    var suggestedQuestion: String?

    @State private var streamText = ""
    @State private var isStreaming = false
    @State private var hasFinished = false
    @State private var errorMessage: String? = nil
    @State private var isBouncing = false
    
    private let keychain = KeychainService.shared
    private let apiKeyAccount = "deepseek_api_key"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(isStreaming ? Color.clear : VelaTheme.accent)
                    .overlay(
                        Group {
                            if isStreaming {
                                Image(systemName: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.pink, .purple, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .scaleEffect(isBouncing ? 1.25 : 0.8)
                                    .opacity(isBouncing ? 1.0 : 0.4)
                                    .task(id: reduceMotion) {
                                        isBouncing = false
                                        guard !reduceMotion else { return }
                                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                            isBouncing = true
                                        }
                                    }
                            }
                        }
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguage.stored.isChinese ? "让 Coach 实时分析" : "Vela Coach Live")
                        .font(.headline)
                        .foregroundStyle(VelaTheme.fg)

                    Text(AppLanguage.stored.isChinese ? "由 DeepSeek 驱动" : "Powered by DeepSeek AI")
                        .font(.caption2)
                        .foregroundStyle(VelaTheme.muted)
                }

                Spacer()
                
                if isStreaming {
                    Text(AppLanguage.stored.isChinese ? "分析中..." : "Analyzing...")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(VelaTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(VelaTheme.accent.opacity(0.12), in: Capsule())
                }
            }

            if !streamText.isEmpty || errorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(VelaTheme.stressColor)
                            .padding(.vertical, 4)
                    } else if hasFinished {
                        MetricCoachAdviceView(advice: MetricCoachAdviceFormatter.parse(streamText))
                    } else {
                        MarkdownText(markdown: streamText, isStreaming: isStreaming)
                            .font(.subheadline)
                            .padding(.top, 4)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            } else {
                Text(AppLanguage.stored.isChinese ? "点击下方按钮，由 AI 针对当前生命体征和最新运动数据，提供定制的训练与恢复行动建议。" : "Tap below to let AI analyze your current vitals and recent activity trends, and deliver tailored training or recovery advice.")
                    .font(.footnote)
                    .foregroundStyle(VelaTheme.fg2)
                    .lineSpacing(3)
            }

            if !isStreaming {
                HStack(spacing: 8) {
                    if !streamText.isEmpty {
                        Button {
                            startStreaming()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 38, height: 38)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VelaTheme.fillSoft))
                        }
                        .buttonStyle(.cardPress)
                        .foregroundStyle(VelaTheme.fg)
                    }

                    Button {
                        if !hasFinished {
                            startStreaming()
                        } else {
                            VelaAppState.shared.routeToCoach(question: resolvedQuestion, surface: .metricDetail)
                        }
                    } label: {
                        HStack {
                            if !hasFinished {
                                Image(systemName: "sparkles")
                                Text(AppLanguage.stored.isChinese ? "获取 AI 建议" : "Get AI Advice")
                            } else {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text(AppLanguage.stored.isChinese ? "深度对话" : "Discuss with Coach")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VelaTheme.accent)
                }
                .padding(.top, 4)
            }
        }
        .heroCardSurface(accent: VelaTheme.accent)
        .modifier(AppleIntelligenceGlowBorder(isGlowing: isStreaming))
    }

    private func startStreaming() {
        streamText = ""
        errorMessage = nil
        isStreaming = true
        hasFinished = false
        
        Task {
            do {
                guard let apiKey = try keychain.read(account: apiKeyAccount), !apiKey.isEmpty else {
                    errorMessage = AppLanguage.stored.isChinese
                        ? "请先在设置中添加 DeepSeek API Key。"
                        : "Please add your DeepSeek API key in Settings first."
                    isStreaming = false
                    return
                }

                let systemPrompt = AppLanguage.stored.isChinese ? """
                你是 Vela，一位世界顶级私人健康教练和运动科学家。你正在为用户提供针对特定身体指标 (\(focus.title)) 的定制化行动建议。
                你的语言风格必须专业、精准、简洁、充满人情味。不要诊断疾病，不要把单次测量解释为确定结论。
                使用 Markdown，严格按以下结构输出：
                ### 结论
                用 1-2 句说明今天该保持、减载还是关注变化。
                ### 依据
                最多 3 个项目符号，只引用最相关的数据。
                ### 今天行动
                给出 1 个明确、可执行的动作。
                总长度控制在 220 个中文字符以内。
                """ : """
                You are Vela, a world-class personal health coach. You are giving the user hyper-personalized, expert advice about their \(focus.title) metric.
                Keep your style professional, concise, empathetic, and highly actionable. Do not diagnose medical conditions or overinterpret one reading.
                Use Markdown with exactly three sections: ### Conclusion, ### Evidence, and ### Today's Action.
                Keep Evidence to at most 3 bullets, Today's Action to one concrete step, and the total response under 140 words.
                """

                let asOf = Date()
                let input = AgentFactInputLoader().load(modelContext: modelContext, asOf: asOf)
                let bodyState = input.bodyState(dashboard: dashboard)
                let wiki = WikiFileService.loadPopulatedDictionary()
                let coverageSummary = DataCoverageSummaryModel.build(
                    groups: await DataCoverageGroupFactory.loadPriorityGroups()
                )
                let snapshot = AIContextBuilder().buildFacts(
                    dashboard: dashboard,
                    journalEntries: input.journalContext,
                    historicalReports: input.reportContext,
                    userWiki: wiki,
                    weeklyTrends: input.weeklyTrends,
                    foodLogs: input.foodLogs,
                    workoutEvents: input.workoutEvents,
                    strengthWorkouts: input.strengthWorkouts,
                    trainingResponses: input.trainingResponses,
                    onboardingState: input.onboardingState,
                    bodyState: bodyState,
                    trainingDecision: input.canonicalTrainingDecision(for: bodyState),
                    dataCoverage: coverageSummary.agentFactContext,
                    scoringContext: dashboard.scoringContext,
                    dailyOperatingPlan: AIContextBuilder.compactDailyOperatingPlan(input.dailyOperatingPlan),
                    activePlan: input.activePlan?.dto,
                    generatedAt: asOf
                ).snapshot
                let canonicalFacts = CoachCompactContextAdapter().render(
                    snapshot: snapshot,
                    language: AppLanguage.stored,
                    maxCharacters: 1_600
                )
                let wikiText = ContextBudget.trimWiki(
                    wiki.sorted { $0.key < $1.key }
                        .map { "### \($0.key)\n\($0.value)" }
                        .joined(separator: "\n\n"),
                    maxChars: 1_600
                )
                let metricsPrompt = """
                Focus Metric: \(focus.title)
                Focus Metric Context: \(focus.systemContext)

                \(canonicalFacts)

                ## Confirmed User Wiki
                \(wikiText)

                User Question:
                \(resolvedQuestion)
                """

                let baseProvider = DeepSeekProvider(apiKey: apiKey)
                // 此前直连 provider 无重试：偶发网络抖动直接报错。
                let provider = RetryingLLMProvider(base: baseProvider)
                let messages = [
                    ChatMessage(role: .system, content: systemPrompt),
                    ChatMessage(role: .user, content: metricsPrompt)
                ]

                let stream = provider.streamChat(messages: messages)
                for try await chunk in stream {
                    streamText += chunk
                    if Task.isCancelled { break }
                }
                
                isStreaming = false
                hasFinished = true
            } catch {
                errorMessage = AppLanguage.stored.isChinese
                    ? "分析失败：\(error.localizedDescription)"
                    : "Analysis failed: \(error.localizedDescription)"
                isStreaming = false
            }
        }
    }

    private var resolvedQuestion: String {
        if let suggestedQuestion,
           !suggestedQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return suggestedQuestion
        }

        return AppLanguage.stored.isChinese
            ? "请基于当前\(focus.title)数据，先给结论，再说明依据，最后给我今天最重要的一步行动。"
            : "Analyze my current \(focus.title) data. Start with the conclusion, then evidence, then the single most important action for today."
    }
}

struct MetricCoachAdvice: Equatable {
    var conclusion: String
    var evidence: [String]
    var action: String

    var totalCharacterCount: Int {
        conclusion.count + evidence.reduce(0) { $0 + $1.count } + action.count
    }
}

enum MetricCoachAdviceFormatter {
    static func parse(_ raw: String) -> MetricCoachAdvice {
        let cleaned = cleanedMarkdown(raw)
        if let structured = structuredSections(in: cleaned) {
            return makeAdvice(
                conclusion: structured.conclusion,
                evidence: sentences(in: structured.evidence),
                action: structured.action
            )
        }

        let fallbackSentences = sentences(in: cleaned)
        guard let conclusion = fallbackSentences.first else {
            return MetricCoachAdvice(conclusion: "", evidence: [], action: "")
        }
        guard fallbackSentences.count > 1 else {
            return makeAdvice(conclusion: conclusion, evidence: [], action: conclusion)
        }

        return makeAdvice(
            conclusion: conclusion,
            evidence: Array(fallbackSentences.dropFirst().dropLast()),
            action: fallbackSentences.last ?? conclusion
        )
    }

    private static func makeAdvice(
        conclusion: String,
        evidence: [String],
        action: String
    ) -> MetricCoachAdvice {
        MetricCoachAdvice(
            conclusion: bounded(clean(conclusion), limit: 56),
            evidence: Array(evidence.map(clean).filter { !$0.isEmpty }.prefix(3)).map {
                bounded($0, limit: 34)
            },
            action: bounded(clean(action), limit: 56)
        )
    }

    private static func structuredSections(
        in text: String
    ) -> (conclusion: String, evidence: String, action: String)? {
        guard
            let conclusion = markerRange(for: ["结论", "Conclusion"], in: text),
            let evidence = markerRange(for: ["依据", "Evidence"], in: text, after: conclusion.upperBound),
            let action = markerRange(
                for: ["今天行动", "今日行动", "Today's Action", "Today’s Action", "Action"],
                in: text,
                after: evidence.upperBound
            )
        else {
            return nil
        }

        return (
            String(text[conclusion.upperBound..<evidence.lowerBound]),
            String(text[evidence.upperBound..<action.lowerBound]),
            String(text[action.upperBound...])
        )
    }

    private static func markerRange(
        for candidates: [String],
        in text: String,
        after start: String.Index? = nil
    ) -> Range<String.Index>? {
        let searchRange = (start ?? text.startIndex)..<text.endIndex
        return candidates
            .compactMap { text.range(of: $0, options: [.caseInsensitive], range: searchRange) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func cleanedMarkdown(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentences(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if "。！？!?；;\n".contains(character) {
                let sentence = clean(current)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let trailing = clean(current)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }
        return sentences
    }

    private static func clean(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, "-*+•:：".contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(limit - 1, 0))) + "…"
    }
}

private struct MetricCoachAdviceView: View {
    let advice: MetricCoachAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(title: AppLanguage.stored.isChinese ? "结论" : "Conclusion") {
                Text(advice.conclusion)
            }

            if !advice.evidence.isEmpty {
                section(title: AppLanguage.stored.isChinese ? "依据" : "Evidence") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(advice.evidence, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(VelaTheme.accent)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(item)
                            }
                        }
                    }
                }
            }

            section(title: AppLanguage.stored.isChinese ? "今天行动" : "Today's Action") {
                Text(advice.action)
            }
        }
        .font(.subheadline)
        .foregroundStyle(VelaTheme.fg2)
        .lineSpacing(3)
        .padding(.top, 4)
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(VelaTheme.fg)
            content()
        }
    }
}

struct AppleIntelligenceGlowBorder: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isGlowing: Bool
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isGlowing {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                AngularGradient(
                                    colors: [.pink, .purple, .cyan, .orange, .pink],
                                    center: .center,
                                    angle: .degrees(rotation)
                                ),
                                lineWidth: 2.2
                            )
                            .shadow(color: .purple.opacity(0.42), radius: 6)
                            .task(id: reduceMotion) {
                                rotation = 0
                                guard !reduceMotion else { return }
                                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                                    rotation = 360
                                }
                            }
                    }
                }
            )
            .scaleEffect(isGlowing && !reduceMotion ? 1.012 : 1.0)
            .animation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion), value: isGlowing)
    }
}
