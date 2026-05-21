import SwiftUI

// MARK: - Models

private struct SessionMock: Identifiable {
    let id = UUID()
    let type: SessionType
    let title: String
    let subtitle: String
    let stat: String
    let statUnit: String
    let date: String
    let icon: String
    let accent: Color

    enum SessionType { case shot, range, sim, course }
}

// MARK: - View

struct SessionsView: View {
    @State private var filter: FilterTab = .all

    private let sessions: [SessionMock] = [
        SessionMock(type: .range,  title: "Range Session",       subtitle: "7 Iron focus · 23 shots",      stat: "156",  statUnit: "yd avg",    date: "Today",      icon: "target",               accent: BSTheme.electricCyan),
        SessionMock(type: .shot,   title: "Driver Shot",         subtitle: "Best of the day",               stat: "263",  statUnit: "yd total",  date: "Today",      icon: "circle.inset.filled",  accent: BSTheme.fairwayGreen),
        SessionMock(type: .range,  title: "Range Session",       subtitle: "Mixed bag · 18 shots",          stat: "152",  statUnit: "yd avg",    date: "Yesterday",  icon: "target",               accent: BSTheme.electricCyan),
        SessionMock(type: .shot,   title: "7 Iron Shot",         subtitle: "Solid strike",                  stat: "164",  statUnit: "yd carry",  date: "Yesterday",  icon: "circle.inset.filled",  accent: BSTheme.fairwayGreen),
        SessionMock(type: .sim,    title: "Local Sim Session",   subtitle: "8 shots sent · GSPro",          stat: "8",    statUnit: "shots",     date: "May 12",     icon: "display",              accent: BSTheme.simBlue),
        SessionMock(type: .range,  title: "Range Session",       subtitle: "Driver focus · 31 shots",       stat: "161",  statUnit: "yd avg",    date: "May 12",     icon: "target",               accent: BSTheme.electricCyan),
        SessionMock(type: .course, title: "Pebble Beach (Mock)", subtitle: "18 holes · Blue tees",          stat: "82",   statUnit: "score",     date: "May 10",     icon: "flag.fill",            accent: BSTheme.gold),
        SessionMock(type: .shot,   title: "Driver Shot",         subtitle: "Personal best",                 stat: "284",  statUnit: "yd total",  date: "May 8",      icon: "circle.inset.filled",  accent: BSTheme.fairwayGreen),
    ]

    private var filtered: [SessionMock] {
        switch filter {
        case .all:    return sessions
        case .shots:  return sessions.filter { $0.type == .shot }
        case .range:  return sessions.filter { $0.type == .range }
        case .rounds: return sessions.filter { $0.type == .course || $0.type == .sim }
        }
    }

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSTheme.sectionGap) {
                    summaryStrip
                    filterPicker
                    sessionList
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, BSTheme.hPad)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
    }

    // MARK: Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            StatTile(label: "Total Sessions", value: "8",   icon: "list.bullet",           accent: BSTheme.electricCyan)
            StatTile(label: "Total Shots",    value: "127", icon: "circle.inset.filled",   accent: BSTheme.fairwayGreen)
            StatTile(label: "Best Carry",     value: "284", unit: "yd", icon: "arrow.up.right", accent: BSTheme.gold)
        }
    }

    // MARK: Filter Picker

    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(FilterTab.allCases, id: \.self) { tab in
                Button { withAnimation(.easeInOut(duration: 0.2)) { filter = tab } } label: {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(filter == tab ? .black : BSTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            filter == tab
                                ? AnyView(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(BSTheme.electricCyan)
                                )
                                : AnyView(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
    }

    // MARK: Session List

    private var sessionList: some View {
        VStack(spacing: 8) {
            ForEach(filtered) { s in
                sessionCard(s)
            }
        }
    }

    private func sessionCard(_ s: SessionMock) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(s.accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: s.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(s.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text(s.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(s.stat)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(BSTheme.textPrimary)
                }
                Text(s.statUnit)
                    .font(.system(size: 10))
                    .foregroundColor(BSTheme.textMuted)
                Text(s.date)
                    .font(.system(size: 10))
                    .foregroundColor(BSTheme.textMuted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
    }
}

private enum FilterTab: String, CaseIterable {
    case all, shots, range, rounds
    var label: String {
        switch self {
        case .all:    return "All"
        case .shots:  return "Shots"
        case .range:  return "Range"
        case .rounds: return "Rounds"
        }
    }
}
