import Foundation

/// A person in a group. Members are names, so friends without the app can be part of a group too.
/// Someone who uses Barte is linked to their member through `userID`.
struct Member: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var userID: UUID? = nil

    var usesApp: Bool { userID != nil }

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

/// An expense paid by one member and shared equally by some members.
/// A settlement ("A paid B back") is the same shape: payer A, single participant B.
struct Expense: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var amountCents: Int
    var date: Date
    var payerID: UUID
    var participantIDs: [UUID]
    var isSettlement: Bool = false
}

/// A suggested payment that moves money from a debtor to a creditor.
struct Transfer: Hashable, Sendable {
    let from: UUID
    let to: UUID
    let amountCents: Int
}

/// How an expense is divided. Shares always add up to the amount exactly.
enum Split {
    /// Equal shares. Leftover cents go to the payer first (if they take part), then to the others
    /// in a stable order, so every device computes the same result: 10,00 € between three people
    /// with payer A is A 3,34 € + 3,33 € + 3,33 €.
    static func equal(amountCents: Int, participants: [UUID], payer: UUID) -> [UUID: Int] {
        let unique = Array(Set(participants))
        guard !unique.isEmpty, amountCents >= 0 else { return [:] }
        let ordered = unique.sorted { lhs, rhs in
            if lhs == payer { return rhs != payer }
            if rhs == payer { return false }
            return lhs.uuidString < rhs.uuidString
        }
        let base = amountCents / ordered.count
        let remainder = amountCents % ordered.count
        var shares: [UUID: Int] = [:]
        for (index, id) in ordered.enumerated() {
            shares[id] = base + (index < remainder ? 1 : 0)
        }
        return shares
    }
}

enum Balances {
    /// Net balance per member: positive means the group owes them money, negative means they owe.
    /// The values always sum to zero.
    static func compute(members: [UUID], expenses: [Expense]) -> [UUID: Int] {
        var balances = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        for expense in expenses where !expense.participantIDs.isEmpty {
            balances[expense.payerID, default: 0] += expense.amountCents
            for (id, share) in Split.equal(amountCents: expense.amountCents, participants: expense.participantIDs, payer: expense.payerID) {
                balances[id, default: 0] -= share
            }
        }
        return balances
    }
}

enum Settlement {
    /// Up to this many people with an open balance, the exact minimum is computed (2^n subsets).
    static let exactLimit = 16

    /// The fewest transfers that settle all balances.
    ///
    /// Everyone with a non-zero balance needs at least one transfer, and a group of k people whose
    /// balances sum to zero can always be settled with k − 1 transfers. So the minimum is
    /// n − (largest number of disjoint zero-sum subgroups). A subset DP finds that partition exactly;
    /// each subgroup is then settled by matching the largest debtor with the largest creditor.
    /// Beyond `exactLimit` people the greedy matching alone is used (still at most n − 1 transfers).
    static func transfers(for balances: [UUID: Int]) -> [Transfer] {
        let ids = balances.filter { $0.value != 0 }.keys.sorted { $0.uuidString < $1.uuidString }
        guard !ids.isEmpty else { return [] }
        let values = ids.map { balances[$0] ?? 0 }
        guard values.reduce(0, +) == 0 else {
            assertionFailure("Balances must sum to zero")
            return []
        }
        let groups = ids.count <= exactLimit ? zeroSumPartition(values) : [Array(ids.indices)]
        return groups.flatMap { group in
            greedy(group.map { (ids[$0], values[$0]) })
        }
    }

    /// How many transfers paying back each expense directly would take (one per debtor/creditor pair
    /// with an open amount). Used to show how much simpler the suggestion is.
    static func directTransferCount(expenses: [Expense]) -> Int {
        var owed: [PairKey: Int] = [:]
        for expense in expenses where !expense.participantIDs.isEmpty {
            for (id, share) in Split.equal(amountCents: expense.amountCents, participants: expense.participantIDs, payer: expense.payerID)
            where id != expense.payerID && share > 0 {
                let key = PairKey(id, expense.payerID)
                owed[key, default: 0] += key.first == id ? share : -share
            }
        }
        return owed.values.filter { $0 != 0 }.count
    }

    // MARK: - Internals

    /// Splits indices into the largest number of disjoint subsets that each sum to zero.
    /// dp[mask] = most zero-sum blocks along some removal order of mask's elements; every mask on
    /// that chain with sum zero closes a block.
    static func zeroSumPartition(_ values: [Int]) -> [[Int]] {
        let n = values.count
        let full = (1 << n) - 1
        var sum = [Int](repeating: 0, count: full + 1)
        var dp = [Int](repeating: 0, count: full + 1)
        var removed = [Int](repeating: 0, count: full + 1)
        for mask in 1...full {
            let low = mask & -mask
            sum[mask] = sum[mask ^ low] + values[low.trailingZeroBitCount]
            var best = -1
            var bestIndex = 0
            var rest = mask
            while rest != 0 {
                let bit = rest & -rest
                rest ^= bit
                if dp[mask ^ bit] > best {
                    best = dp[mask ^ bit]
                    bestIndex = bit.trailingZeroBitCount
                }
            }
            dp[mask] = best + (sum[mask] == 0 ? 1 : 0)
            removed[mask] = bestIndex
        }
        var groups: [[Int]] = []
        var current: [Int] = []
        var mask = full
        while mask != 0 {
            let index = removed[mask]
            current.append(index)
            mask ^= 1 << index
            if sum[mask] == 0 {
                groups.append(current.sorted())
                current = []
            }
        }
        return groups
    }

    /// Settles one zero-sum group: biggest debtor pays biggest creditor until everyone is even.
    private static func greedy(_ people: [(id: UUID, balance: Int)]) -> [Transfer] {
        var creditors = people.filter { $0.balance > 0 }
        var debtors = people.filter { $0.balance < 0 }.map { (id: $0.id, balance: -$0.balance) }
        func byAmount(_ a: (id: UUID, balance: Int), _ b: (id: UUID, balance: Int)) -> Bool {
            a.balance != b.balance ? a.balance > b.balance : a.id.uuidString < b.id.uuidString
        }
        var result: [Transfer] = []
        while !creditors.isEmpty, !debtors.isEmpty {
            creditors.sort(by: byAmount)
            debtors.sort(by: byAmount)
            let amount = min(creditors[0].balance, debtors[0].balance)
            result.append(Transfer(from: debtors[0].id, to: creditors[0].id, amountCents: amount))
            creditors[0].balance -= amount
            debtors[0].balance -= amount
            creditors.removeAll { $0.balance == 0 }
            debtors.removeAll { $0.balance == 0 }
        }
        return result
    }

    private struct PairKey: Hashable {
        let first: UUID
        let second: UUID
        init(_ a: UUID, _ b: UUID) {
            if a.uuidString < b.uuidString { first = a; second = b } else { first = b; second = a }
        }
    }
}
