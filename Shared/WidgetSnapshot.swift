import Foundation

/// What the widget shows, written by the app into the shared App Group container.
/// The widget never talks to the server itself: it shows the state from the last time the app had fresh data.
struct WidgetSnapshot: Codable, Sendable, Hashable {
    /// My balance across all groups in one currency: positive means I get money.
    struct Total: Codable, Sendable, Hashable {
        var currency: String
        var cents: Int
    }

    struct Group: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var name: String
        /// CardColor raw value.
        var color: Int
        var currency: String
        var balance: Int
    }

    var updatedAt: Date
    /// Non-zero totals, largest first.
    var totals: [Total]
    /// Groups where I get or owe something, largest first; at most 4.
    var groups: [Group]
}

enum WidgetStore {
    static let appGroup = "group.com.iamginsley.barte"
    static let balanceKind = "BarteBalance"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot?) {
        guard let fileURL else { return }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Complete-until-first-unlock so the widget can still read it on the Lock Screen.
        try? encoder.encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
