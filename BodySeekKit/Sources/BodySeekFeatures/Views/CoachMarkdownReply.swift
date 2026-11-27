import BodySeekDesign
import Foundation
import SwiftUI
import Textual

struct CoachMarkdownReply: View {
    let source: String

    var body: some View {
        StructuredText(source, parser: CoachMarkdownParser())
            .font(.body)
            .foregroundStyle(BevelTheme.ink)
            .tint(BevelTheme.brand)
            .textual.headingStyle(CoachHeadingStyle())
            .textual.paragraphStyle(CoachParagraphStyle())
            .textual.listItemStyle(.default(markerSpacing: .fontScaled(0.4)))
            .textual.textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme?.lowercased() == "https", url.host != nil else {
                    return .discarded
                }
                return .systemAction
            })
    }
}

private struct CoachHeadingStyle: StructuredText.HeadingStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.fontScale(configuration.headingLevel < 3 ? 1.15 : 1)
            .textual.blockSpacing(.fontScaled(top: 0.8, bottom: 0.25))
            .fontWeight(.semibold)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CoachParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.23))
            .textual.blockSpacing(.fontScaled(top: 0.55))
    }
}

struct CoachMarkdownParser: MarkupParser {
    func attributedString(for input: String) -> AttributedString {
        do {
            let parser = AttributedStringMarkdownParser(baseURL: nil)
            var content = try parser.attributedString(for: input)
            // Preserve image descriptions as text without fetching model-provided URLs.
            content.imageURL = nil
            return content
        } catch {
            return AttributedString(input)
        }
    }
}
