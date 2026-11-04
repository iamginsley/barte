import Foundation
import Testing
@testable import Barte

/// Deterministic member ids so tests read like names.
private enum P {
    static let anna = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let ben = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let clara = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
    static let david = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!
    static let emil = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!
    static let fiona = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
}

private func expense(_ cents: Int, by payer: UUID, for participants: [UUID]) -> Expense {
    Expense(id: UUID(), title: "Test", amountCents: cents, date: .now, payerID: payer, participantIDs: participants)
}

/// Applies transfers to balances; settled balances are all zero.
private func apply(_ transfers: [Transfer], to balances: [UUID: Int]) -> [UUID: Int] {
    var result = balances
    for t in transfers {
        result[t.from, default: 0] += t.amountCents
        result[t.to, default: 0] -= t.amountCents
    }
    return result
}

@Suite("Money")
struct MoneyTests {
    @Test(arguments: [
        ("12", 1200), ("12,5", 1250), ("12,50", 1250), ("1.234,56", 123456),
        ("12.50", 1250), ("12,50 €", 1250), ("0,99", 99), (",5", 50), ("1.000", 100000),
    ])
    func parses(input: String, cents: Int) {
        #expect(Money.parse(input) == cents)
    }

    @Test(arguments: ["", "abc", "1,234", "-5", "1.2.3,4,5"])
    func rejects(input: String) {
        #expect(Money.parse(input) == nil)
    }

    @Test func formatsGerman() {
        #expect(Money.format(123456, currency: "EUR") == "1.234,56\u{00A0}€")
        #expect(Money.editString(1250) == "12,50")
    }
}

@Suite("Split")
struct SplitTests {
    @Test func sharesAddUp() {
        for amount in [0, 1, 2, 99, 100, 1001, 99_999] {
            let shares = Split.equal(amountCents: amount, participants: [P.anna, P.ben, P.clara], payer: P.anna)
            #expect(shares.values.reduce(0, +) == amount)
            #expect(shares.values.max()! - shares.values.min()! <= 1)
        }
    }

    @Test func payerGetsLeftoverCentFirst() {
        let shares = Split.equal(amountCents: 1000, participants: [P.clara, P.ben, P.anna], payer: P.clara)
        #expect(shares == [P.clara: 334, P.anna: 333, P.ben: 333])
    }

    @Test func ignoresDuplicates() {
        let shares = Split.equal(amountCents: 600, participants: [P.anna, P.anna, P.ben], payer: P.anna)
        #expect(shares == [P.anna: 300, P.ben: 300])
    }
}

@Suite("Balances")
struct BalanceTests {
    @Test func equalSplit() {
        let balances = Balances.compute(members: [P.anna, P.ben, P.clara], expenses: [
            expense(9000, by: P.anna, for: [P.anna, P.ben, P.clara]),
        ])
        #expect(balances == [P.anna: 6000, P.ben: -3000, P.clara: -3000])
    }

    @Test func payerNotParticipating() {
        let balances = Balances.compute(members: [P.anna, P.ben], expenses: [
            expense(2000, by: P.anna, for: [P.ben]),
        ])
        #expect(balances == [P.anna: 2000, P.ben: -2000])
    }

    @Test func settlementEvensOut() {
        var expenses = [expense(5000, by: P.anna, for: [P.anna, P.ben])]
        expenses.append(Expense(id: UUID(), title: "Ausgleich", amountCents: 2500, date: .now,
                                payerID: P.ben, participantIDs: [P.anna], isSettlement: true))
        let balances = Balances.compute(members: [P.anna, P.ben], expenses: expenses)
        #expect(balances.values.allSatisfy { $0 == 0 })
    }

    @Test func alwaysSumsToZero() {
        var generator = SeededGenerator(seed: 7)
        let people = [P.anna, P.ben, P.clara, P.david]
        let expenses = (0..<200).map { _ in
            expense(Int.random(in: 1...50_000, using: &generator),
                    by: people.randomElement(using: &generator)!,
                    for: Array(people.shuffled(using: &generator).prefix(Int.random(in: 1...4, using: &generator))))
        }
        #expect(Balances.compute(members: people, expenses: expenses).values.reduce(0, +) == 0)
    }
}

@Suite("Settlement")
struct SettlementTests {
    @Test func evenGroupNeedsNothing() {
        #expect(Settlement.transfers(for: [P.anna: 0, P.ben: 0]).isEmpty)
    }

    @Test func chainCollapses() {
        // Anna owes Ben 10 €, Ben owes Clara 10 € → Anna pays Clara directly.
        let expenses = [expense(1000, by: P.ben, for: [P.anna]), expense(1000, by: P.clara, for: [P.ben])]
        let balances = Balances.compute(members: [P.anna, P.ben, P.clara], expenses: expenses)
        #expect(Settlement.transfers(for: balances) == [Transfer(from: P.anna, to: P.clara, amountCents: 1000)])
        #expect(Settlement.directTransferCount(expenses: expenses) == 2)
    }

    @Test func circleCancels() {
        let expenses = [
            expense(1000, by: P.ben, for: [P.anna]),
            expense(1000, by: P.clara, for: [P.ben]),
            expense(1000, by: P.anna, for: [P.clara]),
        ]
        let balances = Balances.compute(members: [P.anna, P.ben, P.clara], expenses: expenses)
        #expect(Settlement.transfers(for: balances).isEmpty)
    }

    @Test func beatsPlainGreedy() {
        // Matching largest debtor with largest creditor alone needs 5 transfers here;
        // spotting that David (+3) and Fiona (−3) cancel out gets it down to 4.
        let balances = [P.anna: -800, P.ben: 600, P.clara: -200, P.david: 300, P.emil: 400, P.fiona: -300]
        let transfers = Settlement.transfers(for: balances)
        #expect(transfers.count == 4)
        #expect(transfers.contains(Transfer(from: P.fiona, to: P.david, amountCents: 300)))
        #expect(apply(transfers, to: balances).values.allSatisfy { $0 == 0 })
    }

    @Test func randomGroupsSettleOptimally() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<300 {
            let count = Int.random(in: 2...8, using: &generator)
            let people = (0..<count).map { _ in UUID() }
            var balances: [UUID: Int] = [:]
            for person in people.dropLast() { balances[person] = Int.random(in: -12...12, using: &generator) * 100 }
            balances[people.last!] = -balances.values.reduce(0, +)

            let transfers = Settlement.transfers(for: balances)
            #expect(apply(transfers, to: balances).values.allSatisfy { $0 == 0 })
            #expect(transfers.allSatisfy { $0.amountCents > 0 && $0.from != $0.to })
            #expect(transfers.count == bruteForceMinimum(Array(balances.values)))
        }
    }

    @Test func isDeterministic() {
        let balances = [P.anna: -500, P.ben: -500, P.clara: 500, P.david: 500]
        let first = Settlement.transfers(for: balances)
        for _ in 0..<20 { #expect(Settlement.transfers(for: balances) == first) }
        #expect(first.count == 2)
    }

    @Test func largeGroupStillSettles() {
        var balances: [UUID: Int] = [:]
        for index in 0..<30 { balances[UUID()] = (index % 2 == 0 ? 1 : -1) * (index + 1) * 100 }
        let fix = balances.values.reduce(0, +)
        balances[UUID()] = -fix
        let transfers = Settlement.transfers(for: balances)
        #expect(apply(transfers, to: balances).values.allSatisfy { $0 == 0 })
        #expect(transfers.count < balances.count)
    }

    /// Reference: n minus the most zero-sum blocks over all set partitions (recursive, slow).
    private func bruteForceMinimum(_ values: [Int]) -> Int {
        let open = values.filter { $0 != 0 }
        func blocks(_ rest: [Int]) -> Int {
            guard let first = rest.first else { return 0 }
            let others = Array(rest.dropFirst())
            var best = 0
            for mask in 0..<(1 << others.count) {
                let chosen = others.indices.filter { mask >> $0 & 1 == 1 }
                guard first + chosen.reduce(0, { $0 + others[$1] }) == 0 else { continue }
                let remaining = others.indices.filter { mask >> $0 & 1 == 0 }.map { others[$0] }
                best = max(best, 1 + blocks(remaining))
            }
            return best
        }
        return open.count - blocks(open)
    }
}

/// Small deterministic RNG (SplitMix64) for reproducible random tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
