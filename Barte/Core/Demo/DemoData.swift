import Foundation

/// Sample groups for screenshots and UI tests. Debug only, enabled with `-BarteDemo`.
///
/// Launch flags (Debug):
/// - `-BarteDemo`: in-memory sample groups, signed in as Dominik, no server
/// - `-BarteEmpty`: with `-BarteDemo`, start without groups
/// - `-BarteSignedOut`: with `-BarteDemo`, show the sign-in screen
/// - `-BarteGroup <n>`: open the n-th group (0 = top card)
/// - `-BarteSheet settle|expense|group|about|join|invite|history|chat`: also open a sheet (chat: the group's chat)
enum DemoData {
    static let userID = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000001")!
    static let inviteCode = "SKI2FUN7"

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-BarteDemo")
        #else
        false
        #endif
    }

    static func has(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
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

    static func groups() -> [SplitGroup] {
        guard !has("-BarteEmpty") else { return [] }
        // Newest first, like the server returns them.
        return [
            Builder("Skiurlaub Saalbach", .blue, "EUR", ["Dominik", "Anna", "Ben", "Clara", "David"], appUsers: ["Anna", "Ben"], daysAgo: 10, code: inviteCode)
                .add("Tanken", 8900, by: "Clara", daysAgo: 2)
                .add("Taxi zum Lift", 4500, by: "David", for: ["Ben", "David"], daysAgo: 4)
                .add("Pizza", 9850, by: "Clara", for: ["Dominik", "Anna", "Clara"], daysAgo: 5)
                .add("Hüttengaudi", 6200, by: "Dominik", for: ["Dominik", "Ben", "David"], daysAgo: 6)
                .add("Abendessen Alpenrose", 21000, by: "David", split: .shares(["Dominik": 1, "Anna": 1, "Ben": 2, "Clara": 1, "David": 2]), daysAgo: 7)
                .add("Einkauf Spar", 18640, by: "Ben", daysAgo: 8)
                .add("Skipässe", 114_000, by: "Anna", daysAgo: 8)
                .add("Skischule Kinder", 36000, by: "Ben", for: ["Ben", "Clara"], split: .exact(["Ben": 24000, "Clara": 12000]), daysAgo: 8)
                .add("Chalet", 120_000, by: "Dominik", daysAgo: 9)
                .group,
            Builder("WG Leopoldstraße", .indigo, "EUR", ["Dominik", "Lena", "Max"], appUsers: ["Lena", "Max"], daysAgo: 20)
                .add("Ausgleich", 2000, by: "Max", for: ["Lena"], daysAgo: 3, settlement: true)
                .add("Putzmittel dm", 2315, by: "Dominik", daysAgo: 6)
                .add("Internet", 3999, by: "Max", daysAgo: 12)
                .add("Strom Oktober", 8400, by: "Lena", daysAgo: 16)
                .group,
            Builder("London", .pink, "GBP", ["Dominik", "Sophie"], appUsers: [], daysAgo: 25)
                .add("Fish & Chips", 2850, by: "Dominik", daysAgo: 19)
                .add("Tube", 3260, by: "Dominik", daysAgo: 20)
                .add("Hotel Shoreditch", 42000, by: "Sophie", daysAgo: 21)
                .group,
            Builder("Pizza-Abende", .orange, "EUR", ["Dominik", "Jonas", "Mia"], appUsers: ["Jonas"], daysAgo: 40)
                .add("Ausgleich", 2483, by: "Mia", for: ["Jonas"], daysAgo: 29, settlement: true)
                .add("Ausgleich", 2483, by: "Dominik", for: ["Jonas"], daysAgo: 29, settlement: true)
                .add("Pizzeria Da Mario", 7450, by: "Jonas", daysAgo: 30)
                .closed(daysAgo: 28)
                .group,
        ]
    }

    static func snapshot(_ expense: Expense) -> GroupEvent.Snapshot {
        GroupEvent.Snapshot(
            title: expense.title, amountCents: expense.amountCents, spentOn: LocalDay.string(from: expense.date),
            payerID: expense.payerID, participantIDs: expense.participantIDs, isSettlement: expense.isSettlement,
            splitKind: expense.split.kind, splitValues: expense.splitValues
        )
    }

    /// Who entered what, plus one edit worth a second look: Ben changed the Spar receipt.
    static func history(for groups: [SplitGroup]) -> [(groupID: UUID, event: GroupEvent)] {
        var all: [(groupID: UUID, event: GroupEvent)] = []
        for group in groups {
            var events: [GroupEvent] = []
            for expense in group.expenses.reversed() {
                let payer = group.member(expense.payerID)
                // Plain names can't enter anything; the creator did it for them.
                let actor = payer?.usesApp == true ? payer! : group.members.first { $0.userID == userID }!
                events.append(GroupEvent(
                    id: UUID(), kind: expense.isSettlement ? .settlementAdded : .expenseAdded,
                    actorID: actor.userID, actorName: actor.name, subjectID: expense.id,
                    old: nil, new: snapshot(expense), createdAt: expense.date.addingTimeInterval(19 * 3600)
                ))
                if expense.title == "Einkauf Spar", let ben = group.members.first(where: { $0.name == "Ben" }) {
                    var before = snapshot(expense)
                    before.amountCents = 19640
                    events[events.count - 1] = GroupEvent(
                        id: UUID(), kind: .expenseAdded, actorID: ben.userID, actorName: ben.name, subjectID: expense.id,
                        old: nil, new: before, createdAt: expense.date.addingTimeInterval(18 * 3600)
                    )
                    events.append(GroupEvent(
                        id: UUID(), kind: .expenseChanged, actorID: ben.userID, actorName: ben.name, subjectID: expense.id,
                        old: before, new: snapshot(expense), createdAt: expense.date.addingTimeInterval(44 * 3600)
                    ))
                }
            }
            if let closedAt = group.closedAt {
                events.append(GroupEvent(id: UUID(), kind: .groupClosed, actorID: userID, actorName: "Dominik", subjectID: group.id,
                                         old: nil, new: nil, createdAt: closedAt))
            }
            all += events.map { (group.id, $0) }
        }
        return all.sorted { $0.event.createdAt < $1.event.createdAt }
    }

    /// A short conversation on the ski trip around Ben's corrected receipt, with two new messages,
    /// and one unread message in the flat share.
    static func chat(for groups: [SplitGroup]) -> (messages: [UUID: [ChatMessage]], readAt: [UUID: Date]) {
        var messages: [UUID: [ChatMessage]] = [:]
        var readAt: [UUID: Date] = [:]
        let today = Calendar.current.startOfDay(for: .now)
        func say(_ name: String, in group: SplitGroup, _ text: String, at date: Date, about expense: String? = nil) {
            guard let member = group.members.first(where: { $0.name == name }), let author = member.userID else { return }
            messages[group.id, default: []].append(ChatMessage(
                id: UUID(), memberID: member.id, authorID: author, body: text,
                expenseID: expense.flatMap { title in group.expenses.first { $0.title == title }?.id },
                createdAt: date
            ))
        }
        if let ski = groups.first(where: { $0.name == "Skiurlaub Saalbach" }) {
            let spar = ski.expenses.first { $0.title == "Einkauf Spar" }?.date ?? today
            say("Anna", in: ski, "Skipässe sind gezahlt, hab sie für alle eingetragen 🎿", at: spar.addingTimeInterval(19 * 3600 + 120))
            say("Ben", in: ski, "Hab den Spar-Bon korrigiert, da waren 10 € Pfand dabei, die ich zurückbekommen hab.", at: spar.addingTimeInterval(44 * 3600 + 90), about: "Einkauf Spar")
            say("Dominik", in: ski, "Passt, danke!", at: spar.addingTimeInterval(44 * 3600 + 600))
            say("Ben", in: ski, "Wer hat noch Bargeld für die Hütte?", at: .now.addingTimeInterval(-52 * 60))
            say("Anna", in: ski, "Ich, so 50 €", at: .now.addingTimeInterval(-49 * 60))
            readAt[ski.id] = spar.addingTimeInterval(44 * 3600 + 600)
        }
        if let flat = groups.first(where: { $0.name == "WG Leopoldstraße" }) {
            say("Lena", in: flat, "Die Stromrechnung ist da, ich trag sie gleich ein.", at: .now.addingTimeInterval(-3 * 3600))
            readAt[flat.id] = .now.addingTimeInterval(-4 * 3600)
        }
        return (messages, readAt)
    }

    /// An invite for a group the demo person is not in yet.
    static let invitePreview = InvitePreview(
        groupID: UUID(), name: "Roadtrip Kroatien", currency: "EUR", color: CardColor.teal.rawValue, isMember: false,
        members: [
            .init(id: UUID(), name: "Lukas", isClaimed: true),
            .init(id: UUID(), name: "Dominik", isClaimed: false),
            .init(id: UUID(), name: "Sara", isClaimed: false),
        ]
    )

    private struct Builder {
        var group: SplitGroup
        let ids: [String: UUID]

        init(_ name: String, _ color: CardColor, _ currency: String, _ names: [String], appUsers: [String], daysAgo: Int, code: String = "DEMO2345") {
            let members = names.map { memberName in
                Member(
                    id: UUID(), name: memberName,
                    userID: memberName == "Dominik" ? DemoData.userID : appUsers.contains(memberName) ? UUID() : nil
                )
            }
            ids = Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0.id) })
            group = SplitGroup(
                id: UUID(), name: name, currency: currency, color: color,
                createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
                members: members, expenses: [], inviteCode: code, createdBy: DemoData.userID
            )
        }

        enum DemoSplit {
            case shares([String: Int])
            case exact([String: Int])
        }

        func add(_ title: String, _ cents: Int, by payer: String, for participants: [String]? = nil, split: DemoSplit? = nil, daysAgo: Int, settlement: Bool = false) -> Builder {
            var copy = self
            let date = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now)
            copy.group.expenses.append(Expense(
                id: UUID(), title: title, amountCents: cents, date: date,
                payerID: ids[payer]!,
                participantIDs: (participants ?? group.members.map(\.name)).compactMap { ids[$0] },
                isSettlement: settlement,
                split: split.map(mode) ?? .equal
            ))
            return copy
        }

        func closed(daysAgo: Int) -> Builder {
            var copy = self
            copy.group.closedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)
            return copy
        }

        private func mode(_ split: DemoSplit) -> SplitMode {
            func byID(_ values: [String: Int]) -> [UUID: Int] {
                Dictionary(uniqueKeysWithValues: values.compactMap { name, value in ids[name].map { ($0, value) } })
            }
            switch split {
            case .shares(let values): return .shares(byID(values))
            case .exact(let values): return .exact(byID(values))
            }
        }
    }
}

/// In-memory repository for demo mode: no server, changes live until the app quits.
actor DemoGroupRepository: GroupRepository {
    private var groups: [SplitGroup]
    private var payments: [UUID: PaymentDetails]
    /// Newest last, like they happened, each with its group.
    private var events: [(groupID: UUID, event: GroupEvent)] = []
    private var messages: [UUID: [ChatMessage]]
    private var readAt: [UUID: Date]
    private var muted: Set<UUID> = []
    private let stream = AsyncStream<Void>.makeStream()
    /// One stream per open chat; finished ones just ignore further signals.
    private var chatListeners: [AsyncStream<Void>.Continuation] = []

    init(groups: [SplitGroup] = DemoData.groups()) {
        self.groups = groups
        events = DemoData.history(for: groups)
        (messages, readAt) = DemoData.chat(for: groups)
        // Everyone else with the app has PayPal and a bank account; Dominik has nothing yet.
        var payments: [UUID: PaymentDetails] = [:]
        for member in groups.flatMap(\.members) {
            guard let userID = member.userID, userID != DemoData.userID else { continue }
            payments[userID] = PaymentDetails(
                paypal: member.name.lowercased() + "demo",
                iban: "DE89370400440532013000",
                accountHolder: "\(member.name) Beispiel"
            )
        }
        self.payments = payments
    }

    func fetchPaymentDetails() async throws -> [UUID: PaymentDetails] { payments }

    func savePaymentDetails(_ details: PaymentDetails) async throws {
        payments[DemoData.userID] = details.isEmpty ? nil : details
        stream.continuation.yield()
    }

    nonisolated func changes() -> AsyncStream<Void> { stream.stream }

    private func update(_ groupID: UUID, _ change: (inout SplitGroup) throws -> Void) throws {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { throw BarteError.server(hint: "not_member") }
        try change(&groups[index])
        stream.continuation.yield()
    }

    private func groupIndex(ofMember id: UUID) -> Int? {
        groups.firstIndex { $0.members.contains { $0.id == id } }
    }

    func fetchGroups() async throws -> [SplitGroup] {
        groups.map { group in
            var group = group
            let current = Set(group.expenses.map(\.id))
            group.editedExpenseIDs = Set(events.filter { $0.groupID == group.id && $0.event.kind == .expenseChanged }
                .compactMap(\.event.subjectID)).intersection(current)
            let read = readAt[group.id] ?? .distantPast
            group.unreadMessages = (messages[group.id] ?? []).count { !$0.isDeleted && $0.authorID != DemoData.userID && $0.createdAt > read }
            group.chatMuted = muted.contains(group.id)
            return group
        }
    }

    func fetchHistory(groupID: UUID, subjectID: UUID?) async throws -> [GroupEvent] {
        events
            .filter { $0.groupID == groupID && (subjectID == nil || $0.event.subjectID == subjectID) }
            .map(\.event)
            .reversed()
    }

    private func log(_ kind: GroupEvent.Kind, in groupID: UUID, subject: UUID, old: GroupEvent.Snapshot?, new: GroupEvent.Snapshot?) {
        let event = GroupEvent(id: UUID(), kind: kind, actorID: DemoData.userID, actorName: "Dominik", subjectID: subject, old: old, new: new, createdAt: .now)
        events.append((groupID, event))
        chatChanged()
    }

    // MARK: Chat

    func fetchChat(groupID: UUID) async throws -> [ChatMessage] {
        messages[groupID] ?? []
    }

    func sendMessage(_ id: UUID, body: String, expenseID: UUID?, in groupID: UUID) async throws {
        guard let group = groups.first(where: { $0.id == groupID }) else { throw BarteError.server(hint: "not_member") }
        guard let body = ChatMessage.cleaned(body) else { throw BarteError.server(hint: "empty_message") }
        guard !(messages[groupID] ?? []).contains(where: { $0.id == id }) else { return }
        try await Task.sleep(for: .milliseconds(250))
        messages[groupID, default: []].append(ChatMessage(
            id: id, memberID: group.me(userID: DemoData.userID), authorID: DemoData.userID,
            body: body, expenseID: expenseID, createdAt: .now
        ))
        readAt[groupID] = .now
        chatChanged()
        stream.continuation.yield()
    }

    func deleteMessage(_ id: UUID) async throws {
        for (groupID, list) in messages {
            guard let index = list.firstIndex(where: { $0.id == id && $0.authorID == DemoData.userID && !$0.isDeleted }) else { continue }
            messages[groupID]![index].body = nil
            messages[groupID]![index].expenseID = nil
            messages[groupID]![index].deletedAt = .now
            chatChanged()
            return
        }
        throw BarteError.server(hint: "message_not_found")
    }

    func markChatRead(groupID: UUID) async throws {
        readAt[groupID] = .now
        stream.continuation.yield()
    }

    func setChatMuted(_ isMuted: Bool, group id: UUID) async throws {
        if isMuted { muted.insert(id) } else { muted.remove(id) }
        stream.continuation.yield()
    }

    nonisolated func chatChanges(groupID: UUID) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        Task { await addChatListener(continuation) }
        return stream
    }

    private func addChatListener(_ continuation: AsyncStream<Void>.Continuation) {
        chatListeners.append(continuation)
    }

    private func chatChanged() {
        for listener in chatListeners { listener.yield() }
    }

    func createGroup(name: String, currency: String, color: CardColor, myName: String, otherNames: [String]) async throws -> UUID {
        let members = [Member(id: UUID(), name: myName, userID: DemoData.userID)] + otherNames.map { Member(id: UUID(), name: $0) }
        let group = SplitGroup(id: UUID(), name: name, currency: currency, color: color, createdAt: .now, members: members, expenses: [], inviteCode: "NEU23456", createdBy: DemoData.userID)
        groups.insert(group, at: 0)
        stream.continuation.yield()
        return group.id
    }

    func updateGroup(_ id: UUID, name: String, currency: String, color: CardColor) async throws {
        try update(id) { group in
            group.name = name
            group.currency = currency
            group.color = color
        }
    }

    func deleteGroup(_ id: UUID) async throws {
        groups.removeAll { $0.id == id }
        stream.continuation.yield()
    }

    func leaveGroup(_ id: UUID) async throws {
        try await deleteGroup(id)
    }

    func setClosed(_ closed: Bool, group id: UUID) async throws {
        try update(id) { group in
            group.closedAt = closed ? group.closedAt ?? .now : nil
        }
        log(closed ? .groupClosed : .groupReopened, in: id, subject: id, old: nil, new: nil)
    }

    func addMember(named name: String, to groupID: UUID) async throws -> UUID {
        let member = Member(id: UUID(), name: name)
        try update(groupID) { $0.members.append(member) }
        return member.id
    }

    func renameMember(_ id: UUID, to name: String) async throws {
        guard let index = groupIndex(ofMember: id) else { return }
        try update(groups[index].id) { group in
            if let member = group.members.firstIndex(where: { $0.id == id }) { group.members[member].name = name }
        }
    }

    func removeMember(_ id: UUID) async throws {
        guard let index = groupIndex(ofMember: id) else { return }
        try update(groups[index].id) { group in
            guard !group.isInvolved(id) else { throw BarteError.server(hint: "member_involved") }
            group.members.removeAll { $0.id == id }
        }
    }

    func claimMember(_ id: UUID) async throws {
        guard let index = groupIndex(ofMember: id) else { return }
        try update(groups[index].id) { group in
            for member in group.members.indices where group.members[member].userID == DemoData.userID {
                group.members[member].userID = nil
            }
            if let member = group.members.firstIndex(where: { $0.id == id }) { group.members[member].userID = DemoData.userID }
        }
    }

    func save(_ expense: Expense, in groupID: UUID) async throws {
        let previous = groups.first { $0.id == groupID }?.expenses.first { $0.id == expense.id }
        let kind: GroupEvent.Kind = previous != nil ? .expenseChanged : expense.isSettlement ? .settlementAdded : .expenseAdded
        if previous.map(DemoData.snapshot) != DemoData.snapshot(expense) {
            log(kind, in: groupID, subject: expense.id, old: previous.map(DemoData.snapshot), new: DemoData.snapshot(expense))
        }
        try update(groupID) { group in
            group.expenses.removeAll { $0.id == expense.id }
            group.expenses.append(expense)
            group.expenses.sort { $0.date > $1.date }
            group.closedAt = nil
        }
    }

    func deleteExpense(_ id: UUID) async throws {
        guard let index = groups.firstIndex(where: { $0.expenses.contains { $0.id == id } }) else { return }
        if let expense = groups[index].expenses.first(where: { $0.id == id }) {
            log(expense.isSettlement ? .settlementDeleted : .expenseDeleted, in: groups[index].id, subject: id, old: DemoData.snapshot(expense), new: nil)
        }
        try update(groups[index].id) { group in
            group.expenses.removeAll { $0.id == id }
            group.closedAt = nil
        }
    }

    func previewInvite(code: String) async throws -> InvitePreview {
        guard code == DemoData.inviteCode || code == "KROATIEN" else { throw BarteError.server(hint: "invalid_code") }
        if code == DemoData.inviteCode, let group = groups.first(where: { $0.inviteCode == code }) {
            return InvitePreview(groupID: group.id, name: group.name, currency: group.currency, color: group.color.rawValue, isMember: true, members: [])
        }
        return DemoData.invitePreview
    }

    func joinGroup(code: String, memberID: UUID?, name: String?) async throws -> UUID {
        let preview = try await previewInvite(code: code)
        if preview.isMember { return preview.groupID }
        var members = preview.members.map { Member(id: $0.id, name: $0.name, userID: $0.isClaimed ? UUID() : nil) }
        if let memberID, let index = members.firstIndex(where: { $0.id == memberID }) {
            members[index].userID = DemoData.userID
        } else {
            members.append(Member(id: UUID(), name: name ?? "Ich", userID: DemoData.userID))
        }
        groups.insert(SplitGroup(id: preview.groupID, name: preview.name, currency: preview.currency, color: CardColor(rawValue: preview.color) ?? .teal, createdAt: .now, members: members, expenses: [], inviteCode: "KROATIEN"), at: 0)
        stream.continuation.yield()
        return preview.groupID
    }

    func deleteAccount(appleAuthorizationCode: String) async throws {
        groups = []
        stream.continuation.yield()
    }
}
