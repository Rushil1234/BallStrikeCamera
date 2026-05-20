import SwiftUI

struct AppRootView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var splashVisible = false

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
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                splashVisible = true
            }
        }
    }

    private var splashView: some View {
        ZStack {
            TrueCarryBackground()
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    TrueCarryLogo(size: 32)
                    Text("Loading your game")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            .opacity(splashVisible ? 1 : 0)
            .offset(y: splashVisible ? 0 : 12)
        }
    }
}
