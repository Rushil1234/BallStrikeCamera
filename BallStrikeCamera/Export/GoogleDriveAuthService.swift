import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Signs in to a Google account with the narrow `drive.file` scope and keeps the access token
/// fresh, entirely with Apple's own `ASWebAuthenticationSession` (Authorization Code + PKCE) —
/// no Google SDK dependency, matching how the rest of the app talks to external services directly
/// over REST rather than pulling in vendor SDKs.
@MainActor
final class GoogleDriveAuthService: NSObject, ObservableObject {
    static let shared = GoogleDriveAuthService()

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var accountEmail: String?

    private static let refreshTokenKey = "google_drive_refresh_token"
    private static let accessTokenKey  = "google_drive_access_token"
    private static let expiryKey       = "google_drive_access_token_expiry"
    private static let emailKey        = "google_drive_account_email"

    private var webAuthSession: ASWebAuthenticationSession?

    override private init() {
        isSignedIn = KeychainTokenStore.get(Self.refreshTokenKey) != nil
        accountEmail = KeychainTokenStore.get(Self.emailKey)
        super.init()
    }

    // MARK: - Sign in / out

    func signIn() async throws {
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 16)

        var components = URLComponents(string: GoogleDriveConfig.authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleDriveConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: GoogleDriveConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveConfig.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            // Forces Google to reissue a refresh_token even for a returning user — without this,
            // signing in again after `signOut()` would silently omit refresh_token.
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let redirectScheme = GoogleDriveConfig.redirectURI.split(separator: ":").first else {
            throw GoogleDriveError.configuration
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: String(redirectScheme)
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? GoogleDriveError.signInCancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleDriveError.signInCancelled
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier)
        try? await fetchAndStoreAccountEmail()
    }

    func signOut() {
        KeychainTokenStore.delete(Self.refreshTokenKey)
        KeychainTokenStore.delete(Self.accessTokenKey)
        KeychainTokenStore.delete(Self.expiryKey)
        KeychainTokenStore.delete(Self.emailKey)
        isSignedIn = false
        accountEmail = nil
    }

    // MARK: - Access token

    /// Returns a currently-valid access token, transparently refreshing if it's expired or about
    /// to expire. Throws if the user has never signed in.
    func validAccessToken() async throws -> String {
        if let token = KeychainTokenStore.get(Self.accessTokenKey),
           let expiryString = KeychainTokenStore.get(Self.expiryKey),
           let expiry = Double(expiryString),
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = KeychainTokenStore.get(Self.refreshTokenKey) else {
            throw GoogleDriveError.notSignedIn
        }
        var request = URLRequest(url: URL(string: GoogleDriveConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": GoogleDriveConfig.clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = Self.formEncode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // A refresh_token can be revoked externally (user removed access in their Google
            // account) — treat that as signed-out rather than surfacing a raw HTTP error forever.
            signOut()
            throw GoogleDriveError.tokenRefreshFailed
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeAccessToken(decoded)
        return decoded.accessToken
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        var request = URLRequest(url: URL(string: GoogleDriveConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": GoogleDriveConfig.clientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleDriveConfig.redirectURI
        ]
        request.httpBody = Self.formEncode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleDriveError.signInFailed
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeAccessToken(decoded)
        if let refreshToken = decoded.refreshToken {
            KeychainTokenStore.set(refreshToken, for: Self.refreshTokenKey)
        }
        isSignedIn = true
    }

    private func fetchAndStoreAccountEmail() async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct UserInfo: Decodable { let email: String? }
        if let info = try? JSONDecoder().decode(UserInfo.self, from: data), let email = info.email {
            KeychainTokenStore.set(email, for: Self.emailKey)
            accountEmail = email
        }
    }

    private func storeAccessToken(_ response: TokenResponse) {
        KeychainTokenStore.set(response.accessToken, for: Self.accessTokenKey)
        let expiry = Date().timeIntervalSince1970 + Double(response.expiresIn)
        KeychainTokenStore.set(String(expiry), for: Self.expiryKey)
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        params.map { key, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(encodedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }
}

enum GoogleDriveError: Error {
    case configuration
    case signInCancelled
    case signInFailed
    case notSignedIn
    case tokenRefreshFailed
    case uploadFailed(String)
}

extension GoogleDriveAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension CharacterSet {
    /// `application/x-www-form-urlencoded` needs `+`/`&`/`=` etc. escaped beyond the default
    /// query-item allowed set.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
