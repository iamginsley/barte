import Foundation
import Supabase

/// Groups, their people and expenses. Reads go through Row Level Security, writes through SQL functions.
protocol GroupRepository: Sendable {
    func fetchGroups() async throws -> [SplitGroup]

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID
    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws
    func deleteGroup(_ id: UUID) async throws
    func leaveGroup(_ id: UUID) async throws

    func addMember(named name: String, to groupID: UUID) async throws -> UUID
    func renameMember(_ id: UUID, to name: String) async throws
    func removeMember(_ id: UUID) async throws
    /// Makes this person the given member instead of their current one.
    func claimMember(_ id: UUID) async throws

    func save(_ expense: Expense, in groupID: UUID) async throws
    func deleteExpense(_ id: UUID) async throws

    func previewInvite(code: String) async throws -> InvitePreview
    /// Joins as an unclaimed member, or as a new person when `memberID` is nil.
    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID

    func deleteAccount(appleAuthorizationCode: String) async throws

    /// Signals whenever something in this person's groups changes, also from other people.
    func changes() -> AsyncStream<Void>
}

struct SupabaseGroupRepository: GroupRepository {
    let client: SupabaseClient

    // MARK: Reading

    private struct GroupRow: Decodable {
        let id: UUID
        let name: String
        let currency: String
        let color: Int
        let inviteCode: String
        let createdBy: UUID?
        let createdAt: Date
        let members: [MemberRow]
        let expenses: [ExpenseRow]

        enum CodingKeys: String, CodingKey {
            case id, name, currency, color, members, expenses
            case inviteCode = "invite_code"
            case createdBy = "created_by"
            case createdAt = "created_at"
        }
    }

    private struct MemberRow: Decodable {
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

    private struct ExpenseRow: Decodable {
        let id: UUID
        let title: String
        let amountCents: Int
        let spentOn: String
        let payerID: UUID
        let participantIDs: [UUID]
        let isSettlement: Bool
        let splitKind: String
        let splitValues: [Int]?
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

    func fetchGroups() async throws -> [SplitGroup] {
        let rows: [GroupRow] = try await client.from("groups")
            .select("id, name, currency, color, invite_code, created_by, created_at, members(id, name, user_id, created_at), expenses(id, title, amount_cents, spent_on, payer_id, participant_ids, is_settlement, split_kind, split_values, created_at)")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map(Self.group(from:))
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
                    participantIDs: item.row.participantIDs,
                    isSettlement: item.row.isSettlement,
                    split: SplitMode(kind: item.row.splitKind, values: item.row.splitValues, participants: item.row.participantIDs)
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
            createdBy: row.createdBy
        )
    }

    // MARK: Groups

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID {
        struct Params: Encodable {
            let p_name: String
            let p_currency: String
            let p_color: Int
            let p_my_name: String
            let p_other_names: [String]
        }
        return try await client.rpc("create_group", params: Params(
            p_name: name, p_currency: currency, p_color: color.rawValue, p_my_name: myName, p_other_names: otherNames
        )).execute().value
    }

    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws {
        struct Params: Encodable {
            let p_group_id: UUID
            let p_name: String
            let p_currency: String
            let p_color: Int
        }
        try await client.rpc("update_group", params: Params(p_group_id: id, p_name: name, p_currency: currency, p_color: color.rawValue)).execute()
    }

    func deleteGroup(_ id: UUID) async throws {
        try await client.rpc("delete_group", params: ["p_group_id": id]).execute()
    }

    func leaveGroup(_ id: UUID) async throws {
        try await client.rpc("leave_group", params: ["p_group_id": id]).execute()
    }

    // MARK: Members

    func addMember(named name: String, to groupID: UUID) async throws -> UUID {
        struct Params: Encodable { let p_group_id: UUID; let p_name: String }
        return try await client.rpc("add_member", params: Params(p_group_id: groupID, p_name: name)).execute().value
    }

    func renameMember(_ id: UUID, to name: String) async throws {
        struct Params: Encodable { let p_member_id: UUID; let p_name: String }
        try await client.rpc("rename_member", params: Params(p_member_id: id, p_name: name)).execute()
    }

    func removeMember(_ id: UUID) async throws {
        try await client.rpc("remove_member", params: ["p_member_id": id]).execute()
    }

    func claimMember(_ id: UUID) async throws {
        try await client.rpc("claim_member", params: ["p_member_id": id]).execute()
    }

    // MARK: Expenses

    func save(_ expense: Expense, in groupID: UUID) async throws {
        struct Params: Encodable {
            let p_id: UUID
            let p_group_id: UUID
            let p_title: String
            let p_amount_cents: Int
            let p_spent_on: String
            let p_payer_id: UUID
            let p_participant_ids: [UUID]
            let p_is_settlement: Bool
            let p_split_kind: String
            let p_split_values: Nullable<[Int]>
        }
        try await client.rpc("save_expense", params: Params(
            p_id: expense.id,
            p_group_id: groupID,
            p_title: expense.title,
            p_amount_cents: expense.amountCents,
            p_spent_on: LocalDay.string(from: expense.date),
            p_payer_id: expense.payerID,
            p_participant_ids: expense.participantIDs,
            p_is_settlement: expense.isSettlement,
            p_split_kind: expense.split.kind,
            p_split_values: Nullable(expense.splitValues)
        )).execute()
    }

    func deleteExpense(_ id: UUID) async throws {
        try await client.rpc("delete_expense", params: ["p_id": id]).execute()
    }

    // MARK: Joining

    func previewInvite(code: String) async throws -> InvitePreview {
        try await client.rpc("preview_invite", params: ["p_code": code]).execute().value
    }

    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID {
        struct Params: Encodable {
            let p_code: String
            let p_member_id: Nullable<UUID>
            let p_name: Nullable<String>
        }
        return try await client.rpc("join_group", params: Params(p_code: code, p_member_id: Nullable(memberID), p_name: Nullable(name))).execute().value
    }

    // MARK: Account

    func deleteAccount(appleAuthorizationCode: String) async throws {
        do {
            try await client.functions.invoke("apple-revoke", options: .init(body: ["authorization_code": appleAuthorizationCode]))
        } catch {
            throw BarteError.appleRevocationFailed
        }
        try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: Realtime

    /// Row Level Security decides which changes reach this person, so no filter is needed.
    func changes() -> AsyncStream<Void> {
        let client = client
        return AsyncStream { continuation in
            let task = Task {
                let channel = client.channel("barte-\(UUID().uuidString)")
                let streams = ["groups", "members", "expenses"].map { table in
                    channel.postgresChange(AnyAction.self, schema: "public", table: table)
                }
                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.finish()
                    return
                }
                await withTaskGroup(of: Void.self) { group in
                    for stream in streams {
                        group.addTask {
                            for await _ in stream { continuation.yield() }
                        }
                    }
                }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
