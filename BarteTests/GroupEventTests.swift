import Foundation
import Testing
@testable import Barte

/// How history entries read: who did what, and exactly what changed.
@Suite("History")
struct GroupEventTests {
    private let me = UUID()
    private let ben = UUID()
    private let anna = Member(id: UUID(), name: "Anna", userID: nil)
    private let benMember: Member
    private let group: SplitGroup

    init() {
        benMember = Member(id: UUID(), name: "Ben", userID: ben)
        group = SplitGroup(id: UUID(), name: "Urlaub", currency: "EUR", color: .blue, createdAt: .now,
                           members: [Member(id: UUID(), name: "Dominik", userID: me), benMember, anna], expenses: [])
    }

    /// Amounts use a no-break space before the currency sign, so they never wrap.
    private func plain(_ lines: [String]) -> [String] {
        lines.map { $0.replacing("\u{00A0}", with: " ").replacing("\u{202F}", with: " ") }
    }

    private func snapshot(_ title: String = "Pizza", _ cents: Int = 4200, payer: UUID? = nil, for ids: [UUID]? = nil,
                          day: String = "2026-11-08", settlement: Bool = false) -> GroupEvent.Snapshot {
        GroupEvent.Snapshot(title: title, amountCents: cents, spentOn: day, payerID: payer ?? benMember.id,
                            participantIDs: ids ?? [benMember.id, anna.id], isSettlement: settlement, splitKind: "equal")
    }

    private func event(_ kind: GroupEvent.Kind, by actor: UUID? = nil, name: String = "Ben",
                       old: GroupEvent.Snapshot? = nil, new: GroupEvent.Snapshot? = nil) -> GroupEvent {
        GroupEvent(id: UUID(), kind: kind, actorID: actor ?? ben, actorName: name, subjectID: UUID(), old: old, new: new, createdAt: .now)
    }

    @Test func joiningAndLeavingAreLogged() {
        let joined = event(.memberJoined, new: .init(name: "Ben")).text(in: group, userID: me)
        #expect(joined.headline == "Ben ist der Gruppe beigetreten")
        let claimed = event(.memberJoined, old: .init(name: "Benni"), new: .init(name: "Ben"))
        #expect(claimed.text(in: group, userID: me).headline == "Ben ist beigetreten und hat „Benni“ übernommen")
        #expect(claimed.isNotable)
        #expect(!event(.memberJoined, new: .init(name: "Ben")).isNotable)
        #expect(event(.memberJoined, by: me, new: .init(name: "Dominik")).text(in: group, userID: me).headline == "Du bist der Gruppe beigetreten")
        #expect(event(.memberLeft, old: .init(name: "Ben")).text(in: group, userID: me).headline == "Ben hat die Gruppe verlassen")
        #expect(GroupEvent.Kind(rawValue: "member_left") == .memberLeft)
    }

    @Test func deletedExpensesCanBeRestored() throws {
        var old = snapshot("Pizza", 4500, for: [benMember.id, anna.id])
        old.splitKind = "shares"
        old.splitValues = [2, 1]
        let deleted = event(.expenseDeleted, old: old)
        let expense = try #require(deleted.restoredExpense(in: group))
        #expect(expense.id == deleted.subjectID)
        #expect(expense.title == "Pizza" && expense.amountCents == 4500 && expense.payerID == benMember.id)
        #expect(expense.split == .shares([benMember.id: 2, anna.id: 1]))
        #expect(LocalDay.string(from: expense.date) == "2026-11-08")
        #expect(!expense.isSettlement)

        // Back in the group, it can't be restored a second time.
        var restored = group
        restored.expenses = [expense]
        #expect(deleted.restoredExpense(in: restored) == nil)

        let settlement = event(.settlementDeleted, old: snapshot("Ausgleich", 1000, for: [anna.id], settlement: true))
        #expect(try #require(settlement.restoredExpense(in: group)).isSettlement)
        #expect(event(.expenseAdded, new: snapshot()).restoredExpense(in: group) == nil)
        #expect(event(.expenseDeleted, old: .init(title: "Pizza")).restoredExpense(in: group) == nil)
    }

    @Test func addedAndDeletedShowWhatItWas() {
        let added = event(.expenseAdded, new: snapshot()).text(in: group, userID: me)
        #expect(added.headline == "Ben hat „Pizza“ eingetragen")
        #expect(plain(added.details) == ["42,00 € · bezahlt von Ben", "für Ben, Anna"])
        let deleted = event(.expenseDeleted, by: me, name: "Dominik", old: snapshot()).text(in: group, userID: me)
        #expect(deleted.headline == "Du hast „Pizza“ gelöscht")
    }

    @Test func editsListEveryChangedField() {
        let old = snapshot("Pasta", 4200, day: "2026-11-07")
        let new = snapshot("Pizza", 2400, payer: anna.id, for: [anna.id])
        let text = event(.expenseChanged, old: old, new: new).text(in: group, userID: me)
        #expect(text.headline == "Ben hat „Pizza“ geändert")
        #expect(plain(text.details) == [
            "Titel: „Pasta“ → „Pizza“",
            "Betrag: 42,00 € → 24,00 €",
            "Bezahlt von: Ben → Anna",
            "Für: Ben, Anna → Anna",
            "Datum: 7. Nov. → 8. Nov.",
        ])
    }

    @Test func everyoneIsAlle() {
        let all = snapshot(for: group.members.map(\.id))
        #expect(event(.expenseAdded, new: all).text(in: group, userID: me).details.last == "für alle")
    }

    @Test func splitChangesWithTheSamePeople() {
        var shares = snapshot()
        shares.splitKind = "shares"
        shares.splitValues = [2, 1]
        let text = event(.expenseChanged, old: snapshot(), new: shares).text(in: group, userID: me)
        #expect(text.details == ["Aufteilung: gleichmäßig → nach Anteilen"])
    }

    @Test func settlementsGroupsAndMembers() {
        let settlement = snapshot("Ausgleich", 2000, payer: anna.id, for: [benMember.id], settlement: true)
        #expect(plain(event(.settlementDeleted, old: settlement).text(in: group, userID: me).details) == ["Anna → Ben · 20,00 €"])
        let renamed = event(.memberRenamed, old: .init(name: "Clara"), new: .init(name: "Klara")).text(in: group, userID: me)
        #expect(renamed.headline == "Ben hat Clara in Klara umbenannt")
        let updated = event(.groupUpdated, old: .init(name: "Urlaub", currency: "EUR"), new: .init(name: "Urlaub", currency: "CHF"))
        #expect(updated.text(in: group, userID: me).details == ["Währung: EUR → CHF"])
        #expect(event(.groupClosed, by: me).text(in: group, userID: me).headline == "Du hast die Gruppe abgeschlossen")
    }

    @Test func removedPeopleAndUnknownActors() {
        let gone = snapshot(payer: UUID())
        #expect(plain(event(.expenseAdded, new: gone).text(in: group, userID: me).details).first == "42,00 € · bezahlt von Entfernte Person")
        let anonymous = GroupEvent(id: UUID(), kind: .groupReopened, actorID: nil, actorName: nil, subjectID: nil, old: nil, new: nil, createdAt: .now)
        #expect(anonymous.text(in: group, userID: me).headline == "Jemand hat die Gruppe wieder geöffnet")
    }

    @Test func snapshotsDecodeFromTheDatabase() throws {
        let json = #"{"title":"Pizza","amount_cents":4200,"spent_on":"2026-11-08","payer_id":"aaaaaaaa-0000-0000-0000-000000000001","participant_ids":["aaaaaaaa-0000-0000-0000-000000000001"],"is_settlement":false,"split_kind":"shares","split_values":[2]}"#
        let snapshot = try JSONDecoder().decode(GroupEvent.Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.amountCents == 4200 && snapshot.splitValues == [2] && snapshot.participantIDs?.count == 1)
    }

    @Test func demoKeepsAHistoryOfChanges() async throws {
        let repository = DemoGroupRepository(groups: [group])
        let expense = Expense(id: UUID(), title: "Taxi", amountCents: 1000, date: .now, payerID: anna.id, participantIDs: [anna.id])
        try await repository.save(expense, in: group.id)
        try await repository.save(expense, in: group.id)  // unchanged: no entry
        var cheaper = expense
        cheaper.amountCents = 800
        try await repository.save(cheaper, in: group.id)
        try await repository.deleteExpense(expense.id)
        let history = try await repository.fetchHistory(groupID: group.id, subjectID: expense.id)
        #expect(history.map(\.kind) == [.expenseDeleted, .expenseChanged, .expenseAdded])
        #expect(try await repository.fetchGroups()[0].editedExpenseIDs.isEmpty, "deleted expenses aren't listed as edited")
    }
}
