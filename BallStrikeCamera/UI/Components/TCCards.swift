import SwiftUI

// MARK: - Section Header

struct TCSectionHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var viewAllAction: (() -> Void)? = nil

    init(title: String, trailing: AnyView? = nil) {
        self.title = title; self.trailing = trailing
    }
    init(title: String, viewAllAction: @escaping () -> Void) {
        self.title = title; self.viewAllAction = viewAllAction
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
            if let action = viewAllAction {
                Button("View All") { action() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
            } else if let t = trailing { t }
        }
    }
}

// MARK: - Divider

struct TCDivider: View {
    var body: some View {
        Rectangle()
            .fill(TCTheme.border)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

// MARK: - Pill

struct TCPill: View {
    let text: String
    var color: Color = TCTheme.gold
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - Metric Tile

struct TCMetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var accent: Color = TCTheme.gold

    var body: some View {
        VStack(spacing: 5) {
            Text(value + (unit.isEmpty ? "" : " " + unit))
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.0)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }
}

// MARK: - Settings Row

struct TCSettingsRow: View {
    let icon: String
    let title: String
    var value: String = ""
    var accent: Color = TCTheme.textMuted
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textMuted)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Session Card (activity feed / history)

struct TCSessionCard: View {
    let icon: String
    let mode: String
    let detail: String
    let stat: String
    let statLabel: String
    var accent: Color = TCTheme.cyan
    var thumbnail: AnyView? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mode)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if let thumb = thumbnail {
                thumb.frame(width: 52, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(stat)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                Text(statLabel)
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
        .tcCard()
    }
}

// MARK: - Mode Card (Play screen horizontal mode picker)

struct TCModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var accent: Color = TCTheme.gold
    var isSelected: Bool = false
    var illustration: AnyView? = nil   // optional custom Canvas illustration
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    if let illus = illustration {
                        illus
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                            )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(accent.opacity(0.12))
                                .frame(width: 56, height: 56)
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(accent)
                        }
                    }
                    if isSelected {
                        ZStack {
                            Circle().fill(accent).frame(width: 20, height: 20)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.black)
                        }
                        .offset(x: 8, y: -8)
                    }
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(isSelected ? accent.opacity(0.07) : TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.60) : TCTheme.border,
                                  lineWidth: isSelected ? 1.8 : 1)
            )
            .shadow(color: isSelected ? accent.opacity(0.12) : Color.clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary Gold Button

struct TCPrimaryGoldButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(TCTheme.goldGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: TCTheme.goldShadow, radius: 10, x: 0, y: 4)
    }
}

// MARK: - Outline/Secondary Button

struct TCOutlineButton: View {
    let title: String
    var color: Color = TCTheme.gold
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.35), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip Button

struct TCChipButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let ic = icon {
                    Image(systemName: ic).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(TCTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(TCTheme.panel)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Group (icon + value + label stack)

struct TCStatGroup: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = TCTheme.gold

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(color)
                .frame(height: 22)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Club Row (for Clubs in Bag)

struct TCClubRow: View {
    let category: String
    let name: String
    var color: Color = TCTheme.sage

    var body: some View {
        HStack(spacing: 12) {
            Text(category)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
                .tracking(1.0)
                .frame(width: 56, alignment: .leading)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TCTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Ranking Row (Courses hub ranking)

struct TCRankingRow: View {
    let rank: Int
    let courseName: String
    let location: String
    var playedCount: Int = 1
    var rating: Double = 9.0
    var thumbnailSeed: Int = 0
    var course: GolfCourse? = nil

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(rank == 1 ? TCTheme.gold : rank <= 3 ? TCTheme.textSecondary : TCTheme.textMuted)
                .frame(width: 26, alignment: .center)

            // Course thumbnail — MapKit or generated aerial
            Group {
                if let c = course {
                    CourseImageView(course: c, seed: thumbnailSeed, cornerRadius: 10)
                } else {
                    TCCourseAerialThumbnail(seed: thumbnailSeed)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(width: 56, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(courseName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                        .foregroundColor(TCTheme.textMuted)
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                TCPill(text: "Played \(playedCount)×", color: TCTheme.sage)
            }

            Spacer(minLength: 6)

            // Rating badge
            ZStack {
                Circle()
                    .strokeBorder(TCTheme.goldGradient, lineWidth: 1.8)
                    .frame(width: 42, height: 42)
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.gold)
            }
        }
        .tcCard()
    }
}

// MARK: - Shot Thumb (saved shot mini card)

struct TCShotThumb: View {
    let clubName: String
    let yards: Int
    var isBest: Bool = false

    private var isDriver: Bool { clubName.lowercased().hasPrefix("dr") }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Premium shot arc background
                TCShotArcThumbPremium(yards: yards, isDriver: isDriver)
                if isBest {
                    Text("BEST")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(TCTheme.goldGradient)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .frame(height: 60)

            VStack(spacing: 2) {
                Text(clubName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("\(yards) yds")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.gold)
            }
            .padding(.vertical, 8)
            .background(TCTheme.panelRaised)
        }
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1))
    }
}

// MARK: - Milestone Badge

struct TCMilestoneBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(TCTheme.goldGradient, lineWidth: 2)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1))
    }
}

// MARK: - Trend Line Chart (simple sparkline)

struct TCTrendLine: View {
    var values: [Double] = []
    var color: Color = TCTheme.sage

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let w = size.width; let h = size.height
            let minV = (values.min() ?? 0) * 0.94
            let maxV = (values.max() ?? 1) * 1.02
            let range = maxV - minV
            let pts = values.enumerated().map { i, v -> CGPoint in
                CGPoint(x: w * CGFloat(i) / CGFloat(values.count - 1),
                        y: h - h * CGFloat((v - minV) / range))
            }
            // Area fill
            var area = Path()
            area.move(to: CGPoint(x: pts[0].x, y: h))
            pts.forEach { area.addLine(to: $0) }
            area.addLine(to: CGPoint(x: pts.last!.x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .color(color.opacity(0.14)))
            // Line
            var line = Path()
            line.move(to: pts[0])
            for pt in pts.dropFirst() { line.addLine(to: pt) }
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // Dots
            for pt in pts {
                ctx.fill(Path(ellipseIn:CGRect(x:pt.x-3,y:pt.y-3,width:6,height:6)),
                         with:.color(color))
            }
        }
    }
}

// MARK: - Bar Row (Club distance bars)

struct TCBarRow: View {
    let label: String
    let value: Int
    let maxValue: Int
    var color: Color = TCTheme.gold

    var fraction: CGFloat { CGFloat(value) / CGFloat(max(maxValue, 1)) }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TCTheme.textSecondary)
                .frame(width: 28, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(TCTheme.panelRaised).frame(height: 7)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: g.size.width * fraction, height: 7)
                }
            }
            .frame(height: 7)
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - Filter Tab Bar

struct TCFilterTabBar: View {
    let tabs: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.self) { tab in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = tab } } label: {
                        Text(tab)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selected == tab ? .black : TCTheme.textMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selected == tab ? TCTheme.goldGradient :
                                            LinearGradient(colors: [TCTheme.panel], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Segmented Tab Underline Bar

struct TCUnderlineTabs: View {
    let tabs: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    VStack(spacing: 6) {
                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = tab } } label: {
                            Text(tab)
                                .font(.system(size: 13, weight: selected == tab ? .bold : .medium))
                                .foregroundColor(selected == tab ? TCTheme.textPrimary : TCTheme.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Rectangle()
                            .fill(selected == tab ? TCTheme.gold : Color.clear)
                            .frame(height: 2)
                    }
                }
            }
        }
        .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Feed Activity Card

struct TCFeedCard: View {
    let avatarInitials: String
    let name: String
    let mode: String         // "Round" or "Practice"
    let courseName: String
    let dateStr: String
    let primaryStat: String
    let primaryLabel: String
    var secondaryStat: String = ""
    var secondaryLabel: String = ""
    var tertiaryStat: String = ""
    var tertiaryLabel: String = ""
    var accent: Color = TCTheme.sage
    var thumbnailView: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                Text(String(avatarInitials.prefix(2)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .bold)).foregroundColor(TCTheme.textPrimary)
                    HStack(spacing: 4) {
                        Image(systemName: mode == "Round" ? "flag.fill" : "target")
                            .font(.system(size: 10))
                            .foregroundColor(accent)
                        Text(courseName).font(.system(size: 12)).foregroundColor(TCTheme.textMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dateStr).font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
                    Text(mode)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accent)
                }
            }

            Divider().background(TCTheme.border).padding(.vertical, 10)

            HStack(spacing: 0) {
                // Stats
                VStack(alignment: .leading, spacing: 10) {
                    statItem(label: primaryLabel, value: primaryStat)
                    if !secondaryStat.isEmpty { statItem(label: secondaryLabel, value: secondaryStat) }
                    if !tertiaryStat.isEmpty { statItem(label: tertiaryLabel, value: tertiaryStat) }
                }

                Spacer()

                // Thumbnail
                if let thumb = thumbnailView {
                    thumb
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(TCTheme.border, lineWidth: 1))
                }
            }
        }
        .tcCard()
    }

    private func statItem(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
        }
    }
}
