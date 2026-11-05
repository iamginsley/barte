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

    @Test func groupLinksRoundTrip() {
        let id = UUID()
        #expect(BarteLink.groupID(from: BarteLink.group(id)) == id)
        #expect(BarteLink.groupID(from: URL(string: "barte://join/ABCD2345")!) == nil)
        #expect(InviteLink.code(from: BarteLink.group(id)) == nil)
    }
}
