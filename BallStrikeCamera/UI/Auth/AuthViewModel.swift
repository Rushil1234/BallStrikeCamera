import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var name     = ""
    @Published var email    = ""
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    func signIn(store: AuthSessionStore) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."; return
        }
        isLoading = true; errorMessage = nil
        do {
            try await store.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createAccount(store: AuthSessionStore) async {
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "Fill in all fields."; return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."; return
        }
        isLoading = true; errorMessage = nil
        do {
            try await store.createAccount(name: name, email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func continueAsGuest(store: AuthSessionStore) async {
        isLoading = true; errorMessage = nil
        do {
            try await store.continueAsGuest()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
