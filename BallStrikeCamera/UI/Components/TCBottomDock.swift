import SwiftUI

// MARK: - Tab Enum

enum TCTab: Int, CaseIterable {
    case home = 0, insights = 1, play = 2, locker = 3

    var label: String {
        switch self {
        case .home:     return "Feed"
        case .insights: return "Insights"
        case .play:     return "Play"
        case .locker:   return "Locker"
        }
    }
    var icon: String {
        switch self {
        case .home:     return "newspaper.fill"
        case .insights: return "chart.bar.xaxis"
        case .play:     return "flag.fill"
        case .locker:   return "person.crop.circle.fill"
        }
    }
    var isCenter: Bool { self == .play }
}

// MARK: - Bottom Dock

struct TCBottomDock: View {
    @Binding var selectedTab: TCTab
    @Environment(\.safeAreaInsets) private var safeInsets

    private var bottomPadding: CGFloat { max(safeInsets.bottom, 6) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(TCTab.allCases, id: \.rawValue) { tab in
                dockItem(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, bottomPadding)
        .background(
            Rectangle()
                .fill(TCTheme.dockBackground)
                .overlay(Rectangle().fill(TCTheme.borderMedium).frame(height: 1), alignment: .top)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: -3)
    }

    private func dockItem(_ tab: TCTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: tab == .play ? 18 : 17, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                Text(tab.label)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                Rectangle()
                    .fill(selected ? TCTheme.gold : Color.clear)
                    .frame(width: selected ? 18 : 0, height: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .animation(.easeInOut(duration: 0.20), value: selected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safe Area Insets (environment key)

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets = .init()
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

// MARK: - App Shell

struct TrueCarryAppShell: View {
    @State private var selectedTab: TCTab = .home
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                tabContent
                    .ignoresSafeArea(edges: .bottom)
                    .environment(\.safeAreaInsets, geo.safeAreaInsets)

                VStack(spacing: 0) {
                    Spacer()
                    TCBottomDock(selectedTab: $selectedTab)
                        .environment(\.safeAreaInsets, geo.safeAreaInsets)
                }
                .ignoresSafeArea(.keyboard)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(TCTheme.background.ignoresSafeArea())
        .tcAppearance()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack { FeedHomeView() }
        case .insights:
            NavigationStack { TrueCarryInsightsView() }
        case .play:
            NavigationStack { TrueCarryPlayView() }
        case .locker:
            NavigationStack { TrueCarryLockerView() }
        }
    }
}
