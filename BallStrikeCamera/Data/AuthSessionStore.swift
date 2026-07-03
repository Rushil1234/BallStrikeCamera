import Foundation
import SwiftUI
import AuthenticationServices
import UIKit

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published var currentUser: AppUser? {
        // Bind the RFID hub to this user so it only auto-connects to their paired device.
        didSet { RFIDHubManager.shared.currentUserId = currentUser?.id }
    }
    @Published var userProfile: UserProfile?
    @Published var isLoading = true

    /// Prewarmed caches so screens render data instantly instead of flashing 0s until a refresh.
    /// Populated right after auth and refreshable on demand.
    @Published var cachedShots: [SavedShot] = []
    @Published var cachedClubs: [UserClub] = []
    @Published var cachedFeedPosts: [FeedPost] = []
    @Published var cachedHomeSummary: FeedHomeSummary?
    @Published private(set) var dataPreloaded = false

    /// The name to show for the current user everywhere. Prefers the chosen username, then a
    /// real (non-email) display name, then the email's local part — never the raw email.
    var displayHandle: String {
        if let u = userProfile?.username, !u.isEmpty { return u }
        let dn = userProfile?.displayName ?? currentUser?.name ?? ""
        if !dn.isEmpty, !dn.contains("@") { return dn }
        let email = currentUser?.email ?? dn
        if email.contains("@") { return String(email.split(separator: "@").first ?? "Golfer") }
        return dn.isEmpty ? "Golfer" : dn
    }

    @Published private(set) var backend: AppBackend
    @Published var entitlementVM: EntitlementViewModel
    private let configuredBackend: AppBackend
    private let localGuestBackend = LocalBackendService()

    /// Stable device identifier stored in UserDefaults.
    /// Used for device registration / validation with Supabase.
    static var deviceId: String {
        let key = "tc_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    /// Pricing URL from AppConfig (reads Secrets.plist).
    static var pricingURL: URL { AppConfig.pricingURL }

    init() {
        let b = BackendFactory.make()
        self.configuredBackend = b
        self.backend = b
        self._entitlementVM = Published(initialValue: EntitlementViewModel(backend: b))
        print("[TrueCarry] DeviceID: \(AuthSessionStore.deviceId)")
        Task { await restoreSession() }
    }

    var isLoggedIn: Bool { currentUser != nil }
    var userId: UUID? { currentUser?.id }

    /// Loads shots + clubs into the in-memory cache so dependent screens have data on first paint.
    func preloadData() async {
        guard let uid = currentUser?.id else { return }
        async let s = try? await backend.loadShots(userId: uid)
        async let c = try? await backend.loadClubs(userId: uid)
        async let f = try? await backend.loadFeedPage(userId: uid, cursor: nil, limit: 20)
        async let hs = try? await backend.loadHomeSummary(userId: uid)
        cachedShots = await s ?? []
        cachedClubs = await c ?? []
        cachedFeedPosts = (await f)?.posts ?? []
        cachedHomeSummary = await hs
        dataPreloaded = true
    }

    /// Refresh the cache after new data is written (e.g. session ends).
    func refreshCache() async { await preloadData() }

    // MARK: - Session Restore

    func restoreSession() async {
        isLoading = true
        if let user = try? await configuredBackend.currentUser() {
            activateBackend(configuredBackend)
            currentUser = user
            await registerThisDevice()   // refresh last-seen; non-blocking on restore
            userProfile = await ensureProfileAndBag(for: user)
            await entitlementVM.load(userId: user.id)
        await preloadData()
        } else if let user = try? await localGuestBackend.currentUser() {
            activateBackend(localGuestBackend)
            currentUser = user
            userProfile = await ensureProfileAndBag(for: user)
            await entitlementVM.load(userId: user.id)
        await preloadData()
        }
        isLoading = false
    }

    // MARK: - Auth Actions

    func signIn(email: String, password: String) async throws {
        activateBackend(configuredBackend)
        let user = try await configuredBackend.signIn(email: email, password: password)
        try await enforceDeviceLimit()           // signs out + throws if over the 2-device cap
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
        await preloadData()
    }

    func createAccount(name: String, email: String, password: String) async throws {
        activateBackend(configuredBackend)
        let user = try await configuredBackend.createAccount(name: name, email: email, password: password)
        try await enforceDeviceLimit()           // new account counts as this device
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
        await preloadData()
    }

    // MARK: - Device registration / 2-device cap

    /// Registers/refreshes this device with the hosted backend. No-op for the
    /// guest/local backend. Returns whether the device is allowed (under the cap).
    @discardableResult
    private func registerThisDevice() async -> Bool {
        guard let supabase = configuredBackend as? SupabaseBackendService else { return true }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return await supabase.registerDevice(
            token: AuthSessionStore.deviceId,
            name: UIDevice.current.name,
            platform: "iOS",
            appVersion: version
        )
    }

    /// On an explicit sign-in/create, block (and sign back out) if the account is
    /// already active on its maximum number of devices.
    private func enforceDeviceLimit() async throws {
        if await registerThisDevice() == false {
            await signOut()
            throw BackendError.deviceLimitReached
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await configuredBackend.sendPasswordReset(email: email)
    }

    func resendConfirmationEmail(email: String) async throws {
        try await configuredBackend.resendConfirmationEmail(email: email)
    }

    func refreshSessionAndEntitlement() async {
        guard let user = currentUser else { return }
        try? await configuredBackend.refreshSession()
        activateBackend(configuredBackend)
        currentUser = (try? await configuredBackend.currentUser()) ?? user
        await entitlementVM.refresh(userId: currentUser?.id ?? user.id)
    }

    func continueAsGuest() async throws {
        let user: AppUser
        do {
            activateBackend(configuredBackend)
            user = try await configuredBackend.continueAsGuest()
        } catch {
            #if DEBUG
            print("[TrueCarry] Supabase guest unavailable (\(error.localizedDescription)) — using local guest")
            #endif
            activateBackend(localGuestBackend)
            user = try await localGuestBackend.continueAsGuest()
        }
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
        await preloadData()
    }

    func signOut() async {
        try? await configuredBackend.signOut()
        try? await localGuestBackend.signOut()
        activateBackend(configuredBackend)
        currentUser = nil
        userProfile = nil
    }

    // MARK: - Google Sign-In

    /// Opens an ASWebAuthenticationSession against Supabase's `/auth/v1/authorize`
    /// endpoint for Google, parses the tokens out of the callback URL, and
    /// completes the session through the Supabase backend.
    func signInWithGoogle() async throws {
        guard let supabase = configuredBackend as? SupabaseBackendService else {
            // Guest/local backends can't do OAuth.
            throw BackendError.notAuthenticated
        }

        let redirectTo = "com.rushilkakkad.BallStrikeCamera://login-callback"
        guard let authorizeURL = supabase.oauthAuthorizeURL(provider: "google", redirectTo: redirectTo) else {
            throw BackendError.networkError("Could not build Google authorize URL.")
        }

        let (accessToken, refreshToken) = try await AuthBrowserSession.shared.run(
            authorizeURL: authorizeURL,
            callbackScheme: "com.rushilkakkad.BallStrikeCamera"
        )

        activateBackend(configuredBackend)
        let user = try await supabase.completeOAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken
        )
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
        await preloadData()
    }

    /// Completes native Sign in with Apple. `idToken` is the Apple identity token
    /// and `nonce` is the RAW nonce whose SHA-256 was sent in the Apple request.
    func signInWithApple(idToken: String, nonce: String) async throws {
        guard let supabase = configuredBackend as? SupabaseBackendService else {
            throw BackendError.notAuthenticated
        }
        activateBackend(configuredBackend)
        let user = try await supabase.signInWithApple(idToken: idToken, nonce: nonce)
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
        await preloadData()
    }

    // MARK: - Profile Updates

    func saveProfile(_ profile: UserProfile) async {
        guard let uid = userId else { return }
        var p = profile
        p.userId = uid
        try? await backend.saveUserProfile(p)
        userProfile = p
    }

    func updateHandedness(_ h: Handedness) async {
        guard var p = userProfile else { return }
        p.handedness = h
        await saveProfile(p)
    }

    /// True once the profile is loaded and the user hasn't finished the tutorial.
    var needsOnboarding: Bool {
        isLoggedIn && userProfile != nil && (userProfile?.onboardingCompleted != true)
    }

    /// Marks the first-run tutorial complete and persists it to Supabase.
    func completeOnboarding() async {
        guard var p = userProfile else { return }
        p.onboardingCompleted = true
        await saveProfile(p)
    }

    func updateHomeCourseName(_ name: String) async {
        guard var p = userProfile else { return }
        p.homeCourseName = name
        await saveProfile(p)
    }

    private func ensureProfileAndBag(for user: AppUser) async -> UserProfile {
        let profile: UserProfile
        if let existing = try? await backend.loadUserProfile(userId: user.id) {
            profile = existing
        } else {
            let created = UserProfile(userId: user.id, displayName: user.name)
            try? await backend.saveUserProfile(created)
            profile = created
        }

        let clubs = (try? await backend.loadClubs(userId: user.id)) ?? []
        if clubs.isEmpty {
            for club in UserClub.defaultBag(userId: user.id) {
                try? await backend.saveClub(club)
            }
        }

        return profile
    }

    private func activateBackend(_ nextBackend: AppBackend) {
        backend = nextBackend
        // Update the backend on the existing VM rather than replacing it.
        // Replacing creates a new instance that SwiftUI doesn't re-observe,
        // so entitlement updates after load() are silently dropped.
        entitlementVM.backend = nextBackend
    }
}

// MARK: - ASWebAuthenticationSession helper for OAuth web flows

@MainActor
private final class AuthBrowserSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthBrowserSession()

    /// Opens `authorizeURL` in a web auth session and resolves once the system
    /// redirects to a URL matching `callbackScheme`. Returns the access/refresh
    /// tokens from the callback URL's fragment (Supabase implicit flow).
    func run(authorizeURL: URL, callbackScheme: String) async throws
        -> (accessToken: String, refreshToken: String)
    {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, String), Error>) in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    cont.resume(throwing: NSError(
                        domain: "TrueCarry.OAuth", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No callback URL from Google sign-in."]
                    ))
                    return
                }

                let pairs = Self.parseTokenPairs(from: url)

                if let desc = pairs["error_description"] ?? pairs["error"] {
                    cont.resume(throwing: NSError(
                        domain: "TrueCarry.OAuth", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: desc]
                    ))
                    return
                }

                guard let at = pairs["access_token"], let rt = pairs["refresh_token"] else {
                    cont.resume(throwing: NSError(
                        domain: "TrueCarry.OAuth", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Google sign-in returned no tokens."]
                    ))
                    return
                }
                cont.resume(returning: (at, rt))
            }
            session.presentationContextProvider = self
            // Show the user's existing Google sign-in cookie rather than forcing
            // an ephemeral window — gives the native "choose your account" UX.
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                cont.resume(throwing: NSError(
                    domain: "TrueCarry.OAuth", code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Could not start Google sign-in."]
                ))
            }
        }
    }

    /// Supabase returns tokens in the URL fragment for the implicit flow and in
    /// query parameters for the PKCE flow — read both, with fragment winning.
    private static func parseTokenPairs(from url: URL) -> [String: String] {
        let raw = (url.fragment?.isEmpty == false ? url.fragment : url.query) ?? ""
        var dict: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            dict[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
        }
        return dict
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}
