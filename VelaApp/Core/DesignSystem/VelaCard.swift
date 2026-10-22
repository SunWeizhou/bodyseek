import SwiftUI

// MARK: - Canonical Metric Card

struct VelaMetricCard<Accessory: View>: View {
    let title: String
    let value: String
    var unit: String? = nil
    let subtitle: String
    let domain: VelaMetricDomain
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        value: String,
        unit: String? = nil,
        subtitle: String,
        domain: VelaMetricDomain = .neutral,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.subtitle = subtitle
        self.domain = domain
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: VelaTheme.inlineGap) {
                Label(title, systemImage: domain.systemImage)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.fg2)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 4)
                accessory()
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(VelaTheme.cardValue())
                    .foregroundStyle(VelaTheme.fg)
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)

                if let unit {
                    Text(unit)
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.muted)
                }
            }

            Text(subtitle)
                .font(VelaTheme.caption1())
                .foregroundStyle(VelaTheme.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VelaTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.cardBg, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                .stroke(domain.color.opacity(0.16), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)\(unit.map { " \($0)" } ?? "")。\(subtitle)")
    }
}

extension VelaMetricCard where Accessory == EmptyView {
    init(
        title: String,
        value: String,
        unit: String? = nil,
        subtitle: String,
        domain: VelaMetricDomain = .neutral
    ) {
        self.init(
            title: title,
            value: value,
            unit: unit,
            subtitle: subtitle,
            domain: domain,
            accessory: { EmptyView() }
        )
    }
}

struct VelaEvidenceRow: View {
    let title: String
    let detail: String
    let value: String
    var systemImage: String = "waveform.path.ecg"
    var tint: Color = VelaTheme.accent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.fg)
                Text(detail)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(VelaTheme.headline().monospacedDigit())
                .foregroundStyle(VelaTheme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, VelaTheme.compactCardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: VelaTheme.minimumHitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)。\(detail)")
    }
}

// MARK: - VitalCard (vitals metric card)

// MARK: - InfoCard (dual metric card)

// MARK: - InsightCard (coach insight with left accent bar)

struct InsightCard: View {
    let title: String
    let bodyText: String
    let cta: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(VelaTheme.caption2())
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .kerning(0.04)
                    .foregroundStyle(VelaTheme.accent)

                Text(bodyText)
                    .font(VelaTheme.subheadline())
                    .lineSpacing(4)
                    .foregroundStyle(VelaTheme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(cta)
                        .font(VelaTheme.subheadline())
                        .fontWeight(.medium)
                    Image(systemName: "chevron.forward")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                }
                .foregroundStyle(VelaTheme.accent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .stroke(VelaTheme.borderSoft, lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(VelaTheme.accent)
                    .frame(width: 3)
                    .padding(.leading, 1)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .buttonStyle(.cardPress)
    }
}

// MARK: - EmptyStateCard

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionLabel: String?
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(VelaTheme.meta)

            Text(title)
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.fg)

            Text(subtitle)
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            if let label = actionLabel, let action = onAction {
                Button(action: action) {
                    Text(label)
                        .font(VelaTheme.subheadline())
                        .fontWeight(.medium)
                        .foregroundStyle(VelaTheme.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(VelaTheme.accent, lineWidth: 1)
                        )
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .fill(VelaTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .stroke(VelaTheme.border, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }
}

// MARK: - WorkoutCard

struct WorkoutCard: View {
    let badge: String
    let badgeColor: Color
    let badgeBg: Color
    let title: String
    let duration: String
    let originalPlan: String?
    let adaptedPlan: String
    let reason: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(badge)
                        .font(VelaTheme.caption2())
                        .fontWeight(.semibold)
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous).fill(badgeBg)
                        )

                    Text(title)
                        .font(.system(.callout, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.fg)

                    Spacer()

                    Text(duration)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.muted)
                }

                if let original = originalPlan {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.warn)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(original)
                                .font(VelaTheme.caption1())
                                .foregroundStyle(VelaTheme.meta)
                                .strikethrough()

                            Text(adaptedPlan)
                                .font(VelaTheme.caption1())
                                .foregroundStyle(VelaTheme.fg)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                            .fill(VelaTheme.elevatedBg)
                    )
                } else {
                    Text(adaptedPlan)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.fg)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                                .fill(VelaTheme.elevatedBg)
                        )
                }

                Text(reason)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.meta)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .fill(VelaTheme.cardBg)
            )
        }
        .buttonStyle(.cardPress)
    }
}

// MARK: - VelaGlassCard — retained API, calm adaptive surface

struct VelaGlassCard<Content: View>: View {
    var padding: CGFloat = VelaTheme.space4
    var cornerRadius: CGFloat = VelaTheme.radiusLg
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VelaTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VelaTheme.borderSoft, lineWidth: 0.5)
            )
    }
}

// MARK: - VelaMemoryProposalCard — proposal-based card for WikiProfileView compat

struct VelaMemoryProposalCardCompat: View {
    var title: String = ""
    var evidence: String = ""
    var confidence: String = ""
    var source: String = ""
    var target: String = ""
    var proposal: Any?
    var onAccept: (() -> Void)?
    var onEdit: (() -> Void)?
    var onReject: (() -> Void)?

    var body: some View {
        let displayTitle: String = {
            if let p = proposal as? MemoryProposal { return p.displayTitle }
            if let r = proposal as? MemoryEventRecord { return r.content }
            return title
        }()
        let displayEvidence: String = {
            if let p = proposal as? MemoryProposal { return p.content }
            if let r = proposal as? MemoryEventRecord { return r.evidence }
            return evidence
        }()
        let displayConfidence: String = {
            if let p = proposal as? MemoryProposal { return String(format: "%.0f%%", p.confidence * 100) }
            if let r = proposal as? MemoryEventRecord { return String(format: "%.0f%%", r.confidence * 100) }
            return confidence
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VelaStatusBadge(label: "Pattern", systemImage: "brain.head.profile", tint: VelaTheme.accent)
                Spacer()
                Text("\(displayConfidence) confidence")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
            }
            Text(displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VelaTheme.fg)
            Text(displayEvidence)
                .font(VelaTheme.captionLarge())
                .foregroundStyle(VelaTheme.fg2)
            if !source.isEmpty || !target.isEmpty {
                HStack(spacing: 8) {
                    VelaMetricPill(title: "Source", value: source, systemImage: "point.3.connected.trianglepath.dotted", tint: VelaTheme.rhythmInk)
                    VelaMetricPill(title: "Target", value: target, systemImage: "doc.text", tint: VelaTheme.rhythmInk)
                }
            }
            HStack(spacing: 10) {
                Button(action: { onAccept?() }) {
                    Label("Confirm", systemImage: "checkmark")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(VelaTheme.accent)
                if onEdit != nil {
                    Button(action: { onEdit?() }) {
                        Label("Edit", systemImage: "pencil")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(VelaTheme.accent)
                }
                Button(action: { onReject?() }) {
                    Label("Reject", systemImage: "xmark")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(VelaTheme.muted)
            }
        }
        .padding(VelaTheme.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .fill(VelaTheme.cardBg)
        )
    }
}

typealias VelaMemoryProposalCard = VelaMemoryProposalCardCompat

// MARK: - VelaStatusBadge

struct VelaStatusBadgeCompat: View {
    let label: String
    var systemImage: String?
    var tint: Color = VelaTheme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.system(.caption2, design: .default))
            }
            Text(label)
                .font(VelaTheme.caption2())
                .fontWeight(.medium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().stroke(tint.opacity(0.10), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
typealias VelaStatusBadge = VelaStatusBadgeCompat

// MARK: - VelaMetricPill

struct VelaMetricPill: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = VelaTheme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.system(.caption2, design: .default))
            }
            Text("\(title) ")
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.muted)
            + Text(value)
                .font(VelaTheme.caption2().weight(.semibold))
                .foregroundStyle(VelaTheme.fg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - VelaHeroSurface

struct VelaHeroSurface<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(VelaTheme.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusFeature, style: .continuous)
                    .fill(tint.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusFeature, style: .continuous)
                    .stroke(tint.opacity(0.2), lineWidth: 0.5)
            )
    }
}

// MARK: - VelaEmptyState

struct VelaEmptyStateCompat: View {
    var title: String = ""
    var subtitle: String = ""
    var message: String = ""
    var systemImage: String = "questionmark.circle"
    var tint: Color = VelaTheme.accent
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(.title2, design: .default, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.12)))
            Text(title)
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.fg)
            let supportingText = message.isEmpty ? subtitle : message
            if !supportingText.isEmpty {
                Text(supportingText)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.muted)
                    .multilineTextAlignment(.center)
            }
            if let label = actionLabel, let action = action {
                Button(action: action) {
                    Text(label)
                        .font(VelaTheme.subheadline())
                        .fontWeight(.medium)
                        .foregroundStyle(VelaTheme.accentOn)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(VelaTheme.accent))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg)
                .fill(VelaTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg)
                .stroke(VelaTheme.borderSoft, lineWidth: 0.5)
        )
    }
}
typealias VelaEmptyState = VelaEmptyStateCompat
