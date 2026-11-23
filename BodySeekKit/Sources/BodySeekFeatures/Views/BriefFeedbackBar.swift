import BodySeekDesign
import BodySeekStore
import SwiftUI

/// 简报反馈：准 / 不准 / 没用。一天只记一次，选完后显示感谢。
struct BriefFeedbackBar: View {
    let selected: BriefFeedbackRating?
    let onSelect: (BriefFeedbackRating) -> Void

    var body: some View {
        HStack(spacing: BSSpace.xs) {
            Text("这条结论")
                .bsText(.caption)
            ForEach(BriefFeedbackRating.allCases, id: \.self) { rating in
                feedbackButton(rating)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-brief-feedback")
    }

    private func feedbackButton(_ rating: BriefFeedbackRating) -> some View {
        let isSelected = selected == rating
        return Button {
            onSelect(rating)
        } label: {
            Text(title(rating))
                .bsText(.label)
                .padding(.horizontal, BSSpace.s)
                .padding(.vertical, BSSpace.xxs)
                .background(isSelected ? BSColor.tint.opacity(BSOpacity.faint) : BSColor.surfaceInset, in: Capsule())
        }
        .buttonStyle(.bsPressable)
        .disabled(selected != nil)
        .frame(minHeight: BSSize.hitTarget)
        .accessibilityIdentifier("today-brief-feedback-\(rating.rawValue)")
    }

    private func title(_ rating: BriefFeedbackRating) -> String {
        switch rating {
        case .accurate: "准"
        case .inaccurate: "不准"
        case .useless: "没用"
        }
    }
}
