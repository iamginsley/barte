import Foundation

/// barte://group/<id> opens a group; used by notifications and the widget.
enum BarteLink {
    static let home = URL(string: "barte://home")!

    static func group(_ id: UUID) -> URL {
        URL(string: "barte://group/\(id.uuidString.lowercased())")!
    }

    static func groupID(from url: URL) -> UUID? {
        guard url.scheme == "barte", url.host() == "group" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
