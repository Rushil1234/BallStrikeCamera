import Foundation
import SwiftUI

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var userProfile: UserProfile?
    @Published var isLoading = true

    let backend: AppBackend = LocalBackendService()

    init() {
        Task { await restoreSession() }
    }

    var isLoggedIn: Bool { currentUser != nil }
    var userId: UUID? { currentUser?.id }

    // MARK: - Session Restore

    func restoreSession() async {
        isLoading = true
        if let user = try? await backend.currentUser() {
            currentUser = user
            userProfile = try? await backend.loadUserProfile(userId: user.id)
        }
        isLoading = false
    }

    // MARK: - Auth Actions

    func signIn(email: String, password: String) async throws {
        let user = try await backend.signIn(email: email, password: password)
        currentUser = user
        userProfile = try? await backend.loadUserProfile(userId: user.id)
    }

    func createAccount(name: String, email: String, password: String) async throws {
        let user = try await backend.createAccount(name: name, email: email, password: password)
        currentUser = user
        userProfile = try? await backend.loadUserProfile(userId: user.id)
    }

    func continueAsGuest() async throws {
        let user = try await backend.continueAsGuest()
        currentUser = user
        userProfile = try? await backend.loadUserProfile(userId: user.id)
    }

    func signOut() async {
        try? await backend.signOut()
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
}
