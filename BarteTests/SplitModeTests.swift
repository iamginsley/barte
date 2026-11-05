import Foundation
import Testing
@testable import Barte

private let anna = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let ben = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
private let clara = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

@Suite("Unequal splits")
struct SplitModeTests {
    @Test func weightedSplitsProportionally() {
        let shares = Split.weighted(amountCents: 10000, weights: [anna: 2, ben: 1], payer: anna)
        #expect(shares == [anna: 6667, ben: 3333])
    }

    @Test func weightedSharesAlwaysAddUp() {
        let weights = [anna: 3, ben: 2, clara: 7]
        for amount in [0, 1, 7, 99, 1001, 12345, 99_999] {
            let shares = Split.weighted(amountCents: amount, weights: weights, payer: ben)
            #expect(shares.values.reduce(0, +) == amount)
        }
    }

    @Test func weightedTiesGoToThePayerFirst() {
        // 1 cent, three equal weights: everyone has the same remainder, so the payer gets it.
        let shares = Split.weighted(amountCents: 1, weights: [anna: 1, ben: 1, clara: 1], payer: clara)
        #expect(shares[clara] == 1)
        #expect(shares[anna] == 0 && shares[ben] == 0)
    }

    @Test func equalWeightsMatchTheEqualSplit() {
        for amount in [1, 2, 100, 1001] {
            let weighted = Split.weighted(amountCents: amount, weights: [anna: 1, ben: 1, clara: 1], payer: anna)
            let equal = Split.equal(amountCents: amount, participants: [anna, ben, clara], payer: anna)
            #expect(weighted == equal)
        }
    }

    @Test func zeroWeightsAreIgnored() {
        let shares = Split.weighted(amountCents: 900, weights: [anna: 1, ben: 0, clara: 2], payer: anna)
        #expect(shares == [anna: 300, clara: 600])
    }

    @Test func expenseUsesItsSplit() {
        let exact = Expense(id: UUID(), title: "Skischule", amountCents: 36000, date: .now, payerID: ben,
                            participantIDs: [ben, clara], split: .exact([ben: 24000, clara: 12000]))
        #expect(exact.shares == [ben: 24000, clara: 12000])
        #expect(exact.splitValues == [24000, 12000])

        let couple = Expense(id: UUID(), title: "Essen", amountCents: 9000, date: .now, payerID: anna,
                             participantIDs: [anna, ben], split: .shares([anna: 1, ben: 2]))
        let balances = Balances.compute(members: [anna, ben], expenses: [couple])
        #expect(balances == [anna: 6000, ben: -6000])
    }

    @Test func serverValuesRoundTrip() {
        let mode = SplitMode(kind: "shares", values: [2, 1], participants: [anna, ben])
        #expect(mode == .shares([anna: 2, ben: 1]))
        #expect(SplitMode(kind: "exact", values: [5], participants: [anna, ben]) == .equal)
        #expect(SplitMode(kind: "equal", values: nil, participants: [anna]) == .equal)
    }

    @Test func settlementWorksWithMixedSplits() {
        let expenses = [
            Expense(id: UUID(), title: "A", amountCents: 9000, date: .now, payerID: anna, participantIDs: [anna, ben, clara],
                    split: .shares([anna: 1, ben: 1, clara: 1])),
            Expense(id: UUID(), title: "B", amountCents: 5000, date: .now, payerID: ben, participantIDs: [anna, clara],
                    split: .exact([anna: 1000, clara: 4000])),
        ]
        let balances = Balances.compute(members: [anna, ben, clara], expenses: expenses)
        #expect(balances.values.reduce(0, +) == 0)
        #expect(balances == [anna: 5000, ben: 2000, clara: -7000])
        #expect(Settlement.transfers(for: balances).count == 2)
    }
}

@Suite("Expense editor")
@MainActor
struct ExpenseEditorTests {
    private var group: SplitGroup {
        SplitGroup(id: UUID(), name: "Test", currency: "EUR", color: .blue, createdAt: .now,
                   members: [Member(id: anna, name: "Anna"), Member(id: ben, name: "Ben"), Member(id: clara, name: "Clara")],
                   expenses: [])
    }

    @Test func switchingToExactStartsFromTheEqualShares() {
        let model = ExpenseEditorModel(group: group, expense: nil, me: anna)
        model.amountText = "10"
        model.setMode(.exact)
        #expect(model.exactTexts[anna] == "3,34")
        #expect(model.exactDifference == 0)
        #expect(model.canSave)
    }

    @Test func exactNeedsToAddUp() {
        let model = ExpenseEditorModel(group: group, expense: nil, me: anna)
        model.amountText = "30"
        model.setMode(.exact)
        model.exactTexts = [anna: "5", ben: "10"]
        #expect(model.exactDifference == -1500)
        #expect(!model.canSave)
        model.assignRest(to: clara)
        #expect(model.exactTexts[clara] == "15,00")
        #expect(model.canSave)
        #expect(model.makeExpense()?.participantIDs == [anna, ben, clara])
    }

    @Test func sharesKeepTheSelection() {
        let model = ExpenseEditorModel(group: group, expense: nil, me: anna)
        model.amountText = "40"
        model.toggle(clara)
        model.setMode(.shares)
        model.weights[ben] = 3
        #expect(model.selectedIDs == [anna, ben])
        let expense = model.makeExpense()
        #expect(expense?.split == .shares([anna: 1, ben: 3]))
        #expect(expense?.shares == [anna: 1000, ben: 3000])
    }

    @Test func editingRestoresTheMode() {
        let existing = Expense(id: UUID(), title: "Essen", amountCents: 9000, date: .now, payerID: anna,
                               participantIDs: [anna, ben], split: .shares([anna: 1, ben: 2]))
        let model = ExpenseEditorModel(group: group, expense: existing, me: anna)
        #expect(model.mode == .shares)
        #expect(model.weights[ben] == 2)
        #expect(model.weights[clara] == 0)
    }
}
