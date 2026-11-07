import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Groups, their people and expenses. Reads come straight from Firestore (the security rules keep them
/// to this person's groups), writes go through Cloud Functions that check membership and consistency.
protocol GroupRepository: Sendable {
    func fetchGroups() async throws -> [SplitGroup]

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID
    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws
    func deleteGroup(_ id: UUID) async throws
    func leaveGroup(_ id: UUID) async throws

    func addMember(named name: String, to groupID: UUID) async throws -> UUID
    func renameMember(_ id: UUID, in groupID: UUID, to name: String) async throws
    func removeMember(_ id: UUID, from groupID: UUID) async throws
    /// Makes this person the given member instead of their current one.
    func claimMember(_ id: UUID, in groupID: UUID) async throws

    func save(_ expense: Expense, in groupID: UUID) async throws
    func deleteExpense(_ id: UUID, in groupID: UUID) async throws

    func previewInvite(code: String) async throws -> InvitePreview
    /// Joins as an unclaimed member, or as a new person when `memberID` is nil.
    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID

    /// Payment details of everyone this person shares a group with, and their own, by user id.
    func fetchPaymentDetails() async throws -> [UserID: PaymentDetails]
    /// Empty details remove them.
    func savePaymentDetails(_ details: PaymentDetails) async throws

    func deleteAccount(appleAuthorizationCode: String) async throws

    /// Signals whenever something in this person's groups changes, also from other people.
    func changes() -> AsyncStream<Void>
}

/// Firestore keeps ids as lowercase strings.
extension UUID {
    var key: String { uuidString.lowercased() }
}

struct FirebaseGroupRepository: GroupRepository {
    private var db: Firestore { Firestore.firestore() }
    private var groups: CollectionReference { db.collection("groups") }

    // MARK: Reading

    private struct GroupRow: Decodable {
        struct MemberRow: Decodable {
            let id: String
            let name: String
            let uid: String?
            let joinedAt: Double
        }

        let name: String
        let currency: String
        let color: Int
        let inviteCode: String
        let createdBy: String?
        let createdAt: Date?
        let members: [MemberRow]
    }

    private struct ExpenseRow: Decodable {
        let title: String
        let amountCents: Int
        let spentOn: String
        let payerId: String
        let participantIds: [String]
        let isSettlement: Bool
        let splitKind: String?
        let splitValues: [Int]?
        let createdAt: Date?
    }

    func fetchGroups() async throws -> [SplitGroup] {
        let uid = try Backend.currentUserID
        let snapshot = try await groups.whereField("memberUids", arrayContains: uid).getDocuments()
        let rows: [(id: UUID, row: GroupRow)] = try snapshot.documents.compactMap { document in
            guard let id = UUID(uuidString: document.documentID) else { return nil }
            return (id, try document.data(as: GroupRow.self))
        }
        let result = try await withThrowingTaskGroup(of: SplitGroup.self) { tasks in
            for item in rows {
                tasks.addTask { try await group(id: item.id, row: item.row) }
            }
            return try await tasks.reduce(into: []) { $0.append($1) }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    private func group(id: UUID, row: GroupRow) async throws -> SplitGroup {
        let expenseDocs = try await groups.document(id.key).collection("expenses").getDocuments().documents
        let expenses: [Expense] = try expenseDocs.compactMap { document in
            let item = try document.data(as: ExpenseRow.self)
            guard let expenseID = UUID(uuidString: document.documentID),
                  let payer = UUID(uuidString: item.payerId) else { return nil }
            let participants = item.participantIds.compactMap(UUID.init(uuidString:))
            return Expense(
                id: expenseID,
                title: item.title,
                amountCents: item.amountCents,
                date: LocalDay.date(from: item.spentOn) ?? item.createdAt ?? .now,
                payerID: payer,
                participantIDs: participants,
                isSettlement: item.isSettlement,
                split: SplitMode(kind: item.splitKind ?? "equal", values: item.splitValues, participants: participants)
            )
        }
        let createdAt = Dictionary(expenseDocs.map { ($0.documentID, (try? $0.data(as: ExpenseRow.self))?.createdAt ?? .distantPast) },
                                   uniquingKeysWith: { first, _ in first })
        let sorted = expenses.sorted {
            ($0.date, createdAt[$0.id.key] ?? .distantPast) > ($1.date, createdAt[$1.id.key] ?? .distantPast)
        }
        let members = row.members
            .sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }
            .compactMap { member in UUID(uuidString: member.id).map { Member(id: $0, name: member.name, userID: member.uid) } }
        return SplitGroup(
            id: id,
            name: row.name,
            currency: row.currency,
            color: CardColor(rawValue: row.color) ?? .blue,
            createdAt: row.createdAt ?? .now,
            members: members,
            expenses: sorted,
            inviteCode: row.inviteCode,
            createdBy: row.createdBy
        )
    }

    // MARK: Calling functions

    private struct Empty: Codable, Sendable {}

    private func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, _ request: Request, as response: Response.Type = Empty.self
    ) async throws -> Response {
        let callable = Backend.functions.httpsCallable(name, requestAs: Request.self, responseAs: Response.self)
        return try await callable(request)
    }

    private struct GroupRef: Codable, Sendable { let groupId: String }
    private struct MemberRef: Codable, Sendable { let groupId: String; let memberId: String }

    // MARK: Groups

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID {
        struct Request: Encodable, Sendable {
            let name: String
            let currency: String
            let color: Int
            let myName: String
            let otherNames: [String]
        }
        let response = try await call("createGroup", Request(
            name: name, currency: currency, color: color.rawValue, myName: myName, otherNames: otherNames
        ), as: GroupRef.self)
        guard let id = UUID(uuidString: response.groupId) else { throw BarteError.server(hint: nil) }
        return id
    }

    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws {
        struct Request: Encodable, Sendable { let groupId: String; let name: String; let currency: String; let color: Int }
        _ = try await call("updateGroup", Request(groupId: id.key, name: name, currency: currency, color: color.rawValue))
    }

    func deleteGroup(_ id: UUID) async throws {
        _ = try await call("deleteGroup", GroupRef(groupId: id.key))
    }

    func leaveGroup(_ id: UUID) async throws {
        _ = try await call("leaveGroup", GroupRef(groupId: id.key))
    }

    // MARK: Members

    func addMember(named name: String, to groupID: UUID) async throws -> UUID {
        struct Request: Encodable, Sendable { let groupId: String; let name: String }
        struct Response: Decodable, Sendable { let memberId: String }
        let response = try await call("addMember", Request(groupId: groupID.key, name: name), as: Response.self)
        guard let id = UUID(uuidString: response.memberId) else { throw BarteError.server(hint: nil) }
        return id
    }

    func renameMember(_ id: UUID, in groupID: UUID, to name: String) async throws {
        struct Request: Encodable, Sendable { let groupId: String; let memberId: String; let name: String }
        _ = try await call("renameMember", Request(groupId: groupID.key, memberId: id.key, name: name))
    }

    func removeMember(_ id: UUID, from groupID: UUID) async throws {
        _ = try await call("removeMember", MemberRef(groupId: groupID.key, memberId: id.key))
    }

    func claimMember(_ id: UUID, in groupID: UUID) async throws {
        _ = try await call("claimMember", MemberRef(groupId: groupID.key, memberId: id.key))
    }

    // MARK: Expenses

    func save(_ expense: Expense, in groupID: UUID) async throws {
        struct Request: Encodable, Sendable {
            let groupId: String
            let id: String
            let title: String
            let amountCents: Int
            let spentOn: String
            let payerId: String
            let participantIds: [String]
            let isSettlement: Bool
            let splitKind: String
            let splitValues: [Int]?
        }
        _ = try await call("saveExpense", Request(
            groupId: groupID.key,
            id: expense.id.key,
            title: expense.title,
            amountCents: expense.amountCents,
            spentOn: LocalDay.string(from: expense.date),
            payerId: expense.payerID.key,
            participantIds: expense.participantIDs.map(\.key),
            isSettlement: expense.isSettlement,
            splitKind: expense.split.kind,
            splitValues: expense.splitValues
        ))
    }

    func deleteExpense(_ id: UUID, in groupID: UUID) async throws {
        struct Request: Encodable, Sendable { let groupId: String; let expenseId: String }
        _ = try await call("deleteExpense", Request(groupId: groupID.key, expenseId: id.key))
    }

    // MARK: Joining

    private struct CodeRequest: Encodable, Sendable { let code: String }

    func previewInvite(code: String) async throws -> InvitePreview {
        try await call("previewInvite", CodeRequest(code: code), as: InvitePreview.self)
    }

    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID {
        struct Request: Encodable, Sendable { let code: String; let memberId: String?; let name: String? }
        let response = try await call("joinGroup", Request(code: code, memberId: memberID?.key, name: name), as: GroupRef.self)
        guard let id = UUID(uuidString: response.groupId) else { throw BarteError.server(hint: nil) }
        return id
    }

    // MARK: Payment details

    func fetchPaymentDetails() async throws -> [UserID: PaymentDetails] {
        try await call("paymentDetails", Empty(), as: [String: PaymentDetails].self)
    }

    func savePaymentDetails(_ details: PaymentDetails) async throws {
        _ = try await call("setPaymentDetails", details)
    }

    // MARK: Account

    func deleteAccount(appleAuthorizationCode: String) async throws {
        do {
            try await Auth.auth().revokeToken(withAuthorizationCode: appleAuthorizationCode)
        } catch {
            throw BarteError.appleRevocationFailed
        }
        _ = try await call("deleteAccount", Empty())
        try? Auth.auth().signOut()
    }

    // MARK: Realtime

    /// Listens to my groups and to each group's expenses; the security rules decide what reaches me.
    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard let uid = Auth.auth().currentUser?.uid else {
                continuation.finish()
                return
            }
            let watcher = ChangeWatcher(db: db, onChange: { continuation.yield() })
            watcher.start(uid: uid)
            continuation.onTermination = { _ in watcher.stop() }
        }
    }
}

/// Keeps one listener on my groups and one per group on its expenses, adding and dropping them as
/// groups come and go. Firestore calls back on the main queue; the lock keeps `stop()` safe from anywhere.
private final class ChangeWatcher: @unchecked Sendable {
    private let db: Firestore
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var groupsListener: ListenerRegistration?
    private var expenseListeners: [String: ListenerRegistration] = [:]
    private var stopped = false

    init(db: Firestore, onChange: @escaping @Sendable () -> Void) {
        self.db = db
        self.onChange = onChange
    }

    func start(uid: String) {
        let listener = db.collection("groups").whereField("memberUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.follow(groupIDs: Set(snapshot.documents.map(\.documentID)))
                self.onChange()
            }
        lock.withLock { groupsListener = listener }
    }

    private func follow(groupIDs: Set<String>) {
        lock.withLock {
            guard !stopped else { return }
            for (id, listener) in expenseListeners where !groupIDs.contains(id) {
                listener.remove()
                expenseListeners[id] = nil
            }
            for id in groupIDs where expenseListeners[id] == nil {
                // The first snapshot of a new listener only repeats what the reload fetches anyway.
                var isFirst = true
                expenseListeners[id] = db.collection("groups").document(id).collection("expenses")
                    .addSnapshotListener { [weak self] _, _ in
                        if isFirst { isFirst = false; return }
                        self?.onChange()
                    }
            }
        }
    }

    func stop() {
        lock.withLock {
            stopped = true
            groupsListener?.remove()
            expenseListeners.values.forEach { $0.remove() }
            expenseListeners = [:]
        }
    }
}
