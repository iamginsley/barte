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
    /// "Anna hat „Pizza“ geändert", plus one line per detail ("Betrag: 42,00 € → 24,00 €").
    struct Wording: Equatable {
        let headline: String
        let details: [String]
    }

    func text(in group: SplitGroup, userID: UUID?) -> Wording {
        let who = actorID != nil && actorID == userID ? "Du hast" : "\(actorName ?? "Jemand") hat"
        let money = { (cents: Int?) in cents.map { Money.format($0, currency: group.currency) } ?? "?" }
        let name = { (id: UUID?) in id.flatMap { group.member($0)?.name } ?? "Entfernte Person" }
        let names = { (ids: [UUID]?) in
            let ids = ids ?? []
            return group.members.count > 2 && Set(ids) == Set(group.members.map(\.id)) ? "alle" : ids.map(name).joined(separator: ", ")
        }
        let quoted = { (title: String?) in "„\(title ?? "?")“" }

        /// Amount, who paid and for whom: what an expense was.
        func summary(_ s: Snapshot?) -> [String] {
            guard let s else { return [] }
            if s.isSettlement == true {
                return ["\(name(s.payerID)) → \(name(s.participantIDs?.first)) · \(money(s.amountCents))"]
            }
            return ["\(money(s.amountCents)) · bezahlt von \(name(s.payerID))", "für \(names(s.participantIDs))"]
        }

        switch kind {
        case .expenseAdded:
            return Wording(headline: "\(who) \(quoted(new?.title)) eingetragen", details: summary(new))
        case .expenseDeleted:
            return Wording(headline: "\(who) \(quoted(old?.title)) gelöscht", details: summary(old))
        case .settlementAdded:
            return Wording(headline: "\(who) einen Ausgleich verbucht", details: summary(new))
        case .settlementDeleted:
            return Wording(headline: "\(who) einen Ausgleich gelöscht", details: summary(old))
        case .expenseChanged:
            guard let old, let new else { return Wording(headline: "\(who) eine Ausgabe geändert", details: []) }
            var details: [String] = []
            if old.title != new.title { details.append("Titel: \(quoted(old.title)) → \(quoted(new.title))") }
            if old.amountCents != new.amountCents { details.append("Betrag: \(money(old.amountCents)) → \(money(new.amountCents))") }
            if old.payerID != new.payerID { details.append("Bezahlt von: \(name(old.payerID)) → \(name(new.payerID))") }
            if Set(old.participantIDs ?? []) != Set(new.participantIDs ?? []) {
                details.append("Für: \(names(old.participantIDs)) → \(names(new.participantIDs))")
            } else if old.splitKind != new.splitKind || old.splitValues != new.splitValues {
                details.append("Aufteilung: \(splitName(old.splitKind)) → \(splitName(new.splitKind))")
            }
            if old.spentOn != new.spentOn { details.append("Datum: \(day(old.spentOn)) → \(day(new.spentOn))") }
            return Wording(headline: "\(who) \(quoted(new.title)) geändert", details: details)
        case .groupUpdated:
            var details: [String] = []
            if old?.name != new?.name { details.append("Name: \(old?.name ?? "?") → \(new?.name ?? "?")") }
            if old?.currency != new?.currency { details.append("Währung: \(old?.currency ?? "?") → \(new?.currency ?? "?")") }
            return Wording(headline: "\(who) die Gruppe bearbeitet", details: details)
        case .groupClosed:
            return Wording(headline: "\(who) die Gruppe abgeschlossen", details: [])
        case .groupReopened:
            return Wording(headline: "\(who) die Gruppe wieder geöffnet", details: [])
        case .memberAdded:
            return Wording(headline: "\(who) \(new?.name ?? "jemanden") hinzugefügt", details: [])
        case .memberRenamed:
            return Wording(headline: "\(who) \(old?.name ?? "?") in \(new?.name ?? "?") umbenannt", details: [])
        case .memberRemoved:
            return Wording(headline: "\(who) \(old?.name ?? "jemanden") entfernt", details: [])
        case .unknown:
            return Wording(headline: "\(who) etwas geändert", details: [])
        }
    }

    private func splitName(_ kind: String?) -> String {
        switch kind {
        case "shares": "nach Anteilen"
        case "exact": "feste Beträge"
        default: "gleichmäßig"
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
        case .memberAdded: "person.badge.plus"
        case .unknown: "clock"
        }
    }

    /// Deletions and edits are what someone else might want to double-check.
    var isNotable: Bool { [.expenseChanged, .expenseDeleted, .settlementDeleted].contains(kind) }
}
