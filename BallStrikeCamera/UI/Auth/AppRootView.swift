import SwiftUI

struct AppRootView: View {
    @EnvironmentObject var session: AuthSessionStore

    var body: some View {
        Group {
            if session.isLoading {
                splashView
            } else if session.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var splashView: some View {
        ZStack {
            TrueCarryBackground()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(TCTheme.panelRaised)
                        .frame(width: 74, height: 74)
                    Circle()
                        .strokeBorder(TCTheme.borderGold, lineWidth: 1.5)
                        .frame(width: 74, height: 74)
                    Image(systemName: "flag.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                }
                VStack(spacing: 6) {
                    TrueCarryLogo(size: 28)
                    Text("Loading your game")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
        }
    }
}
