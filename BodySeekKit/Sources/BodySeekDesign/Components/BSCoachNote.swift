import SwiftUI

/// 简报生成引擎，用于标注解读的来源。
public enum BSBriefEngine: Sendable, Hashable, CaseIterable {
    /// 云端模型。
    case cloud
    /// 端侧模型。
    case onDevice
    /// 本地模板（离线或模型不可用时）。
    case localTemplate

    var title: String {
        switch self {
        case .cloud: "云端"
        case .onDevice: "端侧"
        case .localTemplate: "本地模板"
        }
    }
}

/// L1 解读条：Coach 徽记 + 一段话 + 依据 chip + "问 Coach"按钮，并标注生成引擎。
///
/// 生成中先显示本地模板文字，生成完成后原地替换；`isLoading` 为 `true` 时文字显示骨架。
public struct BSCoachNote: View {
    private let text: String?
    private let engine: BSBriefEngine
    private let evidence: [String]
    private let isLoading: Bool
    private let onEvidenceTap: ((String) -> Void)?
    private let onAsk: (() -> Void)?

    /// 创建 Coach 解读条。
    /// - Parameters:
    ///   - text: 解读文字；`nil` 显示"暂无解读"。
    ///   - engine: 生成引擎。
    ///   - evidence: 依据 chip 的文字。
    ///   - isLoading: 为 `true` 时文字显示骨架。
    ///   - onEvidenceTap: 点击依据 chip 的回调。
    ///   - onAsk: "问 Coach"按钮动作；为 `nil` 时不显示。
    public init(
        _ text: String?,
        engine: BSBriefEngine = .localTemplate,
        evidence: [String] = [],
        isLoading: Bool = false,
        onEvidenceTap: ((String) -> Void)? = nil,
        onAsk: (() -> Void)? = nil
    ) {
        self.text = text
        self.engine = engine
        self.evidence = evidence
        self.isLoading = isLoading
        self.onEvidenceTap = onEvidenceTap
        self.onAsk = onAsk
    }

    public var body: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Label("Coach", systemImage: "sparkles")
                        .bsText(.cardTitle)
                    Spacer(minLength: BSSpace.xs)
                    Text(engine.title)
                        .bsText(.caption)
                }
                Text(text ?? "暂无解读")
                    .bsText(.body)
                    .redacted(reason: isLoading ? .placeholder : [])
                if !evidence.isEmpty {
                    evidenceRow
                }
                if let onAsk {
                    Button(action: onAsk) {
                        Label("问 Coach", systemImage: "bubble.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: BSSize.hitTarget)
                }
            }
        }
    }

    private var evidenceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpace.xs) {
                ForEach(evidence, id: \.self) { item in
                    BSEvidenceChip(item, action: chipAction(for: item))
                }
            }
        }
    }

    private func chipAction(for item: String) -> (() -> Void)? {
        guard let onEvidenceTap else { return nil }
        return { onEvidenceTap(item) }
    }
}
