import Foundation
import SwiftUI

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var userProfile: UserProfile?
    @Published var isLoading = true

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

    // MARK: - Session Restore

    func restoreSession() async {
        isLoading = true
        if let user = try? await configuredBackend.currentUser() {
            activateBackend(configuredBackend)
            currentUser = user
            userProfile = await ensureProfileAndBag(for: user)
            await entitlementVM.load(userId: user.id)
        } else if let user = try? await localGuestBackend.currentUser() {
            activateBackend(localGuestBackend)
            currentUser = user
            userProfile = await ensureProfileAndBag(for: user)
            await entitlementVM.load(userId: user.id)
        }
        isLoading = false
    }

    // MARK: - Auth Actions

    func signIn(email: String, password: String) async throws {
        activateBackend(configuredBackend)
        let user = try await configuredBackend.signIn(email: email, password: password)
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
    }

    func createAccount(name: String, email: String, password: String) async throws {
        activateBackend(configuredBackend)
        let user = try await configuredBackend.createAccount(name: name, email: email, password: password)
        currentUser = user
        userProfile = await ensureProfileAndBag(for: user)
        await entitlementVM.load(userId: user.id)
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
    }

    func signOut() async {
        try? await configuredBackend.signOut()
        try? await localGuestBackend.signOut()
        activateBackend(configuredBackend)
        currentUser = nil
        userProfile = nil
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
        entitlementVM = EntitlementViewModel(backend: nextBackend)
    }
}
