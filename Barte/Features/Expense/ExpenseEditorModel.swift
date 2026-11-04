import Foundation
import Observation

/// Form state for adding or editing an expense, split equally among the selected people.
@Observable
@MainActor
final class ExpenseEditorModel {
    let group: SplitGroup
    let existing: Expense?
    let me: UUID?

    var amountText: String
    var title: String
    var payerID: UUID
    var participants: Set<UUID>
    var date: Date

    init(group: SplitGroup, expense: Expense?, me: UUID?) {
        self.group = group
        existing = expense
        self.me = me
        amountText = expense.map { Money.editString($0.amountCents) } ?? ""
        title = expense?.title ?? ""
        payerID = expense?.payerID ?? me ?? group.members.first?.id ?? UUID()
        participants = Set(expense?.participantIDs ?? group.members.map(\.id))
        date = expense?.date ?? .now
    }

    var amountCents: Int? { Money.parse(amountText) }

    var canSave: Bool { (amountCents ?? 0) > 0 && !participants.isEmpty && group.member(payerID) != nil }

    var allSelected: Bool { participants.count == group.members.count }

    /// What each selected person pays, live while typing.
    var shares: [UUID: Int] {
        Split.equal(amountCents: amountCents ?? 0, participants: Array(participants), payer: payerID)
    }

    var perPersonText: String? {
        guard let amount = amountCents, amount > 0, !participants.isEmpty else { return nil }
        let values = Set(shares.values)
        let text = Money.format(amount / participants.count, currency: group.currency)
        return values.count == 1 ? "Je \(text) pro Person" : "Je etwa \(text) pro Person, Cent-Reste trägt die zahlende Person"
    }

    func toggle(_ id: UUID) {
        if participants.contains(id) { participants.remove(id) } else { participants.insert(id) }
    }

    func toggleAll() {
        participants = allSelected ? [] : Set(group.members.map(\.id))
    }

    func makeExpense() -> Expense? {
        guard canSave, let amount = amountCents else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return Expense(
            id: existing?.id ?? UUID(),
            title: trimmed.isEmpty ? "Ausgabe" : trimmed,
            amountCents: amount,
            date: date,
            payerID: payerID,
            participantIDs: group.members.map(\.id).filter(participants.contains)
        )
    }
}
