import SwiftUI

public enum CoachPersonality: String, Codable, CaseIterable, Identifiable {
    case dataNerd = "data_nerd"
    case guardian = "guardian"
    case friend = "friend"
    case commander = "commander"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dataNerd: return "chart.bar.doc.horizontal.fill"
        case .guardian: return "shield.heart.fill"
        case .friend: return "face.smiling.fill"
        case .commander: return "bolt.shield.fill"
        }
    }

    public var tint: Color {
        switch self {
        case .dataNerd: return VelaTheme.rhythmInk
        case .guardian: return VelaTheme.rhythmInk
        case .friend: return VelaTheme.rhythmInk
        case .commander: return VelaTheme.rhythmInk
        }
    }

    public var displayName: String {
        switch self {
        case .dataNerd: return L10n.t("Data Nerd", "数据极客")
        case .guardian: return L10n.t("Guardian", "健康守护")
        case .friend: return L10n.t("Friend", "暖心挚友")
        case .commander: return L10n.t("Commander", "铁血指挥官")
        }
    }

    public var description: String {
        switch self {
        case .dataNerd:
            return L10n.t(
                "Analytical & detailed. Enforces statistics, deviations, and clinical physiological reasoning.",
                "理性细致，基于可用数据说明依据、不确定性与趋势，提供指标对比和必要的统计分析。"
            )
        case .guardian:
            return L10n.t(
                "Protective & sustainable. Prioritizes active recovery, sleep alignment, and stress reduction.",
                "温和沉稳，专注长程健康与平衡。警惕过度负荷，把睡眠和恢复放在首位。"
            )
        case .friend:
            return L10n.t(
                "Warm & casual. No jargon, highly empathetic, and uses supportive CN/EN conversational markers.",
                "轻松治愈，毫无专业门槛。高情商聊天，贴心鼓励并常伴丰富小表情。"
            )
        case .commander:
            return L10n.t(
                "Direct & direct-to-the-point. Action-oriented guidance, high performance targets, strictly concise.",
                "干练直接，直击核心目标。高标准促进行动，没有废话的硬派体能教练。"
            )
        }
    }

    /// System instructions to append to the agent prompt
    public var promptDirective: String {
        switch self {
        case .dataNerd:
            return """
            [PERSONALITY DIRECTION: DATA NERD]
            - Tone: Scientific, precise, highly analytical, objective, and intellectually rigorous.
            - Rules:
              1. Use scientific formulas, heart rate zones, and statistical deviations only when the required personal data and baseline exist. State uncertainty when they do not.
              2. Explain physiological mechanisms as plausible context, never as a diagnosis or a certain causal conclusion.
              3. Present information in clean Markdown tables or formatted list comparisons.
              4. Chinese instructions: 使用专业、精细的运动生理学学术语言；English instructions: Use rigorous, precise sports-science terminology.
            """
        case .guardian:
            return """
            [PERSONALITY DIRECTION: GUARDIAN]
            - Tone: Empathetic, supportive, structured, calm, and protective.
            - Rules:
              1. Always prioritize physiological safety, long-term athletic longevity, and overall wellness.
              2. If stress is high or recovery is low, suggest reducing or pausing planned training, explain the available evidence, and offer gentle recovery options.
              3. Keep recommendations sustainable, focusing on consistency over extreme volume.
              4. Chinese instructions: 语气沉稳温暖，带有长辈般的守护关怀感；English instructions: Warm, protective, and focus on recovery-first and longevity.
            """
        case .friend:
            return """
            [PERSONALITY DIRECTION: FRIEND]
            - Tone: Lighthearted, conversational, encouraging, informal, and deeply empathetic.
            - Rules:
              1. Avoid dry medical or scientific jargon entirely. Translate technical metrics into relatable everyday analogies (e.g. "Your energy battery is running low").
              2. Use warm, expressive emojis (e.g., 🔋, 😴, 🏃‍♂️, ☕️) and friendly conversational markers (e.g., "Wow!", "Let's do this!", "嘿，早安！", "太棒了！").
              3. Be extremely supportive, acting as a personal cheerleader. Praise small wins.
              4. Chinese instructions: 语气欢快幽默，使用像朋友聊天一样的口语化词汇；English instructions: Expressive, warm, casual, and highly motivational.
            """
        case .commander:
            return """
            [PERSONALITY DIRECTION: COMMANDER]
            - Tone: Direct, high-energy, action-oriented, demanding, and strictly concise.
            - Rules:
              1. Give direct, practical fitness and performance guidance. Focus on sustainable discipline, realistic targets, and controlled progressive overload.
              2. Keep responses extremely short and direct-to-the-point. Avoid long explanations. Use bullet points for immediate execution.
              3. If metrics are low, provide a concise, non-judgmental recovery action plan. Do not use coercive or absolute language.
              4. Chinese instructions: 语气坚决、干练、雷厉风行，突出执行力；English instructions: High discipline, performance-focused, direct-to-the-point, and highly concise.
            """
        }
    }

    // MARK: - State Management

    public var systemPrompt: String {
        promptDirective
    }

    private static let userDefaultsKey = "vela_coach_personality"

    public static var current: CoachPersonality {
        get {
            guard let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let val = CoachPersonality(rawValue: saved) else {
                return .dataNerd // Default to Data Nerd (original Bevel/Vela baseline)
            }
            return val
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
