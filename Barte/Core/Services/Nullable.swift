import Foundation

/// Encodes nil as JSON null. Synthesized Encodable drops nil optionals, which turns
/// "clear this column" into "leave it unchanged" and drops required RPC arguments.
struct Nullable<Wrapped: Encodable & Sendable>: Encodable, Sendable {
    let value: Wrapped?

    init(_ value: Wrapped?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}
