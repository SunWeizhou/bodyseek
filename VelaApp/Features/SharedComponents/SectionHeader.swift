import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.title, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.fg)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
