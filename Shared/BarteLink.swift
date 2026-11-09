import Foundation

/// barte://group/<id> opens a group, barte://group/<id>/chat its chat; used by notifications and the widget.
enum BarteLink {
    static let home = URL(string: "barte://home")!

    static func group(_ id: UUID) -> URL {
        URL(string: "barte://group/\(id.uuidString.lowercased())")!
    }

    static func chat(_ id: UUID) -> URL {
        group(id).appending(path: "chat")
    }

    static func groupID(from url: URL) -> UUID? {
        guard url.scheme == "barte", url.host() == "group" else { return nil }
        return url.pathComponents.lazy.compactMap(UUID.init(uuidString:)).first
    }

    /// The link goes to the group's chat.
    static func opensChat(_ url: URL) -> Bool {
        groupID(from: url) != nil && url.lastPathComponent == "chat"
    }
}
