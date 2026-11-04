@preconcurrency import CloudKit
@preconcurrency import CoreData
import Foundation

/// Reads and writes groups, members and expenses. Hands out value snapshots so views never touch
/// managed objects; every write saves right away and CloudKit syncs it in the background.
@MainActor
final class GroupRepository {
    enum Failure: LocalizedError {
        case memberInvolved
        var errorDescription: String? {
            "Diese Person kommt in Ausgaben vor und kann nicht entfernt werden."
        }
    }

    let persistence: Persistence
    private var context: NSManagedObjectContext { persistence.context }

    init(persistence: Persistence) {
        self.persistence = persistence
    }

    // MARK: Reading

    func fetchGroups() -> [SplitGroup] {
        let request = GroupEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GroupEntity.createdAt, ascending: false)]
        let entities = (try? context.fetch(request)) ?? []
        let shared = Set(persistence.shares(for: entities.map(\.objectID)).keys)
        return entities.compactMap { entity in
            guard var group = Self.snapshot(of: entity) else { return nil }
            if persistence.isInSharedStore(entity) {
                group.sharing = .participant
            } else if shared.contains(entity.objectID) {
                group.sharing = .owner
            }
            return group
        }
    }

    private static func snapshot(of entity: GroupEntity) -> SplitGroup? {
        guard let id = entity.id else { return nil }
        let memberEntities = (entity.members as? Set<MemberEntity> ?? [])
            .sorted { ($0.createdAt ?? .distantPast, $0.id?.uuidString ?? "") < ($1.createdAt ?? .distantPast, $1.id?.uuidString ?? "") }
        let members = memberEntities.compactMap { member -> Member? in
            guard let id = member.id else { return nil }
            return Member(id: id, name: member.name ?? "")
        }
        let memberIDs = Set(members.map(\.id))
        // Records can arrive from CloudKit in any order; skip expenses whose people haven't synced yet.
        let expenses = (entity.expenses as? Set<ExpenseEntity> ?? []).compactMap { expense -> Expense? in
            guard let id = expense.id, let payer = expense.payer?.id, memberIDs.contains(payer) else { return nil }
            let participants = (expense.participants as? Set<MemberEntity> ?? []).compactMap(\.id).filter(memberIDs.contains)
            guard !participants.isEmpty else { return nil }
            return Expense(
                id: id,
                title: expense.title ?? "",
                amountCents: Int(expense.amountCents),
                date: expense.date ?? expense.createdAt ?? .now,
                payerID: payer,
                participantIDs: participants.sorted { $0.uuidString < $1.uuidString },
                isSettlement: expense.isSettlement
            )
        }
        .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }

        return SplitGroup(
            id: id,
            name: entity.name ?? "",
            currency: entity.currencyCode ?? "EUR",
            color: CardColor(rawValue: Int(entity.colorIndex)) ?? .blue,
            createdAt: entity.createdAt ?? .now,
            members: members,
            expenses: expenses
        )
    }

    // MARK: Groups

    /// Creates a group. The first name is "me" on this device.
    @discardableResult
    func createGroup(name: String, currency: String, color: CardColor, memberNames: [String]) -> UUID {
        let group = GroupEntity(context: context)
        if let store = persistence.privateStore { context.assign(group, to: store) }
        let id = UUID()
        group.id = id
        group.name = name.trimmingCharacters(in: .whitespaces)
        group.currencyCode = currency
        group.colorIndex = Int16(color.rawValue)
        group.createdAt = .now
        var first: UUID?
        for (offset, memberName) in memberNames.enumerated() {
            let memberID = insertMember(named: memberName, into: group, order: offset)
            if first == nil { first = memberID }
        }
        persistence.save()
        Identity.setMe(first, in: id)
        return id
    }

    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) {
        guard let group = groupEntity(id) else { return }
        group.name = name.trimmingCharacters(in: .whitespaces)
        group.currencyCode = currency
        group.colorIndex = Int16(color.rawValue)
        persistence.save()
    }

    /// Deletes a group this person owns, or leaves one that was shared with them.
    func deleteGroup(_ id: UUID) {
        guard let group = groupEntity(id) else { return }
        if persistence.isInSharedStore(group) {
            persistence.leave(group)
        } else {
            context.delete(group)
            persistence.save()
        }
        Identity.setMe(nil, in: id)
    }

    func share(for groupID: UUID) async throws -> CKShare? {
        guard let group = groupEntity(groupID) else { return nil }
        return try await persistence.share(for: group)
    }

    // MARK: Members

    @discardableResult
    func addMember(named name: String, to groupID: UUID) -> UUID? {
        guard let group = groupEntity(groupID) else { return nil }
        let id = insertMember(named: name, into: group, order: group.members?.count ?? 0)
        persistence.save()
        return id
    }

    func renameMember(_ id: UUID, to name: String) {
        guard let member = entity(MemberEntity.self, id: id) else { return }
        member.name = name.trimmingCharacters(in: .whitespaces)
        persistence.save()
    }

    func removeMember(_ id: UUID) throws {
        guard let member = entity(MemberEntity.self, id: id) else { return }
        guard (member.paidExpenses?.count ?? 0) == 0, (member.sharedExpenses?.count ?? 0) == 0 else {
            throw Failure.memberInvolved
        }
        context.delete(member)
        persistence.save()
    }

    private func insertMember(named name: String, into group: GroupEntity, order: Int) -> UUID {
        let member = MemberEntity(context: context)
        if let store = group.objectID.persistentStore { context.assign(member, to: store) }
        let id = UUID()
        member.id = id
        member.name = name.trimmingCharacters(in: .whitespaces)
        // Spaced by milliseconds so members created together keep their order.
        member.createdAt = Date.now.addingTimeInterval(Double(order) / 1000)
        member.group = group
        return id
    }

    // MARK: Expenses

    /// Inserts or updates an expense.
    func save(_ expense: Expense, in groupID: UUID) {
        guard let group = groupEntity(groupID) else { return }
        let entity: ExpenseEntity
        if let existing = self.entity(ExpenseEntity.self, id: expense.id) {
            entity = existing
        } else {
            entity = ExpenseEntity(context: context)
            if let store = group.objectID.persistentStore { context.assign(entity, to: store) }
            entity.id = expense.id
            entity.createdAt = .now
            entity.group = group
        }
        let members = (group.members as? Set<MemberEntity>) ?? []
        entity.title = expense.title.trimmingCharacters(in: .whitespaces)
        entity.amountCents = Int64(expense.amountCents)
        entity.date = expense.date
        entity.isSettlement = expense.isSettlement
        entity.payer = members.first { $0.id == expense.payerID }
        entity.participants = NSSet(set: members.filter { member in member.id.map(expense.participantIDs.contains) ?? false })
        persistence.save()
    }

    func deleteExpense(_ id: UUID) {
        guard let expense = entity(ExpenseEntity.self, id: id) else { return }
        context.delete(expense)
        persistence.save()
    }

    // MARK: Lookup

    private func groupEntity(_ id: UUID) -> GroupEntity? { entity(GroupEntity.self, id: id) }

    private func entity<T: NSManagedObject>(_ type: T.Type, id: UUID) -> T? {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
