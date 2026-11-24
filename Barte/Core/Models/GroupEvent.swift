import Foundation

/// One entry of a group's history (public.group_events). Written by the database, never by the
/// app, and never changed afterwards: what someone changed stays visible to everyone in the group.
struct GroupEvent: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case expenseAdded = "expense_added"
        case expenseChanged = "expense_changed"
        case expenseDeleted = "expense_deleted"
        case settlementAdded = "settlement_added"
        case settlementDeleted = "settlement_deleted"
        case groupUpdated = "group_updated"
        case groupClosed = "group_closed"
        case groupReopened = "group_reopened"
        case memberAdded = "member_added"
        case memberRenamed = "member_renamed"
        case memberRemoved = "member_removed"
        case memberJoined = "member_joined"
        case memberLeft = "member_left"
        case unknown
    }

    /// The row before or after the change. Expenses fill the expense fields, groups and members `name`/`currency`.
    struct Snapshot: Hashable, Sendable, Decodable {
        var title: String?
        var amountCents: Int?
        var spentOn: String?
        var payerID: UUID?
        var participantIDs: [UUID]?
        var isSettlement: Bool?
        var splitKind: String?
        var splitValues: [Int]?
        var name: String?
        var currency: String?

        enum CodingKeys: String, CodingKey {
            case title, name, currency
            case amountCents = "amount_cents"
            case spentOn = "spent_on"
            case payerID = "payer_id"
            case participantIDs = "participant_ids"
            case isSettlement = "is_settlement"
            case splitKind = "split_kind"
            case splitValues = "split_values"
        }
    }

    let id: UUID
    let kind: Kind
    let actorID: UUID?
    let actorName: String?
    let subjectID: UUID?
    let old: Snapshot?
    let new: Snapshot?
    let createdAt: Date
}

// MARK: - Wording

extension GroupEvent {
    /// "Anna hat „Pizza“ geändert", plus one line per detail ("Betrag: 42,00 € → 24,00 €"), in the device language.
    struct Wording: Equatable {
        let headline: String
        let details: [String]
    }

    func text(in group: SplitGroup, userID: UUID?) -> Wording {
        let mine = actorID != nil && actorID == userID
        let actor = actorName ?? String(localized: "Jemand", comment: "History: unknown person who made a change")
        let money = { (cents: Int?) in cents.map { Money.format($0, currency: group.currency) } ?? "?" }
        let name = { (id: UUID?) in id.flatMap { group.member($0)?.name } ?? String(localized: "Entfernte Person") }
        let names = { (ids: [UUID]?) in
            let ids = ids ?? []
            return group.members.count > 2 && Set(ids) == Set(group.members.map(\.id))
                ? String(localized: "alle", comment: "History: an expense for everyone in the group")
                : ids.map(name).joined(separator: ", ")
        }
        let quoted = { (title: String?) in String(localized: "„\(title ?? "?")“", comment: "A quoted expense title") }
        let someone = String(localized: "jemanden", comment: "History: an unnamed person was added or removed")

        /// Amount, who paid and for whom: what an expense was.
        func summary(_ s: Snapshot?) -> [String] {
            guard let s else { return [] }
            if s.isSettlement == true {
                return ["\(name(s.payerID)) → \(name(s.participantIDs?.first)) · \(money(s.amountCents))"]
            }
            return [
                String(localized: "\(money(s.amountCents)) · bezahlt von \(name(s.payerID))"),
                String(localized: "für \(names(s.participantIDs))", comment: "History: for whom an expense was"),
            ]
        }

        switch kind {
        case .expenseAdded:
            let title = quoted(new?.title)
            return Wording(headline: mine ? String(localized: "Du hast \(title) eingetragen") : String(localized: "\(actor) hat \(title) eingetragen"),
                           details: summary(new))
        case .expenseDeleted:
            let title = quoted(old?.title)
            return Wording(headline: mine ? String(localized: "Du hast \(title) gelöscht") : String(localized: "\(actor) hat \(title) gelöscht"),
                           details: summary(old))
        case .settlementAdded:
            return Wording(headline: mine ? String(localized: "Du hast einen Ausgleich verbucht") : String(localized: "\(actor) hat einen Ausgleich verbucht"),
                           details: summary(new))
        case .settlementDeleted:
            return Wording(headline: mine ? String(localized: "Du hast einen Ausgleich gelöscht") : String(localized: "\(actor) hat einen Ausgleich gelöscht"),
                           details: summary(old))
        case .expenseChanged:
            guard let old, let new else {
                return Wording(headline: mine ? String(localized: "Du hast eine Ausgabe geändert") : String(localized: "\(actor) hat eine Ausgabe geändert"),
                               details: [])
            }
            var details: [String] = []
            if old.title != new.title { details.append(String(localized: "Titel: \(quoted(old.title)) → \(quoted(new.title))")) }
            if old.amountCents != new.amountCents { details.append(String(localized: "Betrag: \(money(old.amountCents)) → \(money(new.amountCents))")) }
            if old.payerID != new.payerID { details.append(String(localized: "Bezahlt von: \(name(old.payerID)) → \(name(new.payerID))")) }
            if Set(old.participantIDs ?? []) != Set(new.participantIDs ?? []) {
                details.append(String(localized: "Für: \(names(old.participantIDs)) → \(names(new.participantIDs))"))
            } else if old.splitKind != new.splitKind || old.splitValues != new.splitValues {
                details.append(String(localized: "Aufteilung: \(splitName(old.splitKind)) → \(splitName(new.splitKind))"))
            }
            if old.spentOn != new.spentOn { details.append(String(localized: "Datum: \(day(old.spentOn)) → \(day(new.spentOn))")) }
            let title = quoted(new.title)
            return Wording(headline: mine ? String(localized: "Du hast \(title) geändert") : String(localized: "\(actor) hat \(title) geändert"),
                           details: details)
        case .groupUpdated:
            var details: [String] = []
            if old?.name != new?.name { details.append(String(localized: "Name: \(old?.name ?? "?") → \(new?.name ?? "?")")) }
            if old?.currency != new?.currency { details.append(String(localized: "Währung: \(old?.currency ?? "?") → \(new?.currency ?? "?")")) }
            return Wording(headline: mine ? String(localized: "Du hast die Gruppe bearbeitet") : String(localized: "\(actor) hat die Gruppe bearbeitet"),
                           details: details)
        case .groupClosed:
            return Wording(headline: mine ? String(localized: "Du hast die Gruppe abgeschlossen") : String(localized: "\(actor) hat die Gruppe abgeschlossen"),
                           details: [])
        case .groupReopened:
            return Wording(headline: mine ? String(localized: "Du hast die Gruppe wieder geöffnet") : String(localized: "\(actor) hat die Gruppe wieder geöffnet"),
                           details: [])
        case .memberAdded:
            let person = new?.name ?? someone
            return Wording(headline: mine ? String(localized: "Du hast \(person) hinzugefügt") : String(localized: "\(actor) hat \(person) hinzugefügt"),
                           details: [])
        case .memberRenamed:
            let from = old?.name ?? "?", to = new?.name ?? "?"
            return Wording(headline: mine ? String(localized: "Du hast \(from) in \(to) umbenannt") : String(localized: "\(actor) hat \(from) in \(to) umbenannt"),
                           details: [])
        case .memberRemoved:
            let person = old?.name ?? someone
            return Wording(headline: mine ? String(localized: "Du hast \(person) entfernt") : String(localized: "\(actor) hat \(person) entfernt"),
                           details: [])
        case .memberJoined:
            let person = new?.name ?? actor
            // Taking over a typed-in name takes over its expenses too, so it says whose.
            if let claimed = old?.name {
                return Wording(headline: mine ? String(localized: "Du bist beigetreten und hast „\(claimed)“ übernommen")
                                              : String(localized: "\(person) ist beigetreten und hat „\(claimed)“ übernommen"),
                               details: [])
            }
            return Wording(headline: mine ? String(localized: "Du bist der Gruppe beigetreten") : String(localized: "\(person) ist der Gruppe beigetreten"),
                           details: [])
        case .memberLeft:
            let person = old?.name ?? actor
            return Wording(headline: mine ? String(localized: "Du hast die Gruppe verlassen") : String(localized: "\(person) hat die Gruppe verlassen"),
                           details: [])
        case .unknown:
            return Wording(headline: mine ? String(localized: "Du hast etwas geändert") : String(localized: "\(actor) hat etwas geändert"),
                           details: [])
        }
    }

    private func splitName(_ kind: String?) -> String {
        switch kind {
        case "shares": String(localized: "nach Anteilen", comment: "History: split kind")
        case "exact": String(localized: "feste Beträge", comment: "History: split kind")
        default: String(localized: "gleichmäßig", comment: "History: split kind")
        }
    }

    private func day(_ text: String?) -> String {
        guard let text, let date = LocalDay.date(from: text) else { return "?" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// SF Symbol for the history list.
    var symbol: String {
        switch kind {
        case .expenseAdded: "plus"
        case .expenseChanged: "pencil"
        case .expenseDeleted, .settlementDeleted, .memberRemoved: "trash"
        case .settlementAdded: "arrow.left.arrow.right"
        case .groupUpdated, .memberRenamed: "character.cursor.ibeam"
        case .groupClosed: "archivebox"
        case .groupReopened: "arrow.uturn.backward"
        case .memberAdded, .memberJoined: "person.badge.plus"
        case .memberLeft: "rectangle.portrait.and.arrow.right"
        case .unknown: "clock"
        }
    }

    /// Deletions and edits are what someone else might want to double-check.
    var isNotable: Bool {
        [.expenseChanged, .expenseDeleted, .settlementDeleted].contains(kind) || (kind == .memberJoined && old?.name != nil)
    }

    /// A deleted expense or settlement as it was, to save again under its old id. Nil for anything
    /// else, when the snapshot is incomplete, or when it still exists (restored or never gone).
    func restoredExpense(in group: SplitGroup) -> Expense? {
        guard kind == .expenseDeleted || kind == .settlementDeleted, let subjectID, let old,
              !group.expenses.contains(where: { $0.id == subjectID }),
              let title = old.title, let amount = old.amountCents, let payer = old.payerID,
              let participants = old.participantIDs, !participants.isEmpty,
              let spentOn = old.spentOn, let date = LocalDay.date(from: spentOn) else { return nil }
        return Expense(id: subjectID, title: title, amountCents: amount, date: date, payerID: payer,
                       participantIDs: participants, isSettlement: old.isSettlement ?? (kind == .settlementDeleted),
                       split: SplitMode(kind: old.splitKind ?? "equal", values: old.splitValues, participants: participants))
    }
}
