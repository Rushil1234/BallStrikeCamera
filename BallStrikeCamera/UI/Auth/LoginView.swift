import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm = AuthViewModel()
    @State private var showCreate = false

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)
                    logoSection
                    Spacer(minLength: 48)
                    formCard
                    Spacer(minLength: 24)
                    createAccountButton
                    Spacer(minLength: 16)
                    guestButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, BSTheme.hPad)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateAccountView()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Logo

    private var logoSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 56, weight: .black))
                .foregroundColor(BSTheme.electricCyan)
                .glowingAccent(BSTheme.electricCyan, radius: 28)
            Text("BallStrike")
                .font(.system(size: 36, weight: .black))
                .foregroundColor(.white)
            Text("Golf launch monitor · Performance tracking")
                .font(.system(size: 14))
                .foregroundColor(BSTheme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Form

    private var formCard: some View {
        VStack(spacing: 16) {
            Text("Sign In")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            BSTextField(placeholder: "Email", text: $vm.email, icon: "envelope")
                .keyboardType(.emailAddress)
                .autocapitalization(.none)

            BSTextField(placeholder: "Password", text: $vm.password, icon: "lock", isSecure: true)

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.dangerRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PremiumActionButton(
                title: vm.isLoading ? "Signing in…" : "Sign In",
                icon: "arrow.right.circle.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: {
                    Task { await vm.signIn(store: session) }
                }
            )
            .disabled(vm.isLoading)
        }
        .premiumCard()
    }

    // MARK: Create / Guest

    private var createAccountButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 6) {
                Text("Don't have an account?")
                    .foregroundColor(BSTheme.textMuted)
                Text("Create one")
                    .foregroundColor(BSTheme.electricCyan)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
    }

    private var guestButton: some View {
        Button {
            Task { await vm.continueAsGuest(store: session) }
        } label: {
            Text("Continue as Guest")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BSTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(BSTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Account View

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Text("Create Account")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 14) {
                            BSTextField(placeholder: "Full Name", text: $vm.name, icon: "person")
                            BSTextField(placeholder: "Email", text: $vm.email, icon: "envelope")
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                            BSTextField(placeholder: "Password (6+ chars)", text: $vm.password, icon: "lock", isSecure: true)
                        }

                        if let err = vm.errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(BSTheme.dangerRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        PremiumActionButton(
                            title: vm.isLoading ? "Creating…" : "Create Account",
                            icon: "person.badge.plus",
                            style: .gradient(BSTheme.rangeGradient),
                            action: { Task { await vm.createAccount(store: session) } }
                        )
                        .disabled(vm.isLoading)

                        Text("Your data is stored locally on this device. No account info is sent to a server.")
                            .font(.system(size: 11))
                            .foregroundColor(BSTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(BSTheme.textMuted)
                }
            }
            .onChange(of: session.isLoggedIn) { loggedIn in
                if loggedIn { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reusable text field

struct BSTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String = ""
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 20)
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 15))
            .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
    }
}
