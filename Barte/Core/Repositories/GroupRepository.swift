import Foundation

/// Groups, their people and expenses. Reads go through the Hasura permissions, writes through SQL functions.
protocol GroupRepository: Sendable {
    func fetchGroups() async throws -> [SplitGroup]

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID
    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws
    func deleteGroup(_ id: UUID) async throws
    func leaveGroup(_ id: UUID) async throws
    /// Puts a group away for everyone in it, or brings it back.
    func setClosed(_ closed: Bool, group id: UUID) async throws

    func addMember(named name: String, to groupID: UUID) async throws -> UUID
    func renameMember(_ id: UUID, to name: String) async throws
    func removeMember(_ id: UUID) async throws

    func save(_ expense: Expense, in groupID: UUID) async throws
    func deleteExpense(_ id: UUID) async throws

    func previewInvite(code: String) async throws -> InvitePreview
    /// Joins as an unclaimed member, or as a new person when `memberID` is nil.
    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID

    /// Payment details of everyone this person shares a group with, and their own, by user id.
    func fetchPaymentDetails() async throws -> [UUID: PaymentDetails]
    /// Empty details remove them.
    func savePaymentDetails(_ details: PaymentDetails) async throws

    func deleteAccount(appleAuthorizationCode: String) async throws
    /// The account name, used in every group; changing it renames this person everywhere.
    func setMyName(_ name: String) async throws -> String
    /// The account name after signing in; `fallback` names accounts that don't have one yet.
    func syncMyName(fallback: String?) async throws -> String?

    /// The group's history, newest first; only what concerns one expense or member with `subjectID`.
    func fetchHistory(groupID: UUID, subjectID: UUID?) async throws -> [GroupEvent]

    // MARK: Chat

    /// The newest messages, oldest first.
    func fetchChat(groupID: UUID) async throws -> [ChatMessage]
    /// `id` comes from the app, so sending again after a lost connection doesn't duplicate it.
    func sendMessage(_ id: UUID, body: String, expenseID: UUID?, in groupID: UUID) async throws
    /// Only own messages; a placeholder stays.
    func deleteMessage(_ id: UUID) async throws
    func markChatRead(groupID: UUID) async throws
    func setChatMuted(_ muted: Bool, group id: UUID) async throws
    /// Signals new and deleted messages and new history entries in one group.
    func chatChanges(groupID: UUID) -> AsyncStream<Void>

    /// Signals whenever something in this person's groups changes, also from other people.
    func changes() -> AsyncStream<Void>
}

struct NhostGroupRepository: GroupRepository {
    let api: NhostAPI

    // MARK: Reading

    private struct GroupRow: Decodable, Sendable {
        let id: UUID
        let name: String
        let currency: String
        let color: Int
        let inviteCode: String
        let createdBy: UUID?
        let createdAt: Date
        let closedAt: Date?
        let members: [MemberRow]
        let expenses: [ExpenseRow]
        let events: [EditedRow]
        let unreadMessages: Int?
        /// Only this person's own row, if any.
        let chatStates: [ChatStateRow]?

        struct EditedRow: Decodable, Sendable {
            let subjectID: UUID?
            enum CodingKeys: String, CodingKey { case subjectID = "subject_id" }
        }

        struct ChatStateRow: Decodable, Sendable { let muted: Bool }

        enum CodingKeys: String, CodingKey {
            case id, name, currency, color, members, expenses, events
            case unreadMessages = "unread_messages"
            case chatStates = "chat_states"
            case inviteCode = "invite_code"
            case createdBy = "created_by"
            case createdAt = "created_at"
            case closedAt = "closed_at"
        }
    }

    private struct MemberRow: Decodable, Sendable {
        let id: UUID
        let name: String
        let userID: UUID?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, name
            case userID = "user_id"
            case createdAt = "created_at"
        }
    }

    private struct ExpenseRow: Decodable, Sendable {
        let id: UUID
        let title: String
        let amountCents: Int
        let spentOn: String
        let payerID: UUID
        let participantIDs: PGArray<UUID>
        let isSettlement: Bool
        let splitKind: String
        let splitValues: PGArray<Int>?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title
            case splitKind = "split_kind"
            case splitValues = "split_values"
            case amountCents = "amount_cents"
            case spentOn = "spent_on"
            case payerID = "payer_id"
            case participantIDs = "participant_ids"
            case isSettlement = "is_settlement"
            case createdAt = "created_at"
        }
    }

    private static let groupFields = """
        id name currency color invite_code created_by created_at closed_at
        members { id name user_id created_at }
        expenses { id title amount_cents spent_on payer_id participant_ids is_settlement split_kind split_values created_at }
        events(where: { kind: { _eq: "expense_changed" } }) { subject_id }
        unread_messages
        chat_states { muted }
        """

    func fetchGroups() async throws -> [SplitGroup] {
        struct Data: Decodable, Sendable { let groups: [GroupRow] }
        let data: Data = try await api.query("query Groups { groups(order_by: { created_at: desc }) { \(Self.groupFields) } }")
        return data.groups.map(Self.group(from:))
    }

    private static func group(from row: GroupRow) -> SplitGroup {
        let members = row.members
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .map { Member(id: $0.id, name: $0.name, userID: $0.userID) }
        let expenses = row.expenses
            .map { (row: $0, day: LocalDay.date(from: $0.spentOn) ?? $0.createdAt) }
            .sorted { ($0.day, $0.row.createdAt) > ($1.day, $1.row.createdAt) }
            .map { item in
                Expense(
                    id: item.row.id,
                    title: item.row.title,
                    amountCents: item.row.amountCents,
                    date: item.day,
                    payerID: item.row.payerID,
                    participantIDs: item.row.participantIDs.values,
                    isSettlement: item.row.isSettlement,
                    split: SplitMode(kind: item.row.splitKind, values: item.row.splitValues?.values, participants: item.row.participantIDs.values)
                )
            }
        return SplitGroup(
            id: row.id,
            name: row.name,
            currency: row.currency,
            color: CardColor(rawValue: row.color) ?? .blue,
            createdAt: row.createdAt,
            members: members,
            expenses: expenses,
            inviteCode: row.inviteCode,
            createdBy: row.createdBy,
            closedAt: row.closedAt,
            editedExpenseIDs: Set(row.events.compactMap(\.subjectID)),
            unreadMessages: row.unreadMessages ?? 0,
            chatMuted: row.chatStates?.first?.muted ?? false
        )
    }

    /// The id an SQL function returned, or an error when it unexpectedly returned none.
    private func id(from result: NhostAPI.Result?) throws -> UUID {
        guard let id = result?.id else { throw BarteError.server(hint: nil) }
        return id
    }

    // MARK: Groups

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID {
        try id(from: await api.call("create_group", [
            "p_name": .string(name),
            "p_currency": .string(currency),
            "p_color": .int(color.rawValue),
            "p_my_name": .string(myName),
            "p_other_names": .pgArray(otherNames),
        ]))
    }

    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws {
        try await api.call("update_group", [
            "p_group_id": .uuid(id), "p_name": .string(name), "p_currency": .string(currency), "p_color": .int(color.rawValue),
        ])
    }

    func deleteGroup(_ id: UUID) async throws {
        try await api.call("delete_group", ["p_group_id": .uuid(id)])
    }

    func leaveGroup(_ id: UUID) async throws {
        try await api.call("leave_group", ["p_group_id": .uuid(id)])
    }

    func setClosed(_ closed: Bool, group id: UUID) async throws {
        try await api.call("set_group_closed", ["p_group_id": .uuid(id), "p_closed": .bool(closed)])
    }

    // MARK: Members

    func addMember(named name: String, to groupID: UUID) async throws -> UUID {
        try id(from: await api.call("add_member", ["p_group_id": .uuid(groupID), "p_name": .string(name)]))
    }

    func renameMember(_ id: UUID, to name: String) async throws {
        try await api.call("rename_member", ["p_member_id": .uuid(id), "p_name": .string(name)])
    }

    func removeMember(_ id: UUID) async throws {
        try await api.call("remove_member", ["p_member_id": .uuid(id)])
    }


    // MARK: Expenses

    func save(_ expense: Expense, in groupID: UUID) async throws {
        try await api.call("save_expense", [
            "p_id": .uuid(expense.id),
            "p_group_id": .uuid(groupID),
            "p_title": .string(expense.title),
            "p_amount_cents": .int(expense.amountCents),
            "p_spent_on": .string(LocalDay.string(from: expense.date)),
            "p_payer_id": .uuid(expense.payerID),
            "p_participant_ids": .pgArray(expense.participantIDs),
            "p_is_settlement": .bool(expense.isSettlement),
            "p_split_kind": .string(expense.split.kind),
            "p_split_values": .pgArray(expense.splitValues),
        ])
    }

    func deleteExpense(_ id: UUID) async throws {
        try await api.call("delete_expense", ["p_id": .uuid(id)])
    }

    // MARK: Joining

    func previewInvite(code: String) async throws -> InvitePreview {
        guard let preview = try await api.call("preview_invite", ["p_code": .string(code)])?.preview else {
            throw BarteError.server(hint: "invalid_code")
        }
        return preview
    }

    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID {
        try id(from: await api.call("join_group", ["p_code": .string(code), "p_member_id": .uuid(memberID), "p_name": .optional(name)]))
    }

    // MARK: Payment details

    private struct PaymentRow: Decodable, Sendable {
        let userID: UUID
        let paypal: String?
        let iban: String?
        let accountHolder: String?

        enum CodingKeys: String, CodingKey {
            case paypal, iban
            case userID = "user_id"
            case accountHolder = "account_holder"
        }
    }

    func fetchPaymentDetails() async throws -> [UUID: PaymentDetails] {
        struct Data: Decodable, Sendable { let payment_details: [PaymentRow] }
        let data: Data = try await api.query("query Payments { payment_details { user_id paypal iban account_holder } }")
        return Dictionary(data.payment_details.map { ($0.userID, PaymentDetails(paypal: $0.paypal, iban: $0.iban, accountHolder: $0.accountHolder)) },
                          uniquingKeysWith: { first, _ in first })
    }

    func savePaymentDetails(_ details: PaymentDetails) async throws {
        try await api.call("set_payment_details", [
            "p_paypal": .optional(details.paypal), "p_iban": .optional(details.iban), "p_account_holder": .optional(details.accountHolder),
        ])
    }

    // MARK: Account

    func deleteAccount(appleAuthorizationCode: String) async throws {
        do {
            try await api.invokeFunction("apple-revoke", body: ["authorization_code": .string(appleAuthorizationCode)])
        } catch {
            throw BarteError.appleRevocationFailed
        }
        try await api.call("delete_my_account")
        await api.session.signOutLocally()
    }

    func setMyName(_ name: String) async throws -> String {
        guard let saved = try await api.call("set_my_name", ["p_name": .string(name)])?.code else { throw BarteError.server(hint: nil) }
        return saved
    }

    func syncMyName(fallback: String?) async throws -> String? {
        try await api.call("sync_my_name", ["p_fallback": .optional(fallback)])?.code
    }

    // MARK: History

    private struct EventRow: Decodable, Sendable {
        let id: UUID
        let kind: String
        let actorID: UUID?
        let actorName: String?
        let subjectID: UUID?
        let old: GroupEvent.Snapshot?
        let new: GroupEvent.Snapshot?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, kind, old, new
            case actorID = "actor_id"
            case actorName = "actor_name"
            case subjectID = "subject_id"
            case createdAt = "created_at"
        }
    }

    func fetchHistory(groupID: UUID, subjectID: UUID?) async throws -> [GroupEvent] {
        struct Data: Decodable, Sendable { let group_events: [EventRow] }
        let subjectFilter = subjectID == nil ? "" : ", subject_id: { _eq: $subject }"
        let subjectVariable = subjectID == nil ? "" : ", $subject: uuid!"
        var variables: [String: JSON] = ["group": .uuid(groupID)]
        if let subjectID { variables["subject"] = .uuid(subjectID) }
        let data: Data = try await api.query(
            """
            query History($group: uuid!\(subjectVariable)) {
              group_events(where: { group_id: { _eq: $group }\(subjectFilter) }, order_by: { created_at: desc }, limit: 300) {
                id kind actor_id actor_name subject_id old new created_at
              }
            }
            """,
            variables: variables
        )
        return data.group_events.map {
            GroupEvent(id: $0.id, kind: GroupEvent.Kind(rawValue: $0.kind) ?? .unknown, actorID: $0.actorID, actorName: $0.actorName,
                       subjectID: $0.subjectID, old: $0.old, new: $0.new, createdAt: $0.createdAt)
        }
    }

    // MARK: Chat

    private struct MessageRow: Decodable, Sendable {
        let id: UUID
        let memberID: UUID?
        let authorID: UUID
        let body: String?
        let expenseID: UUID?
        let createdAt: Date
        let deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, body
            case memberID = "member_id"
            case authorID = "author_id"
            case expenseID = "expense_id"
            case createdAt = "created_at"
            case deletedAt = "deleted_at"
        }
    }

    func fetchChat(groupID: UUID) async throws -> [ChatMessage] {
        struct Data: Decodable, Sendable { let chat_messages: [MessageRow] }
        let data: Data = try await api.query(
            """
            query Chat($group: uuid!) {
              chat_messages(where: { group_id: { _eq: $group } }, order_by: { created_at: desc }, limit: 300) {
                id member_id author_id body expense_id created_at deleted_at
              }
            }
            """,
            variables: ["group": .uuid(groupID)]
        )
        return data.chat_messages.reversed().map {
            ChatMessage(id: $0.id, memberID: $0.memberID, authorID: $0.authorID, body: $0.body,
                        expenseID: $0.expenseID, createdAt: $0.createdAt, deletedAt: $0.deletedAt)
        }
    }

    func sendMessage(_ id: UUID, body: String, expenseID: UUID?, in groupID: UUID) async throws {
        try await api.call("send_message", [
            "p_id": .uuid(id), "p_group_id": .uuid(groupID), "p_body": .string(body), "p_expense_id": .uuid(expenseID),
        ])
    }

    func deleteMessage(_ id: UUID) async throws {
        try await api.call("delete_message", ["p_id": .uuid(id)])
    }

    func markChatRead(groupID: UUID) async throws {
        try await api.call("mark_chat_read", ["p_group_id": .uuid(groupID)])
    }

    func setChatMuted(_ muted: Bool, group id: UUID) async throws {
        try await api.call("set_chat_muted", ["p_group_id": .uuid(id), "p_muted": .bool(muted)])
    }

    func chatChanges(groupID: UUID) -> AsyncStream<Void> {
        // A UUID can't break out of the string, so it goes straight into the query.
        let group = groupID.uuidString.lowercased()
        return api.changes(of: [
            "subscription { chat_messages(where: { group_id: { _eq: \"\(group)\" } }, order_by: { created_at: desc }, limit: 100) { id deleted_at } }",
            "subscription { group_events(where: { group_id: { _eq: \"\(group)\" } }, order_by: { created_at: desc }, limit: 1) { id } }",
        ])
    }

    // MARK: Live updates

    /// Hasura's permissions decide which rows these see, so they cover exactly this person's groups.
    func changes() -> AsyncStream<Void> {
        api.changes(of: [
            "subscription Groups { groups { id name currency color invite_code closed_at unread_messages members { id name user_id } expenses { id updated_at } } }",
            "subscription Payments { payment_details { user_id updated_at } }",
        ])
    }
}
