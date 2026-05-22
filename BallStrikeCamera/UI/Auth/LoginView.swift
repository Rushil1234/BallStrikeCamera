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
                    Spacer(minLength: 88)
                    logoSection
                    Spacer(minLength: 40)
                    formCard
                    Spacer(minLength: 18)
                    createAccountButton
                    Spacer(minLength: 12)
                    guestButton
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
        VStack(spacing: 24) {
            TCFramedCrest(size: 196)

            VStack(spacing: 10) {
                TrueCarryLogo(size: 30)
                Text("PRECISION GOLF ANALYTICS")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(3.4)
                    .foregroundColor(TCTheme.gold)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Form

    private var formCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Welcome back")
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)
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

            Button {
                Task { await vm.sendPasswordReset(store: session) }
            } label: {
                Text("Forgot password?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)

            if let msg = vm.successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(TCTheme.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TCTheme.gold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

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

                        if let msg = vm.successMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope.badge.shield.half.filled")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(msg)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                Button {
                                    Task { await vm.resendConfirmation(store: session) }
                                } label: {
                                    Text(vm.isLoading ? "Sending…" : "Resend confirmation email")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(TCTheme.gold)
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.isLoading)
                            }
                            .foregroundColor(TCTheme.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(TCTheme.gold.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

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

// MARK: - Framed brand crest (luxury logo frame — brand guideline 'logo-frame')

/// The True Carry logo presented in a sharp gold-hairline frame with an inner
/// inset rule and four corner accents, echoing the brand site's hero treatment.
struct TCFramedCrest: View {
    var size: CGFloat = 196

    var body: some View {
        Image("tc_logo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipped()
            // Inner inset hairline
            .overlay(
                Rectangle()
                    .strokeBorder(TCTheme.gold.opacity(0.20), lineWidth: 0.5)
                    .padding(12)
            )
            // Outer hairline frame
            .overlay(
                Rectangle()
                    .strokeBorder(TCTheme.gold.opacity(0.45), lineWidth: 0.5)
            )
            // Gold corner accents
            .overlay(
                CrestCornerAccents(length: 18)
                    .stroke(TCTheme.gold, lineWidth: 1)
                    .opacity(0.75)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 16)
    }
}

/// Four L-shaped marks, one per corner.
struct CrestCornerAccents: Shape {
    var length: CGFloat = 18
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        return p
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
            .foregroundColor(TCTheme.textPrimary)
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
