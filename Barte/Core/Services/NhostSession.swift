import Foundation
import Security

/// Sign-in state against Nhost Auth: Sign in with Apple's ID token in, a short-lived access token
/// (for GraphQL and functions) and a rotating refresh token out. Only the refresh token and the
/// user id are stored, in the Keychain; access tokens live in memory.
actor NhostSession {
    enum Event: Sendable, Equatable {
        case signedIn(UUID)
        case signedOut
    }

    private struct Stored: Codable {
        var refreshToken: String
        var userID: UUID
    }

    private struct Session: Decodable {
        struct User: Decodable { let id: UUID }
        let accessToken: String
        let accessTokenExpiresIn: Double
        let refreshToken: String
        let user: User?
    }

    private var stored: Stored?
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var refreshTask: Task<String, Error>?

    /// The app model is the only listener.
    nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        self.urlSession = urlSession
    }

    var userID: UUID? { stored?.userID }

    /// On launch: a stored refresh token counts as signed in, also offline. It is checked on first use.
    func restore() {
        stored = Keychain.load()
        continuation.yield(stored.map { .signedIn($0.userID) } ?? .signedOut)
    }

    /// `nonce` is the raw value whose SHA-256 went to Apple; Nhost Auth hashes and compares it.
    func signIn(appleIDToken idToken: String, nonce: String) async throws {
        struct Body: Encodable { let provider = "apple"; let idToken: String; let nonce: String }
        struct Payload: Decodable { let session: Session? }
        let payload: Payload = try await post("signin/idtoken", Body(idToken: idToken, nonce: nonce))
        guard let session = payload.session, let user = session.user else { throw BarteError.server(hint: nil) }
        apply(session, userID: user.id)
        continuation.yield(.signedIn(user.id))
    }

    /// A valid access token, refreshed when it is about to expire. Several callers share one refresh.
    func validAccessToken() async throws -> String {
        if let accessToken, expiresAt.timeIntervalSinceNow > 30 { return accessToken }
        return try await refresh()
    }

    /// After the server rejected a token that looked valid here (clock skew, revoked key).
    func invalidateAccessToken() {
        accessToken = nil
    }

    private func refresh() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let stored else { throw BarteError.notSignedIn }
        let task = Task<String, Error> {
            struct Body: Encodable { let refreshToken: String }
            do {
                let session: Session = try await post("token", Body(refreshToken: stored.refreshToken))
                apply(session, userID: session.user?.id ?? stored.userID)
                return session.accessToken
            } catch let error as HTTPError where error.isUnauthorized {
                // The refresh token expired or the account is gone: back to the sign-in screen.
                signOutLocally()
                throw BarteError.notSignedIn
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Ends the session on the server too, so the refresh token can't be used again.
    func signOut() async {
        if let stored, let token = try? await validAccessToken() {
            struct Body: Encodable { let refreshToken: String }
            var request = URLRequest(url: Backend.url("auth", "signout"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await send(request, body: Body(refreshToken: stored.refreshToken)) as EmptyResponse
        }
        signOutLocally()
    }

    func signOutLocally() {
        stored = nil
        accessToken = nil
        expiresAt = .distantPast
        Keychain.delete()
        continuation.yield(.signedOut)
    }

    // MARK: Helpers

    private func apply(_ session: Session, userID: UUID) {
        let value = Stored(refreshToken: session.refreshToken, userID: userID)
        stored = value
        Keychain.save(value)
        accessToken = session.accessToken
        expiresAt = Date.now.addingTimeInterval(session.accessTokenExpiresIn)
    }

    private struct EmptyResponse: Decodable {}

    private func post<Body: Encodable, Response: Decodable>(_ path: String, _ body: Body) async throws -> Response {
        try await send(URLRequest(url: Backend.url("auth", path)), body: body)
    }

    private func send<Body: Encodable, Response: Decodable>(_ request: URLRequest, body: Body) async throws -> Response {
        var request = request
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPError(status: status) }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: Keychain

    private enum Keychain {
        private static var query: [String: Any] {
            [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.iamginsley.barte.session",
            kSecAttrAccount as String: "nhost",
            ]
        }

        static func load() -> Stored? {
            var query = query
            query[kSecReturnData as String] = true
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return try? JSONDecoder().decode(Stored.self, from: data)
        }

        static func save(_ value: Stored) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                // Push and widgets may wake the app while the phone is locked.
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
                SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            }
        }

        static func delete() {
            SecItemDelete(query as CFDictionary)
        }
    }
}

struct HTTPError: Error {
    let status: Int
    var isUnauthorized: Bool { status == 400 || status == 401 || status == 403 }
}
