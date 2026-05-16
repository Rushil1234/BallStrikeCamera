import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(
            red: 0.02, green: 0.04, blue: 0.08, alpha: 0.96
        )

        let cyan = UIColor(red: 0.00, green: 0.86, blue: 1.00, alpha: 1.0)
        let muted = UIColor.white.withAlphaComponent(0.38)

        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ] {
            layout.selected.iconColor                            = cyan
            layout.selected.titleTextAttributes                  = [.foregroundColor: cyan,
                                                                     .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
            layout.normal.iconColor                              = muted
            layout.normal.titleTextAttributes                    = [.foregroundColor: muted,
                                                                     .font: UIFont.systemFont(ofSize: 10, weight: .medium)]
        }

        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView()
            }
            .tabItem { Label("Home",      systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                ModeSelectionView()
            }
            .tabItem { Label("Modes",     systemImage: "scope") }
            .tag(1)

            NavigationStack {
                SessionsView()
            }
            .tabItem { Label("Sessions",  systemImage: "list.bullet.rectangle.fill") }
            .tag(2)

            NavigationStack {
                AnalyticsView()
            }
            .tabItem { Label("Analytics", systemImage: "chart.xyaxis.line") }
            .tag(3)

            NavigationStack {
                FeedView()
            }
            .tabItem { Label("Feed",      systemImage: "person.2.fill") }
            .tag(4)

            NavigationStack {
                ProfileSettingsView()
            }
            .tabItem { Label("Profile",   systemImage: "person.circle.fill") }
            .tag(5)
        }
        .tint(BSTheme.electricCyan)
        .preferredColorScheme(.dark)
    }
}
