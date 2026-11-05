import Foundation

/// Card colors a group can have. Stored as an index, so the order must never change.
enum CardColor: Int, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, green, teal, graphite

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .blue: "Blau"
        case .indigo: "Indigo"
        case .purple: "Lila"
        case .pink: "Pink"
        case .red: "Rot"
        case .orange: "Orange"
        case .green: "Grün"
        case .teal: "Türkis"
        case .graphite: "Graphit"
        }
    }
}

/// A group of people sharing expenses, as the UI sees it.
struct SplitGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var currency: String
    var color: CardColor
    var createdAt: Date
    /// Ordered by when they joined the group.
    var members: [Member]
    /// Newest first.
    var expenses: [Expense]
    var inviteCode: String = ""
    var createdBy: UUID? = nil

    var balances: [UUID: Int] { Balances.compute(members: members.map(\.id), expenses: expenses) }

    func balance(of memberID: UUID?) -> Int {
        guard let memberID else { return 0 }
        return balances[memberID] ?? 0
    }

    var transfers: [Transfer] { Settlement.transfers(for: balances) }
    var isSettled: Bool { balances.values.allSatisfy { $0 == 0 } }

    /// Sum of real expenses, without paybacks.
    var totalSpent: Int { expenses.filter { !$0.isSettlement }.reduce(0) { $0 + $1.amountCents } }

    func member(_ id: UUID) -> Member? { members.first { $0.id == id } }

    /// The member linked to this person.
    func me(userID: UUID?) -> UUID? {
        guard let userID else { return nil }
        return members.first { $0.userID == userID }?.id
    }

    /// More than one person uses the app in this group.
    var isShared: Bool { members.filter(\.usesApp).count > 1 }

    /// The creator deletes for everyone; so does the last person with the app. Everyone else leaves.
    func canDelete(userID: UUID?) -> Bool {
        guard let userID else { return false }
        return createdBy == userID || !members.contains { $0.usesApp && $0.userID != userID }
    }

    func name(of id: UUID, me: UUID?) -> String {
        id == me ? "Du" : member(id)?.name ?? "Unbekannt"
    }

    /// Whether a member appears in any expense (then they cannot be removed).
    func isInvolved(_ memberID: UUID) -> Bool {
        expenses.contains { $0.payerID == memberID || $0.participantIDs.contains(memberID) }
    }
}
