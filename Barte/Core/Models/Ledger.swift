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

/// How an expense is divided among its participants.
enum SplitMode: Hashable, Sendable {
    /// Everyone pays the same, to the cent.
    case equal
    /// Weights per participant, e.g. 2 for a couple and 1 for everyone else.
    case shares([UUID: Int])
    /// A fixed amount in cents per participant; they add up to the expense's amount.
    case exact([UUID: Int])

    /// The raw value stored on the server.
    var kind: String {
        switch self {
        case .equal: "equal"
        case .shares: "shares"
        case .exact: "exact"
        }
    }

    var values: [UUID: Int]? {
        switch self {
        case .equal: nil
        case .shares(let values), .exact(let values): values
        }
    }

    /// Rebuilds a mode from the server's kind and values aligned with the participant ids.
    init(kind: String, values: [Int]?, participants: [UUID]) {
        guard let values, values.count == participants.count else {
            self = .equal
            return
        }
        let byID = Dictionary(zip(participants, values), uniquingKeysWith: +)
        switch kind {
        case "shares": self = .shares(byID)
        case "exact": self = .exact(byID)
        default: self = .equal
        }
    }
}

/// An expense paid by one member and shared by some members, equally or not.
/// A settlement ("A paid B back") is the same shape: payer A, single participant B.
struct Expense: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var amountCents: Int
    var date: Date
    var payerID: UUID
    var participantIDs: [UUID]
    var isSettlement: Bool = false
    var split: SplitMode = .equal

    /// What each participant pays. Always adds up to the amount.
    var shares: [UUID: Int] {
        switch split {
        case .equal:
            Split.equal(amountCents: amountCents, participants: participantIDs, payer: payerID)
        case .shares(let weights):
            Split.weighted(amountCents: amountCents, weights: weights.filter { participantIDs.contains($0.key) }, payer: payerID)
        case .exact(let amounts):
            amounts.filter { participantIDs.contains($0.key) && $0.value > 0 }
        }
    }

    /// The split values in participant order, as the server stores them.
    var splitValues: [Int]? {
        split.values.map { values in participantIDs.map { values[$0] ?? 0 } }
    }
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

    /// Shares proportional to weights. Each person gets their exact share rounded down; the cents
    /// left over go to the largest remainders, ties broken like `equal` (payer first, then by id).
    /// 100,00 € with weights 2 and 1 is 66,67 € + 33,33 €.
    static func weighted(amountCents: Int, weights: [UUID: Int], payer: UUID) -> [UUID: Int] {
        let positive = weights.filter { $0.value > 0 }
        let total = positive.values.reduce(0, +)
        guard total > 0, amountCents >= 0 else { return [:] }
        var shares: [UUID: Int] = [:]
        var remainders: [(id: UUID, rest: Int)] = []
        for (id, weight) in positive {
            let product = amountCents * weight
            shares[id] = product / total
            remainders.append((id, product % total))
        }
        var left = amountCents - shares.values.reduce(0, +)
        remainders.sort { lhs, rhs in
            if lhs.rest != rhs.rest { return lhs.rest > rhs.rest }
            if lhs.id == payer { return rhs.id != payer }
            if rhs.id == payer { return false }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for item in remainders where left > 0 {
            shares[item.id, default: 0] += 1
            left -= 1
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
            for (id, share) in expense.shares {
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
            for (id, share) in expense.shares
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
