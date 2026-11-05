import Foundation

/// Invite links and codes. A link opens a small web page that hands the code to the app
/// (`barte://join/<code>`), so it works in every messenger, also for friends without the app yet.
enum InviteLink {
    static let webBase = URL(string: "https://iamginsley.github.io/barte/join/")!

    static func url(for code: String) -> URL {
        var components = URLComponents(url: webBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "c", value: code)]
        return components.url!
    }

    static func message(groupName: String, code: String) -> String {
        "Komm in meine Gruppe „\(groupName)“ bei Barte, dann tragen wir alle Ausgaben gemeinsam ein. Code: \(code)"
    }

    /// The code from `barte://join/ABCD2345`, the web link, or a code typed in by hand.
    static func code(from url: URL) -> String? {
        if url.scheme == "barte", url.host() == "join" {
            return normalize(url.lastPathComponent)
        }
        if url.host() == webBase.host(), url.path().hasPrefix(webBase.path()) {
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "c" }?.value
            return value.flatMap(normalize)
        }
        return nil
    }

    /// Upper-cases and strips spaces and dashes. Accepts a pasted link as well.
    static func normalize(_ text: String) -> String? {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil, let code = code(from: url) {
            return code
        }
        let code = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (6...12).contains(code.count), code.allSatisfy({ $0.isASCII }) else { return nil }
        return code
    }
}

/// What someone sees before joining with a code.
struct InvitePreview: Decodable, Sendable, Equatable {
    struct Person: Decodable, Sendable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let isClaimed: Bool

        enum CodingKeys: String, CodingKey {
            case id, name
            case isClaimed = "is_claimed"
        }
    }

    let groupID: UUID
    let name: String
    let currency: String
    let color: Int
    let isMember: Bool
    let members: [Person]

    enum CodingKeys: String, CodingKey {
        case name, currency, color, members
        case groupID = "group_id"
        case isMember = "is_member"
    }

    /// A card for the preview, without expenses.
    var card: SplitGroup {
        SplitGroup(
            id: groupID, name: name, currency: currency,
            color: CardColor(rawValue: color) ?? .blue, createdAt: .now,
            members: members.map { Member(id: $0.id, name: $0.name) }, expenses: []
        )
    }
}
