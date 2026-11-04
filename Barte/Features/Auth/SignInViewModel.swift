import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

/// Sign in with Apple, exchanged for a Supabase session via the ID token.
@MainActor
@Observable
final class SignInViewModel {
    private(set) var isWorking = false
    var errorMessage: String?

    private let client: SupabaseClient?
    private var currentNonce: String?

    init(client: SupabaseClient?) {
        self.client = client
    }

    /// Called by SignInWithAppleButton before the Apple sheet opens.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return // Closing the sheet is a choice, not an error.
        case .failure:
            errorMessage = String(localized: "Die Anmeldung mit Apple hat nicht geklappt. Versuch es noch einmal.")
        case .success(let authorization):
            guard let client,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = String(localized: "Die Anmeldung mit Apple hat nicht geklappt. Versuch es noch einmal.")
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
                // Apple shares the name only on the very first sign-in; keep it to prefill new groups and joining.
                if let givenName = credential.fullName?.givenName, !givenName.isEmpty, Preferences.myName.isEmpty {
                    Preferences.myName = givenName
                }
                errorMessage = nil
            } catch {
                errorMessage = (error as? URLError) != nil
                    ? String(localized: "Keine Verbindung. Prüf dein Internet und versuch es noch einmal.")
                    : String(localized: "Die Anmeldung mit Apple hat nicht geklappt. Versuch es noch einmal.")
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
