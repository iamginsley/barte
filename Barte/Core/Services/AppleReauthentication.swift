import AuthenticationServices
import UIKit

/// Asks Apple once more for a fresh authorization code. Used right before account deletion,
/// so the server can revoke the Sign in with Apple link without ever storing Apple tokens.
@MainActor
final class AppleReauthentication: NSObject {
    enum Failure: LocalizedError {
        case canceled
        case noCode

        var errorDescription: String? {
            switch self {
            case .canceled: nil
            case .noCode: String(localized: "Apple hat die Bestätigung nicht geliefert. Versuch es noch einmal.")
            }
        }
    }

    private var continuation: CheckedContinuation<String, Error>?
    private var controller: ASAuthorizationController?

    func authorizationCode() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

extension AppleReauthentication: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            finish(code.map { .success($0) } ?? .failure(Failure.noCode))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        MainActor.assumeIsolated {
            finish(.failure(canceled ? Failure.canceled : error))
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            // Sign in with Apple only runs from a visible screen, so there is always a scene.
            return ASPresentationAnchor(windowScene: scenes.first!)
        }
    }
}
