import SwiftUI

// MARK: - Section Header

struct BSectionHeader: View {
    let title: String
    var subtitle: String?    = nil
    var trailing: AnyView?   = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BSTheme.textMuted)
                    .tracking(1.2)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundColor(BSTheme.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let text: String
    var color: Color = BSTheme.electricCyan
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(BSTheme.textSecondary)
    }
}

// MARK: - Premium Action Button

enum PremiumButtonStyle { case gradient(LinearGradient), accent(Color), ghost }

struct PremiumActionButton: View {
    let title: String
    let icon: String
    var style: PremiumButtonStyle = .gradient(BSTheme.rangeGradient)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                    .strokeBorder(isPrimary ? TCTheme.gold.opacity(0.30) : BSTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// `.gradient` and `.accent` are strong primary CTAs; `.ghost` is a quiet panel.
    private var isPrimary: Bool {
        switch style {
        case .gradient, .accent: return true
        case .ghost:             return false
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .gradient, .accent: TCTheme.primaryFill
        case .ghost:             BSTheme.panel
        }
    }
    private var foregroundColor: Color {
        switch style {
        case .gradient: return TCTheme.onPrimary
        case .accent:   return TCTheme.onPrimary
        case .ghost:    return BSTheme.textPrimary
        }
    }
}

// MARK: - Stat Tile

struct StatTile: View {
    let label: String
    let value: String
    var unit: String?       = nil
    var icon: String?       = nil
    var accent: Color       = BSTheme.electricCyan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(BSTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSTheme.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .metricTile()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mode Card

struct BSModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    var chips: [String]     = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(BSTheme.textMuted)
                        .frame(width: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(BSTheme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(BSTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSTheme.textMuted)
                }
                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BSTheme.textMuted)
                        }
                        Spacer()
                    }
                }
            }
            .padding(18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                        .strokeBorder(BSTheme.border, lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let stat: String
    var statUnit: String = ""
    var accent: Color    = BSTheme.electricCyan
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(BSTheme.textMuted)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(stat)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(BSTheme.textPrimary)
                    if !statUnit.isEmpty {
                        Text(statUnit)
                            .font(.system(size: 10))
                            .foregroundColor(BSTheme.textMuted)
                    }
                }
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BSTheme.textMuted)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Feed Post Card

struct FeedPostCard: View {
    let playerName: String
    let timeAgo: String
    let activityTitle: String
    let summary: String
    var accentMetric: String?   = nil
    var accentLabel: String?    = nil
    var accentColor: Color      = BSTheme.electricCyan
    var stats: [(label: String, value: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(spacing: 10) {
                Circle()
                    .fill(accentColor.opacity(0.20))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(playerName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accentColor)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSTheme.textPrimary)
                    Text(timeAgo)
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                }
                Spacer()
                if let metric = accentMetric, let label = accentLabel {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(metric)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(accentColor)
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(BSTheme.textMuted)
                    }
                }
            }

            // Activity
            Text(activityTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSTheme.textPrimary)
            Text(summary)
                .font(.system(size: 13))
                .foregroundColor(BSTheme.textSecondary)
                .lineLimit(3)

            // Stats strip
            if !stats.isEmpty {
                HStack(spacing: 16) {
                    ForEach(stats, id: \.label) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.value)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(BSTheme.textPrimary)
                            Text(s.label)
                                .font(.system(size: 10))
                                .foregroundColor(BSTheme.textMuted)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BSTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Action row
            HStack(spacing: 20) {
                feedAction(icon: "heart",        label: "Like")
                feedAction(icon: "bubble.left",  label: "Comment")
                feedAction(icon: "square.and.arrow.up", label: "Share")
                Spacer()
            }
        }
        .premiumCard()
    }

    private func feedAction(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(BSTheme.textMuted)
    }
}

// MARK: - Settings Row

struct BSSettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String?   = nil
    var value: String?      = nil
    var accent: Color       = BSTheme.textMuted
    let action: () -> Void

    init(icon: String, title: String, subtitle: String? = nil, value: String? = nil,
         accent: Color = BSTheme.textMuted, action: @escaping () -> Void = {}) {
        self.icon = icon; self.title = title; self.subtitle = subtitle
        self.value = value; self.accent = accent; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundColor(BSTheme.textPrimary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundColor(BSTheme.textMuted)
                    }
                }
                Spacer()
                if let v = value {
                    Text(v)
                        .font(.system(size: 14))
                        .foregroundColor(BSTheme.textMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BSTheme.textMuted.opacity(0.5))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Container

struct BSSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BSectionHeader(title: title)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content
            }
            .background(BSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                    .strokeBorder(BSTheme.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Divider

struct BSDivider: View {
    var body: some View {
        Rectangle()
            .fill(BSTheme.border)
            .frame(height: 1)
            .padding(.leading, 64)
    }
}

// MARK: - Hero Card

struct HeroCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(BSTheme.panel)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(BSTheme.heroGradient)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(BSTheme.borderBright, lineWidth: 1)
                }
            )
            .shadow(color: BSTheme.electricCyan.opacity(0.12), radius: 24, x: 0, y: 8)
    }
}
