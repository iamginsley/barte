import Foundation

/// GraphQL (Hasura) and Nhost Functions, signed in as the current person.
/// Reads are plain queries, filtered by the Hasura permissions; writes call the SQL functions,
/// which Hasura exposes as mutations returning `api_results` rows.
struct NhostAPI: Sendable {
    let session: NhostSession
    var urlSession: URLSession = .shared

    // MARK: Queries and SQL functions

    /// Runs a query and decodes its `data`. Retries once with a fresh token if Hasura rejects it.
    func query<T: Decodable & Sendable>(_ query: String, variables: [String: JSON] = [:], as type: T.Type = T.self) async throws -> T {
        do {
            return try await run(query, variables: variables)
        } catch GraphQLError.tokenRejected {
            await session.invalidateAccessToken()
            return try await run(query, variables: variables)
        }
    }

    /// One row of `api_results`: what an SQL function hands back.
    struct Result: Decodable, Sendable {
        let id: UUID?
        let code: String?
        let preview: InvitePreview?
    }

    /// Calls one of the SQL functions in nhost/migrations, e.g. `call("add_member", ["p_group_id": .uuid(id)])`.
    @discardableResult
    func call(_ function: String, _ arguments: [String: JSON] = [:]) async throws -> Result? {
        let rows: [String: [Result]]
        if arguments.isEmpty {
            rows = try await query("mutation { \(function) { id code preview } }")
        } else {
            rows = try await query(
                "mutation Call($args: \(function)_args!) { \(function)(args: $args) { id code preview } }",
                variables: ["args": .object(arguments)]
            )
        }
        return rows[function]?.first
    }

    private func run<T: Decodable>(_ query: String, variables: [String: JSON]) async throws -> T {
        var request = URLRequest(url: Backend.url("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let (data, _) = try await urlSession.data(for: request)
        let response = try Self.decoder.decode(GraphQLResponse<T>.self, from: data)
        if let error = response.errors?.first {
            throw GraphQLError.mapped(error)
        }
        guard let value = response.data else { throw BarteError.server(hint: nil) }
        return value
    }

    // MARK: Functions

    /// POSTs JSON to an Nhost Function (functions/<name>.ts) with the access token.
    func invokeFunction(_ name: String, body: [String: JSON]) async throws {
        var request = URLRequest(url: Backend.url("functions", name))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPError(status: status) }
    }

    // MARK: Live updates

    /// Hasura live queries over graphql-transport-ws: yields whenever the result of any of the
    /// subscriptions changes (not for the first result). Reconnects with a fresh token after the
    /// server closes the socket, which it does when the access token expires.
    func changes(of subscriptions: [String]) -> AsyncStream<Void> {
        let api = self
        return AsyncStream { continuation in
            let task = Task {
                var delay = Duration.seconds(1)
                while !Task.isCancelled {
                    var connected = false
                    do {
                        connected = try await api.listen(to: subscriptions) { continuation.yield() }
                    } catch BarteError.notSignedIn {
                        break
                    } catch {
                        // Offline or closed: try again, a bit later each time.
                    }
                    delay = connected ? .seconds(1) : min(delay * 2, .seconds(30))
                    try? await Task.sleep(for: delay)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Returns true when the server accepted the connection before it ended.
    private func listen(to subscriptions: [String], onChange: @Sendable () -> Void) async throws -> Bool {
        var url = URLComponents(url: Backend.url("graphql"), resolvingAgainstBaseURL: false)!
        url.scheme = "wss"
        let socket = urlSession.webSocketTask(with: url.url!, protocols: ["graphql-transport-ws"])
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let token = try await session.validAccessToken()
        try await socket.send(message(["type": "connection_init", "payload": ["headers": ["Authorization": .string("Bearer \(token)")]]]))
        var seenFirst = Set<String>()
        var connected = false

        while !Task.isCancelled {
            let received = try await socket.receive()
            guard case .string(let text) = received,
                  let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            switch type {
            case "connection_ack":
                connected = true
                for (index, query) in subscriptions.enumerated() {
                    try await socket.send(message(["id": .string("\(index)"), "type": "subscribe", "payload": ["query": .string(query)]]))
                }
                // Something may have changed while the socket was down.
                onChange()
            case "ping":
                try await socket.send(message(["type": "pong"]))
            case "next":
                let id = object["id"] as? String ?? ""
                if seenFirst.insert(id).inserted { continue }
                onChange()
            case "error", "complete":
                return connected
            default:
                continue
            }
        }
        return connected
    }

    private func message(_ value: [String: JSON]) throws -> URLSessionWebSocketTask.Message {
        .string(String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
    }

    // MARK: Decoding

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Timestamp.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown date \(text)"))
            }
            return date
        }
        return decoder
    }()
}

// MARK: - Wire types

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: JSON]
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    struct Message: Decodable {
        struct Extensions: Decodable { let code: String? }
        let message: String
        let extensions: Extensions?
    }

    let data: T?
    let errors: [Message]?
}

/// Hasura rejected the access token; the only GraphQL error worth a retry.
enum GraphQLError: Error {
    case tokenRejected

    /// Data exceptions from the SQL functions carry the hint as their message.
    fileprivate static func mapped<T>(_ message: GraphQLResponse<T>.Message) -> Error {
        let code = message.extensions?.code ?? ""
        if code == "invalid-jwt" || message.message.localizedCaseInsensitiveContains("JWTExpired") {
            return GraphQLError.tokenRejected
        }
        return BarteError.server(hint: message.message)
    }
}

/// A JSON value for GraphQL variables.
enum JSON: Encodable, Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
    case array([JSON])
    case object([String: JSON])

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(nilLiteral: ()) { self = .null }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSON)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }

    static func uuid(_ id: UUID?) -> JSON { id.map { .string($0.uuidString.lowercased()) } ?? .null }
    static func optional(_ text: String?) -> JSON { text.map(JSON.string) ?? .null }

    /// Postgres array literal for array arguments (`uuid[]`, `text[]`, `bigint[]`), which Hasura takes as text.
    static func pgArray(_ values: [String]) -> JSON {
        let quoted = values.map { "\"" + $0.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\"" }
        return .string("{" + quoted.joined(separator: ",") + "}")
    }

    static func pgArray(_ ids: [UUID]) -> JSON { pgArray(ids.map { $0.uuidString.lowercased() }) }
    static func pgArray(_ numbers: [Int]?) -> JSON { numbers.map { .string("{" + $0.map(String.init).joined(separator: ",") + "}") } ?? .null }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Postgres arrays as Hasura returns them: JSON arrays, or the text literal `{a,b}` on older setups.
struct PGArray<Element: Decodable & Sendable & LosslessStringConvertible>: Decodable, Sendable {
    let values: [Element]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let values = try? container.decode([Element].self) {
            self.values = values
            return
        }
        let text = try container.decode(String.self)
        let inner = text.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        values = inner.isEmpty ? [] : try inner.split(separator: ",").map { part in
            guard let value = Element(String(part).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad array element \(part)"))
            }
            return value
        }
    }
}

extension UUID: @retroactive LosslessStringConvertible {
    public init?(_ description: String) { self.init(uuidString: description) }
}

/// Postgres `timestamptz` as Hasura sends it: `2026-11-07T16:31:06.123456+00:00`.
enum Timestamp {
    static func date(from text: String) -> Date? {
        // Foundation parses at most milliseconds, so trim longer fractions.
        let trimmed = text.replacing(/(\.\d{3})\d+/) { $0.output.1 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
