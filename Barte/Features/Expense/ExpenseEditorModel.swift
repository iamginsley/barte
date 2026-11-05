import Foundation
import Observation

/// Form state for adding or editing an expense: equally, by shares, or with fixed amounts per person.
@Observable
@MainActor
final class ExpenseEditorModel {
    enum Mode: String, CaseIterable, Identifiable {
        case equal, shares, exact

        var id: String { rawValue }

        var title: String {
            switch self {
            case .equal: "Gleich"
            case .shares: "Anteile"
            case .exact: "Beträge"
            }
        }
    }

    static let maxWeight = 20

    let group: SplitGroup
    let existing: Expense?
    let me: UUID?

    var amountText: String
    var title: String
    var payerID: UUID
    var date: Date
    private(set) var mode: Mode

    /// Who shares the expense in equal mode.
    var participants: Set<UUID>
    /// Weights in shares mode; 0 means not part of it.
    var weights: [UUID: Int]
    /// Typed amounts in exact mode.
    var exactTexts: [UUID: String]

    init(group: SplitGroup, expense: Expense?, me: UUID?) {
        self.group = group
        existing = expense
        self.me = me
        amountText = expense.map { Money.editString($0.amountCents) } ?? ""
        title = expense?.title ?? ""
        payerID = expense?.payerID ?? me ?? group.members.first?.id ?? UUID()
        date = expense?.date ?? .now
        let selected = Set(expense?.participantIDs ?? group.members.map(\.id))
        participants = selected
        weights = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, selected.contains($0.id) ? 1 : 0) })
        exactTexts = [:]
        switch expense?.split ?? .equal {
        case .equal:
            mode = .equal
        case .shares(let values):
            mode = .shares
            for (id, weight) in values { weights[id] = weight }
        case .exact(let values):
            mode = .exact
            exactTexts = values.filter { $0.value > 0 }.mapValues(Money.editString)
        }
    }

    var amountCents: Int? { Money.parse(amountText) }

    /// The people who pay part of this expense, in group order.
    var selectedIDs: [UUID] {
        group.members.map(\.id).filter { id in
            switch mode {
            case .equal: participants.contains(id)
            case .shares: (weights[id] ?? 0) > 0
            case .exact: (exactCents(id) ?? 0) > 0
            }
        }
    }

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    var allSelected: Bool { participants.count == group.members.count }

    func exactCents(_ id: UUID) -> Int? { exactTexts[id].flatMap(Money.parse) }

    /// Sum of the typed amounts in exact mode.
    var exactTotal: Int { group.members.reduce(0) { $0 + (exactCents($1.id) ?? 0) } }

    /// Typed amounts minus the total: negative while something is missing.
    var exactDifference: Int? {
        guard mode == .exact, let amount = amountCents else { return nil }
        return exactTotal - amount
    }

    var split: SplitMode {
        switch mode {
        case .equal: .equal
        case .shares: .shares(weights.filter { $0.value > 0 })
        case .exact: .exact(Dictionary(uniqueKeysWithValues: selectedIDs.map { ($0, exactCents($0) ?? 0) }))
        }
    }

    var canSave: Bool {
        guard (amountCents ?? 0) > 0, !selectedIDs.isEmpty, group.member(payerID) != nil else { return false }
        if mode == .exact { return exactDifference == 0 }
        return true
    }

    /// What each selected person pays, live while typing.
    var shares: [UUID: Int] { draft.shares }

    private var draft: Expense {
        Expense(id: existing?.id ?? UUID(), title: title, amountCents: amountCents ?? 0, date: date,
                payerID: payerID, participantIDs: selectedIDs, split: split)
    }

    var footerText: String? {
        guard selectedIDs.isEmpty == false else { return "Wähle mindestens eine Person aus." }
        guard let amount = amountCents, amount > 0 else { return nil }
        switch mode {
        case .equal:
            let values = Set(shares.values)
            let text = Money.format(amount / selectedIDs.count, currency: group.currency)
            return values.count == 1 ? "Je \(text) pro Person" : "Je etwa \(text) pro Person, Cent-Reste trägt die zahlende Person"
        case .shares:
            let total = weights.values.filter { $0 > 0 }.reduce(0, +)
            let perShare = Money.format(amount / total, currency: group.currency)
            return "\(total) Anteile, etwa \(perShare) pro Anteil. Ein Paar zählt zum Beispiel doppelt."
        case .exact:
            guard let difference = exactDifference else { return nil }
            if difference == 0 { return "Passt genau." }
            let text = Money.format(abs(difference), currency: group.currency)
            return difference < 0 ? "Noch \(text) zu verteilen." : "\(text) zu viel verteilt."
        }
    }

    // MARK: Editing

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        let current = Set(selectedIDs)
        let currentShares = shares
        switch newMode {
        case .equal:
            participants = current
        case .shares:
            for member in group.members {
                let weight = weights[member.id] ?? 0
                weights[member.id] = current.contains(member.id) ? max(weight, 1) : 0
            }
        case .exact:
            // Start from what each person pays now, so only the differences need typing.
            exactTexts = currentShares.filter { $0.value > 0 }.mapValues(Money.editString)
        }
        mode = newMode
    }

    func toggle(_ id: UUID) {
        switch mode {
        case .equal:
            if participants.contains(id) { participants.remove(id) } else { participants.insert(id) }
        case .shares:
            weights[id] = (weights[id] ?? 0) > 0 ? 0 : 1
        case .exact:
            break
        }
    }

    func toggleAll() {
        participants = allSelected ? [] : Set(group.members.map(\.id))
    }

    /// Puts what's still missing on this person (or takes off what's too much).
    func assignRest(to id: UUID) {
        guard let difference = exactDifference else { return }
        let value = max(0, (exactCents(id) ?? 0) - difference)
        exactTexts[id] = value > 0 ? Money.editString(value) : ""
    }

    func makeExpense() -> Expense? {
        guard canSave else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        var expense = draft
        expense.title = trimmed.isEmpty ? "Ausgabe" : trimmed
        return expense
    }
}
