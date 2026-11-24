import Foundation
import Testing
@testable import Barte

/// Reminding someone who owes me: a push through Barte, or a message for people without the app.
@Suite("Reminders")
struct ReminderTests {
    let me = UUID()
    let ben = UUID()

    /// I paid 60 € for me, Ben (with the app) and Clara (without): both owe me 20 €.
    private func group() -> SplitGroup {
        let members = [Member(id: UUID(), name: "Ich", userID: me), Member(id: UUID(), name: "Ben", userID: ben), Member(id: UUID(), name: "Clara")]
        return SplitGroup(id: UUID(), name: "Urlaub", currency: "EUR", color: .blue, createdAt: .now, members: members,
                          expenses: [Expense(id: UUID(), title: "Hütte", amountCents: 6000, date: .now, payerID: members[0].id, participantIDs: members.map(\.id))])
    }

    @Test func messageForPeopleWithoutTheApp() {
        let text = Reminder.message(to: "Clara", group: "Urlaub", amount: "20,00 €", paypal: nil)
        #expect(text == "Hallo Clara, kleine Erinnerung: Für „Urlaub“ sind noch 20,00 € an mich offen.")
        let paypal = URL(string: "https://paypal.me/dominik/20.00EUR")!
        #expect(Reminder.message(to: "Clara", group: "Urlaub", amount: "20,00 €", paypal: paypal).hasSuffix("\nPer PayPal: https://paypal.me/dominik/20.00EUR"))
    }

    @Test func demoRemindsOnceAndOnlyWhoOwes() async throws {
        let group = group()
        let repository = DemoGroupRepository(groups: [group])
        let (mine, benMember, clara) = (group.members[0].id, group.members[1].id, group.members[2].id)
        try await repository.remind(benMember, amountCents: 2000, in: group.id)
        await #expect(throws: BarteError.server(hint: "reminded_recently")) { try await repository.remind(benMember, amountCents: 2000, in: group.id) }
        await #expect(throws: BarteError.server(hint: "no_app")) { try await repository.remind(clara, amountCents: 2000, in: group.id) }
        await #expect(throws: BarteError.self) { try await repository.remind(mine, amountCents: 2000, in: group.id) }
    }
}
