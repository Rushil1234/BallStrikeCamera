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
            BallStrikeBackgroundView()
            VStack(spacing: 16) {
                Image(systemName: "circle.inset.filled")
                    .font(.system(size: 54, weight: .black))
                    .foregroundColor(BSTheme.electricCyan)
                    .glowingAccent(BSTheme.electricCyan, radius: 30)
                Text("BallStrike")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}
