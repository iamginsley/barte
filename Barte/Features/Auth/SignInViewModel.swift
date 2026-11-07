import AuthenticationServices
import CryptoKit
import Foundation
import FirebaseAuth
import Observation

/// Sign in with Apple, exchanged for a Firebase session via the ID token.
@MainActor
@Observable
final class SignInViewModel {
    private(set) var isWorking = false
    var errorMessage: String?

    private var currentNonce: String?

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
            guard Backend.isConfigured,
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
                let firebaseCredential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: credential.fullName)
                try await Auth.auth().signIn(with: firebaseCredential)
                // Apple shares the name only on the very first sign-in; keep it to prefill new groups and joining.
                if let givenName = credential.fullName?.givenName, !givenName.isEmpty, Preferences.myName.isEmpty {
                    Preferences.myName = givenName
                }
                errorMessage = nil
            } catch {
                errorMessage = BarteError.from(error) == .offline
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
