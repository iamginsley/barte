import Foundation
import Testing
@testable import Barte

@Suite("Widget and links")
struct WidgetAndLinkTests {
    private let me = UUID()

    private func group(_ name: String, currency: String = "EUR", myShare: Int, color: CardColor = .blue) -> SplitGroup {
        let mine = Member(id: UUID(), name: "Ich", userID: me)
        let other = Member(id: UUID(), name: "Anna")
        // I paid 2 × myShare for both of us, so I get myShare back (negative: Anna paid).
        let payer = myShare >= 0 ? mine.id : other.id
        let expense = Expense(id: UUID(), title: "X", amountCents: abs(myShare) * 2, date: .now, payerID: payer, participantIDs: [mine.id, other.id])
        return SplitGroup(id: UUID(), name: name, currency: currency, color: color, createdAt: .now,
                          members: [mine, other], expenses: myShare == 0 ? [] : [expense])
    }

    @Test func totalsPerCurrencyAndLargestGroupsFirst() {
        let snapshot = WidgetSync.makeSnapshot(groups: [
            group("Ski", myShare: 6500),
            group("WG", myShare: -2500, color: .indigo),
            group("Quitt", myShare: 0),
            group("London", currency: "GBP", myShare: 1000),
        ], userID: me)
        #expect(snapshot.totals == [.init(currency: "EUR", cents: 4000), .init(currency: "GBP", cents: 1000)])
        #expect(snapshot.groups.map(\.name) == ["Ski", "WG", "London"])
        #expect(snapshot.groups[1].color == CardColor.indigo.rawValue)
    }

    @Test func settledShowsNothingOpen() {
        let snapshot = WidgetSync.makeSnapshot(groups: [group("Quitt", myShare: 0)], userID: me)
        #expect(snapshot.totals.isEmpty)
        #expect(snapshot.groups.isEmpty)
    }

    @Test func closedGroupsAreLeftOut() {
        var closed = group("Pizza", myShare: 1200)
        closed.closedAt = .now
        let snapshot = WidgetSync.makeSnapshot(groups: [closed, group("Ski", myShare: 500)], userID: me)
        #expect(snapshot.totals == [.init(currency: "EUR", cents: 500)])
        #expect(snapshot.groups.map(\.name) == ["Ski"])
    }

    @Test func demoExpensesReopenAClosedGroup() async throws {
        var closed = group("Pizza", myShare: 1200)
        closed.closedAt = .now
        let repository = DemoGroupRepository(groups: [closed])
        try await repository.setClosed(true, group: closed.id)
        #expect(try await repository.fetchGroups()[0].closedAt == closed.closedAt, "closing again keeps the date")
        try await repository.deleteExpense(closed.expenses[0].id)
        #expect(try await repository.fetchGroups()[0].isClosed == false)
    }

    @Test func demoClosesOnlyWhenSettledAndRestoresDeletions() async throws {
        let open = group("Pizza", myShare: 1200)
        let repository = DemoGroupRepository(groups: [open])
        await #expect(throws: BarteError.self) { try await repository.setClosed(true, group: open.id) }
        let expense = open.expenses[0]
        try await repository.deleteExpense(expense.id)
        let deleted = try #require(try await repository.fetchHistory(groupID: open.id, subjectID: expense.id).first)
        let groupNow = try await repository.fetchGroups()[0]
        let restored = try #require(deleted.restoredExpense(in: groupNow))
        try await repository.save(restored, in: open.id)
        #expect(try await repository.fetchGroups()[0].expenses.map(\.id) == [expense.id])
    }

    @Test func groupLinksRoundTrip() {
        let id = UUID()
        #expect(BarteLink.groupID(from: BarteLink.group(id)) == id)
        #expect(BarteLink.groupID(from: URL(string: "barte://join/ABCD2345")!) == nil)
        #expect(InviteLink.code(from: BarteLink.group(id)) == nil)
    }
}
