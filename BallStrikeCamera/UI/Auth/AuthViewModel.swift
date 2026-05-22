import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var name     = ""
    @Published var email    = ""
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isLoading = false

    func signIn(store: AuthSessionStore) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."; return
        }
        isLoading = true; errorMessage = nil; successMessage = nil
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
        isLoading = true; errorMessage = nil; successMessage = nil
        do {
            try await store.createAccount(name: name, email: email, password: password)
            successMessage = "Account created."
        } catch BackendError.emailConfirmationRequired(let email) {
            successMessage = "Check \(email) to confirm your account, then come back and sign in."
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func sendPasswordReset(store: AuthSessionStore) async {
        guard !email.isEmpty else {
            errorMessage = "Enter your email first."; return
        }
        isLoading = true; errorMessage = nil; successMessage = nil
        do {
            try await store.sendPasswordReset(email: email)
            successMessage = "If an account exists for \(email), a reset link is on its way."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func resendConfirmation(store: AuthSessionStore) async {
        guard !email.isEmpty else {
            errorMessage = "Enter your email first."; return
        }
        isLoading = true; errorMessage = nil; successMessage = nil
        do {
            try await store.resendConfirmationEmail(email: email)
            successMessage = "Confirmation email sent to \(email)."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func continueAsGuest(store: AuthSessionStore) async {
        isLoading = true; errorMessage = nil; successMessage = nil
        do {
            try await store.continueAsGuest()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
