import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm = AuthViewModel()
    @State private var showCreate = false
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            TrueCarryBackground()
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 46)
                    logoSection
                    Spacer(minLength: 34)
                    formCard
                    Spacer(minLength: 18)
                    createAccountButton
                    Spacer(minLength: 12)
                    guestButton
                    Spacer(minLength: 22)
                    authBenefits
                    Spacer(minLength: 48)
                }
                .padding(.horizontal, TCTheme.hPad)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 18)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                hasAppeared = true
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateAccountView()
                .environmentObject(session)
        }
        .tcAppearance()
    }

    // MARK: Logo

    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    TrueCarryLogo(size: 25)
                    Text("THE CAMERA LAUNCH MONITOR")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(3.0)
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Text("SIGN IN")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TCTheme.textUltraMuted)
                    .tracking(2.0)
            }

            VStack(alignment: .leading, spacing: 12) {
                (Text("Know every\n")
                    .foregroundColor(TCTheme.cream)
                 + Text("yard")
                    .italic()
                    .foregroundColor(TCTheme.goldLight)
                 + Text(" you carry.")
                    .foregroundColor(TCTheme.cream))
                    .font(.system(size: 48, weight: .regular, design: .serif))
                    .tracking(-1.2)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Sign in to sync your bag, sessions, rounds, and course-ready GPS maps.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TCTheme.textMuted)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Form

    private var formCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back")
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Sign in to sync your bag, sessions, and rounds.")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }

            TCAuthTextField(placeholder: "Email", text: $vm.email, icon: "envelope")
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)

            TCAuthTextField(placeholder: "Password", text: $vm.password, icon: "lock", isSecure: true)

            if let err = vm.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(TCTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TCTheme.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            TCPrimaryGoldButton(
                title: vm.isLoading ? "Signing in…" : "Sign In",
                icon: "arrow.right.circle.fill"
            ) {
                Task { await vm.signIn(store: session) }
            }
            .disabled(vm.isLoading)
            .opacity(vm.isLoading ? 0.6 : 1)
        }
        .tcGlassCard(padding: 18)
    }

    // MARK: Create / Guest

    private var createAccountButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 6) {
                Text("Don't have an account?")
                    .foregroundColor(TCTheme.textMuted)
                Text("Create one")
                    .foregroundColor(TCTheme.gold)
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
            Text("Continue as guest")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TCTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TCTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                        .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var authBenefits: some View {
        HStack(spacing: 10) {
            authBenefit("Verified GPS", "checkmark.seal.fill")
            authBenefit("Bag Sync", "figure.golf")
            authBenefit("Insights", "chart.line.uptrend.xyaxis")
        }
    }

    private func authBenefit(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TCTheme.gold)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(TCTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
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
                TrueCarryBackground()
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Create Account")
                                .font(.system(size: 34, weight: .regular, design: .serif))
                                .foregroundColor(TCTheme.textPrimary)
                            Text("Build your True Carry profile and keep your bag, shots, and rounds in sync.")
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.textMuted)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 14) {
                            TCAuthTextField(placeholder: "Full Name", text: $vm.name, icon: "person")
                            TCAuthTextField(placeholder: "Email", text: $vm.email, icon: "envelope")
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .textInputAutocapitalization(.never)
                            TCAuthTextField(placeholder: "Password (6+ chars)", text: $vm.password, icon: "lock", isSecure: true)
                        }
                        .tcGlassCard(padding: 14)

                        if let err = vm.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(err)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(TCTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(TCTheme.danger.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        TCPrimaryGoldButton(
                            title: vm.isLoading ? "Creating…" : "Create Account",
                            icon: "person.badge.plus"
                        ) {
                            Task { await vm.createAccount(store: session) }
                        }
                        .disabled(vm.isLoading)
                        .opacity(vm.isLoading ? 0.6 : 1)

                        Text("Signed-in accounts sync through True Carry. Guest sessions stay local on this device.")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            .onChange(of: session.isLoggedIn) { loggedIn in
                if loggedIn { dismiss() }
            }
        }
        .tcAppearance()
    }
}

// MARK: - Reusable auth text field (TCTheme)

struct TCAuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String = ""
    var isSecure: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isFocused ? TCTheme.gold : TCTheme.textMuted)
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
            .tint(TCTheme.gold)
            .focused($isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(isFocused ? TCTheme.panelRaised : TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isFocused ? TCTheme.borderGold : TCTheme.border, lineWidth: 1)
        )
    }
}
