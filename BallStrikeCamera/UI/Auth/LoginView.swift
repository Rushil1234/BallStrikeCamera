import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm = AuthViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When true, the page plays its staggered entrance. Driven by the launch
    /// handoff on cold start, so the animation isn't wasted behind the splash.
    var startEntrance: Bool = true
    @State private var showCreate = false
    @State private var hasAppeared = false
    @State private var currentNonce: String?   // raw nonce for Sign in with Apple

    var body: some View {
        ZStack {
            TrueCarryBackground()
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 88)
                    brandCrest
                        .modifier(AppearMod(active: hasAppeared, delay: 0, rise: 0, scaleFrom: 0.98, reduceMotion: reduceMotion))
                    Spacer(minLength: 14)
                    brandWordmark
                        .modifier(AppearMod(active: hasAppeared, delay: 0.12, rise: 14, reduceMotion: reduceMotion))
                    Spacer(minLength: 34)
                    formCard
                        .modifier(AppearMod(active: hasAppeared, delay: 0.22, rise: 18, reduceMotion: reduceMotion))
                    Spacer(minLength: 18)
                    createAccountButton
                        .modifier(AppearMod(active: hasAppeared, delay: 0.32, rise: 14, reduceMotion: reduceMotion))
                    Spacer(minLength: 48)
                }
                .padding(.horizontal, TCTheme.hPad)
            }
        }
        .onAppear {
            if startEntrance { hasAppeared = true }
        }
        .onChange(of: startEntrance) { now in
            if now { hasAppeared = true }
        }
        .sheet(isPresented: $showCreate) {
            CreateAccountView()
                .environmentObject(session)
        }
        .tcAppearance()
    }

    // MARK: Logo

    private var brandCrest: some View {
        TCFramedCrest(size: 196)
            .frame(maxWidth: .infinity)
    }

    private var brandWordmark: some View {
        // Canonical two-tone lockup — "Carry" in italic Marker Gold — matching the
        // launch screen, in-app header, and website.
        (Text("True ").foregroundColor(TCTheme.cream)
            + Text("Carry").italic().foregroundColor(TCTheme.gold))
            .font(.system(size: 30, weight: .medium, design: .serif))
            .tracking(-0.25)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
    }

    // MARK: Form

    private var formCard: some View {
        VStack(spacing: 18) {
            Text("Welcome back")
                .font(.system(size: 19, weight: .medium, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            appleSignInButton
            googleSignInButton
            orDivider

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

    // MARK: Apple sign-in (native)

    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = LoginView.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = LoginView.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard
                    let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = cred.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8),
                    let nonce = currentNonce
                else {
                    vm.errorMessage = "Apple sign-in returned no identity token."
                    return
                }
                Task {
                    vm.errorMessage = nil
                    do { try await session.signInWithApple(idToken: idToken, nonce: nonce) }
                    catch { vm.errorMessage = error.localizedDescription }
                }
            case .failure(let error):
                // User-cancelled is not an error worth surfacing.
                if (error as? ASAuthorizationError)?.code != .canceled {
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .disabled(vm.isLoading)
        .opacity(vm.isLoading ? 0.6 : 1)
    }

    // Nonce plumbing for Apple's replay protection: send SHA-256(nonce) in the
    // request, hand the RAW nonce to Supabase to verify against the token.
    private static func randomNonce(_ length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < chars.count { result.append(chars[Int(random)]); remaining -= 1 }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Google sign-in

    private var googleSignInButton: some View {
        Button {
            Task {
                vm.errorMessage = nil
                do {
                    try await session.signInWithGoogle()
                } catch {
                    vm.errorMessage = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text("G")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: 22, height: 22)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                Text("Continue with Google")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(TCTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isLoading)
        .opacity(vm.isLoading ? 0.6 : 1)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(TCTheme.borderMedium).frame(height: 1)
            Text("OR")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(TCTheme.textMuted)
            Rectangle().fill(TCTheme.borderMedium).frame(height: 1)
        }
        .frame(maxWidth: .infinity)
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


}

// MARK: - Staggered entrance modifier

/// Fades + rises (and optionally scales) a view into place once `active` flips
/// true, with a per-element `delay` to stagger the page in. Honors Reduce Motion.
private struct AppearMod: ViewModifier {
    let active: Bool
    var delay: Double = 0
    var rise: CGFloat = 16
    var scaleFrom: CGFloat = 1
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : rise)
            .scaleEffect(active ? 1 : scaleFrom, anchor: .center)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(delay), value: active)
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
