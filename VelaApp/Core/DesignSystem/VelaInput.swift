import SwiftUI

// MARK: - SettingsRow

struct SettingsRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    var value: String?
    var onTap: () -> Void

    var body: some View {
        let _ = iconBg
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(.callout, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .frame(width: 30, height: 30)
                    .background(VelaTheme.rhythmMist)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)

                Text(title)
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.fg)

                Spacer()

                if let value = value {
                    Text(value)
                        .font(VelaTheme.body())
                        .foregroundStyle(VelaTheme.meta)
                }

                Image(systemName: "chevron.forward")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.meta.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ToggleRow

struct ToggleRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    @Binding var isOn: Bool
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        let _ = iconBg
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(.callout, design: .default))
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(width: 30, height: 30)
                .background(VelaTheme.rhythmMist)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .font(VelaTheme.body())
                .foregroundStyle(VelaTheme.fg)

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(VelaTheme.accent)
                .labelsHidden()
                .onChange(of: isOn) { _, val in
                    onToggle?(val)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - EvidenceStep

struct EvidenceStep: View {
    let step: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step)")
                .font(VelaTheme.monoCaption())
                .fontWeight(.bold)
                .foregroundStyle(VelaTheme.accentOn)
                .frame(width: 22, height: 22)
                .background(VelaTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VelaTheme.subheadline())
                    .fontWeight(.semibold)
                    .foregroundStyle(VelaTheme.fg)
                Text(detail)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.muted)
                    .lineSpacing(2)
            }
        }
    }
}

// MARK: - DataFreshnessBar

// MARK: - QuickEntryButton

struct QuickEntryButton: View {
    let icon: String
    let iconBg: Color
    let iconFg: Color
    let label: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconFg)
                    .frame(width: 36, height: 36)
                    .background(iconBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(label)
                    .font(VelaTheme.subheadline())
                    .fontWeight(.medium)
                    .foregroundStyle(VelaTheme.fg)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .fill(VelaTheme.cardBg)
            )
        }
        .buttonStyle(.cardPress)
    }
}

// MARK: - TagChip

struct TagChip: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(VelaTheme.caption1())
            .fontWeight(.medium)
            .foregroundStyle(VelaTheme.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(VelaTheme.cardBg)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(VelaTheme.borderSoft, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - SettingsGroup

struct SettingsGroup<Content: View>: View {
    var header: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = header {
                Text(header)
                    .font(VelaTheme.caption1())
                    .fontWeight(.medium)
                    .foregroundStyle(VelaTheme.muted)
                    .textCase(.uppercase)
                    .kerning(0.02)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                    .fill(VelaTheme.cardBg)
            )
        }
    }
}

// MARK: - PlusAction

struct PlusAction: View {
    let icon: String
    let iconBg: Color
    let iconFg: Color
    let title: String
    let subtitle: String

    var body: some View {
        let _ = (iconBg, iconFg)
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(.title2, design: .default))
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(width: 44, height: 44)
                .background(VelaTheme.rhythmMist)
                .clipShape(Circle())

            Text(title)
                .font(VelaTheme.subheadline())
                .fontWeight(.semibold)
                .foregroundStyle(VelaTheme.fg)

            Text(subtitle)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .fill(VelaTheme.surface)
        )
    }
}
