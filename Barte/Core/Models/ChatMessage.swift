import Foundation

/// One message in a group's chat (public.chat_messages). Messages can't be edited; deleting one
/// leaves a placeholder for everyone.
struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The author's member row in the group, for the name. Nil once that member was removed.
    let memberID: UUID?
    let authorID: UUID
    /// Nil once deleted.
    var body: String?
    /// The expense it is about, if any.
    var expenseID: UUID?
    let createdAt: Date
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    /// What `send_message` accepts: trimmed, 1–2000 characters.
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }

    static let maxLength = 2000
}

/// The chat as it is shown: messages and the group's history in one stream, by day.
/// History entries sit between the messages, so a question lands right below the change it is about.
enum ChatTimeline {
    enum Delivery: Hashable, Sendable { case sent, sending, failed }

    struct Bubble: Hashable, Sendable {
        let message: ChatMessage
        let isMine: Bool
        let delivery: Delivery
        /// First of a run from the same person: shows their name.
        let startsRun: Bool
        /// Last of a run: shows the avatar and the time.
        let endsRun: Bool
    }

    enum Entry: Identifiable, Hashable, Sendable {
        case day(String)
        case message(Bubble)
        case event(GroupEvent)

        var id: String {
            switch self {
            case .day(let title): "day-\(title)"
            case .message(let bubble): bubble.message.id.uuidString
            case .event(let event): event.id.uuidString
            }
        }
    }

    /// Messages from one person within this many seconds form a run.
    static let runGap: TimeInterval = 5 * 60

    static func entries(
        messages: [ChatMessage],
        pending: [(message: ChatMessage, failed: Bool)] = [],
        events: [GroupEvent],
        userID: UUID?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Entry] {
        enum Item { case message(ChatMessage, Delivery), event(GroupEvent) }
        let sentIDs = Set(messages.map(\.id))
        var items: [(date: Date, item: Item)] = messages.map { ($0.createdAt, .message($0, .sent)) }
        items += pending.filter { !sentIDs.contains($0.message.id) }
            .map { ($0.message.createdAt, .message($0.message, $0.failed ? .failed : .sending)) }
        items += events.map { ($0.createdAt, .event($0)) }
        items.sort { $0.date < $1.date }

        var result: [Entry] = []
        var lastDay: String?
        for (index, entry) in items.enumerated() {
            let day = title(for: entry.date, now: now, calendar: calendar)
            if day != lastDay {
                result.append(.day(day))
                lastDay = day
            }
            switch entry.item {
            case .event(let event):
                result.append(.event(event))
            case .message(let message, let delivery):
                func continues(_ other: (date: Date, item: Item)?) -> Bool {
                    guard let other, case .message(let neighbour, _) = other.item else { return false }
                    return neighbour.authorID == message.authorID
                        && abs(other.date.timeIntervalSince(entry.date)) <= runGap
                        && calendar.isDate(other.date, inSameDayAs: entry.date)
                }
                let previous = index > 0 ? items[index - 1] : nil
                let next = index + 1 < items.count ? items[index + 1] : nil
                result.append(.message(Bubble(
                    message: message,
                    isMine: message.authorID == userID,
                    delivery: delivery,
                    startsRun: !continues(previous),
                    endsRun: !continues(next)
                )))
            }
        }
        return result
    }

    static func title(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Heute" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Gestern"
        }
        return date.formatted(calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? .dateTime.weekday(.wide).day().month(.wide)
            : .dateTime.day().month(.wide).year())
    }
}
