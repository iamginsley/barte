import Foundation
import Testing
@testable import Barte

/// The chat timeline, links to a chat and sending through the demo repository.
@Suite("Chat")
struct ChatTests {
    private let me = UUID()
    private let anna = UUID()
    private let calendar = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 18))!

    private func message(_ author: UUID, minutesAgo: Double, _ text: String = "Hi") -> ChatMessage {
        ChatMessage(id: UUID(), memberID: nil, authorID: author, body: text, expenseID: nil, createdAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func event(minutesAgo: Double) -> GroupEvent {
        GroupEvent(id: UUID(), kind: .expenseAdded, actorID: anna, actorName: "Anna", subjectID: UUID(), old: nil, new: nil,
                   createdAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func bubbles(_ entries: [ChatTimeline.Entry]) -> [ChatTimeline.Bubble] {
        entries.compactMap { if case .message(let bubble) = $0 { bubble } else { nil } }
    }

    @Test func messagesAndHistoryShareOneTimelineByDay() {
        let entries = ChatTimeline.entries(
            messages: [message(anna, minutesAgo: 24 * 60), message(me, minutesAgo: 5)],
            events: [event(minutesAgo: 10)], userID: me, now: now, calendar: calendar
        )
        let kinds = entries.map { entry -> String in
            switch entry {
            case .day(let title): title
            case .message(let bubble): bubble.isMine ? "mine" : "other"
            case .event: "event"
            }
        }
        #expect(kinds == ["Gestern", "other", "Heute", "event", "mine"])
    }

    @Test func runsGroupMessagesFromOnePersonUntilSomethingElseHappens() {
        let entries = ChatTimeline.entries(
            messages: [message(anna, minutesAgo: 30), message(anna, minutesAgo: 29), message(anna, minutesAgo: 10), message(anna, minutesAgo: 2)],
            events: [event(minutesAgo: 5)], userID: me, now: now, calendar: calendar
        )
        let runs = bubbles(entries).map { ($0.startsRun, $0.endsRun) }
        // 30 and 29 belong together; 10 is too late; the event splits 10 from 2.
        #expect(runs.map(\.0) == [true, false, true, true])
        #expect(runs.map(\.1) == [false, true, true, true])
    }

    @Test func pendingMessagesShowUntilTheServerHasThem() {
        let sent = message(me, minutesAgo: 1)
        let waiting = message(me, minutesAgo: 0)
        let failed = message(me, minutesAgo: 0)
        let entries = ChatTimeline.entries(
            messages: [sent], pending: [(sent, false), (waiting, false), (failed, true)],
            events: [], userID: me, now: now, calendar: calendar
        )
        #expect(bubbles(entries).map(\.delivery) == [.sent, .sending, .failed])
    }

    @Test func cleanedTextIsTrimmedAndNeverEmpty() {
        #expect(ChatMessage.cleaned("  Hallo\n\n") == "Hallo")
        #expect(ChatMessage.cleaned(" \n ") == nil)
        #expect(ChatMessage.cleaned(String(repeating: "x", count: 2500))?.count == ChatMessage.maxLength)
    }

    @Test func chatLinksOpenTheGroupAndItsChat() {
        let id = UUID()
        #expect(BarteLink.groupID(from: BarteLink.chat(id)) == id)
        #expect(BarteLink.opensChat(BarteLink.chat(id)))
        #expect(!BarteLink.opensChat(BarteLink.group(id)))
        #expect(BarteLink.chat(id).absoluteString == "barte://group/\(id.uuidString.lowercased())/chat")
    }

    @MainActor
    @Test func sendingInTheDemoClearsTheDraftAndLands() async throws {
        let repository = DemoGroupRepository()
        let group = try #require(try await repository.fetchGroups().first { $0.name == "Skiurlaub Saalbach" })
        #expect(group.unreadMessages == 2)

        let chat = ChatModel(groupID: group.id, reference: group.expenses.first)
        await chat.load(repository)
        let before = chat.messages.count
        chat.draft = "  Ich nehm 20 € mit \n"
        #expect(chat.canSend)
        await chat.send(repository, userID: DemoData.userID, memberID: group.me(userID: DemoData.userID))
        #expect(chat.draft.isEmpty && chat.reference == nil && chat.outbox.isEmpty)
        #expect(chat.messages.count == before + 1)
        #expect(chat.messages.last?.body == "Ich nehm 20 € mit")
        #expect(chat.messages.last?.expenseID == group.expenses.first?.id)

        // Writing counts as reading.
        #expect(try await repository.fetchGroups().first { $0.id == group.id }?.unreadMessages == 0)

        let mine = try #require(chat.messages.last)
        await chat.delete(mine.id, repository)
        #expect(chat.messages.last?.isDeleted == true && chat.messages.last?.body == nil)
    }

    @MainActor
    @Test func readMarkGoesOutOncePerNewMessage() async {
        let repository = DemoGroupRepository()
        let group = try! await repository.fetchGroups().first { $0.name == "Skiurlaub Saalbach" }!
        let chat = ChatModel(groupID: group.id)
        await chat.load(repository)
        #expect(chat.takeUnreadMark(userID: DemoData.userID))
        #expect(!chat.takeUnreadMark(userID: DemoData.userID))
    }
}
