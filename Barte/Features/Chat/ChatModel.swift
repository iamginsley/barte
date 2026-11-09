import Foundation
import Observation

/// One group's chat: the messages, the history in between, and what is being written.
/// Sent messages show at once and turn solid when the server has them; failed ones can be retried.
@Observable
@MainActor
final class ChatModel {
    struct Outgoing {
        var message: ChatMessage
        var failed: Bool
    }

    let groupID: UUID
    private(set) var messages: [ChatMessage] = []
    private(set) var events: [GroupEvent] = []
    private(set) var outbox: [Outgoing] = []
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    var draft = ""
    /// The expense the next message is about.
    var reference: Expense?
    var actionError: String?

    /// The newest message from someone else that was marked as read.
    private var markedReadID: UUID?

    init(groupID: UUID, reference: Expense? = nil) {
        self.groupID = groupID
        self.reference = reference
    }

    var canSend: Bool { ChatMessage.cleaned(draft) != nil }

    func entries(userID: UUID?) -> [ChatTimeline.Entry] {
        ChatTimeline.entries(messages: messages, pending: outbox.map { ($0.message, $0.failed) }, events: events, userID: userID)
    }

    func load(_ repository: GroupRepository) async {
        let groupID = groupID
        do {
            async let fetchedMessages = repository.fetchChat(groupID: groupID)
            async let fetchedEvents = repository.fetchHistory(groupID: groupID, subjectID: nil)
            messages = try await fetchedMessages
            events = try await fetchedEvents
            let sent = Set(messages.map(\.id))
            outbox.removeAll { sent.contains($0.message.id) }
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            // Keep showing what is there; only an empty chat shows the error.
            loadError = UserFacingError(error).message
        }
        hasLoaded = true
    }

    /// True once per new message from someone else, so the read mark goes out only when needed.
    func takeUnreadMark(userID: UUID?) -> Bool {
        guard let newest = messages.last(where: { $0.authorID != userID }), newest.id != markedReadID else { return false }
        markedReadID = newest.id
        return true
    }

    func send(_ repository: GroupRepository, userID: UUID?, memberID: UUID?) async {
        guard let body = ChatMessage.cleaned(draft), let userID else { return }
        let message = ChatMessage(id: UUID(), memberID: memberID, authorID: userID, body: body, expenseID: reference?.id, createdAt: .now)
        draft = ""
        reference = nil
        outbox.append(Outgoing(message: message, failed: false))
        await deliver(message, repository)
    }

    func retry(_ id: UUID, _ repository: GroupRepository) async {
        guard let index = outbox.firstIndex(where: { $0.message.id == id }) else { return }
        outbox[index].failed = false
        await deliver(outbox[index].message, repository)
    }

    func discard(_ id: UUID) {
        outbox.removeAll { $0.message.id == id }
    }

    func delete(_ id: UUID, _ repository: GroupRepository) async {
        do {
            try await repository.deleteMessage(id)
            await load(repository)
        } catch {
            actionError = UserFacingError(error).message
        }
    }

    private func deliver(_ message: ChatMessage, _ repository: GroupRepository) async {
        do {
            try await repository.sendMessage(message.id, body: message.body ?? "", expenseID: message.expenseID, in: groupID)
            await load(repository)
        } catch {
            if let index = outbox.firstIndex(where: { $0.message.id == message.id }) { outbox[index].failed = true }
        }
    }
}
