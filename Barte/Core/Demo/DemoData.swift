import Foundation

/// Sample groups for screenshots and UI tests. Debug only, enabled with `-BarteDemo`.
///
/// Launch flags (Debug):
/// - `-BarteDemo`: in-memory store with sample groups, "me" is Dominik
/// - `-BarteEmpty`: with `-BarteDemo`, start without groups
/// - `-BarteGroup <n>`: open the n-th group (0 = top card)
/// - `-BarteSheet settle|expense|group|about`: also open a sheet
@MainActor
enum DemoData {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-BarteDemo")
        #else
        false
        #endif
    }

    static func argument(after flag: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
        #else
        nil
        #endif
    }

    static func seed(into repository: GroupRepository) {
        Identity.myName = "Dominik"
        guard !ProcessInfo.processInfo.arguments.contains("-BarteEmpty") else { return }

        // Created oldest first, so the newest ends up on top of the stack.
        var group = Builder(repository, "Pizza-Abende", .orange, "EUR", ["Dominik", "Jonas", "Mia"])
        group.add("Pizzeria Da Mario", 7450, by: "Jonas", daysAgo: 30)
        group.add("Ausgleich", 2483, by: "Dominik", for: ["Jonas"], daysAgo: 29, settlement: true)
        group.add("Ausgleich", 2483, by: "Mia", for: ["Jonas"], daysAgo: 29, settlement: true)

        group = Builder(repository, "London", .pink, "GBP", ["Dominik", "Sophie"])
        group.add("Hotel Shoreditch", 42000, by: "Sophie", daysAgo: 21)
        group.add("Tube", 3260, by: "Dominik", daysAgo: 20)
        group.add("Fish & Chips", 2850, by: "Dominik", daysAgo: 19)

        group = Builder(repository, "WG Leopoldstraße", .indigo, "EUR", ["Dominik", "Lena", "Max"])
        group.add("Strom Oktober", 8400, by: "Lena", daysAgo: 16)
        group.add("Internet", 3999, by: "Max", daysAgo: 12)
        group.add("Putzmittel dm", 2315, by: "Dominik", daysAgo: 6)
        group.add("Ausgleich", 2000, by: "Max", for: ["Lena"], daysAgo: 3, settlement: true)

        group = Builder(repository, "Skiurlaub Saalbach", .blue, "EUR", ["Dominik", "Anna", "Ben", "Clara", "David"])
        group.add("Chalet", 120_000, by: "Dominik", daysAgo: 9)
        group.add("Skipässe", 114_000, by: "Anna", daysAgo: 8)
        group.add("Einkauf Spar", 18640, by: "Ben", daysAgo: 8)
        group.add("Hüttengaudi", 6200, by: "Dominik", for: ["Dominik", "Ben", "David"], daysAgo: 6)
        group.add("Pizza", 9850, by: "Clara", for: ["Dominik", "Anna", "Clara"], daysAgo: 5)
        group.add("Taxi zum Lift", 4500, by: "David", for: ["Ben", "David"], daysAgo: 4)
        group.add("Tanken", 8900, by: "Clara", daysAgo: 2)
    }

    @MainActor
    private struct Builder {
        let repository: GroupRepository
        let groupID: UUID
        let names: [String]
        let ids: [String: UUID]

        init(_ repository: GroupRepository, _ name: String, _ color: CardColor, _ currency: String, _ names: [String]) {
            self.repository = repository
            self.names = names
            let id = repository.createGroup(name: name, currency: currency, color: color, memberNames: names)
            groupID = id
            let members = repository.fetchGroups().first { $0.id == id }?.members ?? []
            ids = Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0.id) })
        }

        func add(_ title: String, _ cents: Int, by payer: String, for participants: [String]? = nil, daysAgo: Int, settlement: Bool = false) {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            repository.save(Expense(
                id: UUID(), title: title, amountCents: cents, date: date,
                payerID: ids[payer]!,
                participantIDs: (participants ?? names).compactMap { ids[$0] },
                isSettlement: settlement
            ), in: groupID)
        }
    }
}
