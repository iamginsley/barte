import SwiftUI

/// One group: its card, the way to settle up, and all expenses by month.
struct GroupDetailView: View {
    let groupID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editingExpense: Expense?
    @State private var showsNewExpense = false
    @State private var showsSettle = false
    @State private var showsEdit = false
    @State private var confirmsLeave = false
    @State private var settlementToDelete: Expense?
    @State private var showsInvite = false
    @State private var showsHistory = false
    @State private var showsChat = false
    @State private var alertMessage: String?
    @State private var didAppear = false

    var body: some View {
        if let group = model.group(groupID) {
            content(group)
        } else {
            ContentUnavailableView("Gruppe nicht gefunden", systemImage: "rectangle.on.rectangle.slash")
        }
    }

    private func content(_ group: SplitGroup) -> some View {
        let me = model.me(in: group.id)
        return List {
            Section {
                GroupCard(group: group, me: me, showsUnread: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                settleRow(group)
            }

            if group.expenses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Noch keine Ausgaben", systemImage: "creditcard")
                    } description: {
                        Text("Tippe auf „Ausgabe“, wenn jemand etwas für die Gruppe bezahlt hat.")
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(Self.months(of: group.expenses), id: \.title) { month in
                    Section(month.title) {
                        ForEach(month.expenses) { expense in
                            Button {
                                if expense.isSettlement { settlementToDelete = expense } else { editingExpense = expense }
                            } label: {
                                ExpenseRow(expense: expense, group: group, me: me)
                            }
                            .tint(Color.ink)
                            .swipeActions {
                                Button("Löschen", systemImage: "trash", role: .destructive) {
                                    Task { await perform { try await $0.deleteExpense(expense.id) } }
                                }
                            }
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 80, for: .scrollContent)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(group) }
        .safeAreaInset(edge: .bottom) {
            // A closed group is done; reopening it is one tap in the row above.
            if !group.isClosed {
                Button {
                    showsNewExpense = true
                } label: {
                    Label("Ausgabe", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(group.members.isEmpty)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showsNewExpense) { ExpenseEditorSheet(group: group, expense: nil, me: me) }
        .sheet(item: $editingExpense) { ExpenseEditorSheet(group: group, expense: $0, me: me) }
        .sheet(isPresented: $showsSettle) { SettleUpSheet(groupID: group.id) }
        .sheet(isPresented: $showsEdit) { GroupEditorSheet(group: group) { _ in } }
        .sheet(isPresented: $showsInvite) { InviteSheet(groupID: group.id) }
        .sheet(isPresented: $showsHistory) { HistorySheet(group: group) }
        .navigationDestination(isPresented: $showsChat) { ChatView(groupID: group.id) }
        .onChange(of: model.pendingChatGroupID) { openPendingChat() }
        .onChange(of: model.pendingSettleGroupID) { openPendingSettle() }
        .confirmationDialog("Gruppe verlassen?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) { Task { await leave(group) } }
        } message: {
            Text(leaveMessage(group))
        }
        .confirmationDialog("Ausgleich löschen?", isPresented: .init(
            get: { settlementToDelete != nil }, set: { if !$0 { settlementToDelete = nil } }
        ), titleVisibility: .visible, presenting: settlementToDelete) { settlement in
            Button("Löschen", role: .destructive) { Task { await perform { try await $0.deleteExpense(settlement.id) } } }
        } message: { settlement in
            Text("\(group.name(of: settlement.payerID, me: me)) → \(group.name(of: settlement.participantIDs.first ?? settlement.payerID, me: me)), \(Money.format(settlement.amountCents, currency: group.currency)). Die Salden werden neu berechnet.")
        }
        .alert("Das hat nicht geklappt", isPresented: .init(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear { appear(group, me: me) }
    }

    // MARK: Pieces

    @ViewBuilder
    private func settleRow(_ group: SplitGroup) -> some View {
        if let date = group.closedDateText {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Abgeschlossen")
                            .font(.body.weight(.medium))
                        Text("am \(date)")
                            .font(.subheadline)
                    }
                } icon: {
                    Image(systemName: "archivebox.fill")
                }
                .foregroundStyle(Color.inkSecondary)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button("Wieder öffnen") { Task { await setClosed(false, group) } }
                    .buttonStyle(.bordered)
                    .fixedSize()
            }
            .frame(minHeight: Theme.minTapSize)
        } else if group.isSettled && !group.expenses.isEmpty {
            HStack {
                Label("Alle sind quitt", systemImage: "checkmark.seal.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.positive)
                Spacer(minLength: 8)
                Button("Abschließen") { Task { await setClosed(true, group) } }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .accessibilityHint("Legt die Gruppe für alle unter „Abgeschlossen“ ab")
            }
            .frame(minHeight: Theme.minTapSize)
        } else if group.isSettled {
            Label("Noch nichts auszugleichen", systemImage: "checkmark.seal.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.inkSecondary)
                .frame(minHeight: Theme.minTapSize)
        } else {
            let count = group.transfers.count
            Button {
                showsSettle = true
            } label: {
                HStack {
                    Label("Ausgleichen", systemImage: "arrow.left.arrow.right")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text("\(count) Überweisungen", comment: "Number of transfers, with plural variants")
                        .foregroundStyle(Color.inkSecondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: Theme.minTapSize)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ group: SplitGroup) -> some ToolbarContent {
        // Always there; until someone else uses the app, the chat leads to the invite.
        ToolbarItem(placement: .topBarTrailing) {
            Button("Chat", systemImage: "bubble.left.and.bubble.right") { showsChat = true }
                .badge(group.unreadMessages)
                .accessibilityValue(group.unreadMessages > 0 ? UnreadBadge.label(group.unreadMessages) : "")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Einladen", systemImage: "person.crop.circle.badge.plus") { showsInvite = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Mehr", systemImage: "ellipsis") {
                Button("Gruppe bearbeiten", systemImage: "pencil") { showsEdit = true }
                Button("Verlauf", systemImage: "clock.arrow.circlepath") { showsHistory = true }
                if group.isClosed {
                    Button("Wieder öffnen", systemImage: "arrow.uturn.backward") { Task { await setClosed(false, group) } }
                } else if !group.expenses.isEmpty && group.isSettled {
                    // Only once everyone is square: open amounts must not vanish from the overview.
                    Button("Gruppe abschließen", systemImage: "archivebox") { Task { await setClosed(true, group) } }
                }
                Divider()
                Button("Gruppe verlassen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    requestLeave(group)
                }
            }
        }
    }

    // MARK: Actions

    private func appear(_ group: SplitGroup, me: UUID?) {
        guard !didAppear else { return }
        didAppear = true
        openPendingChat()
        openPendingSettle()
        guard model.isDemo else { return }
        switch DemoData.argument(after: "-BarteSheet") {
        case "settle": showsSettle = true
        case "expense": showsNewExpense = true
        case "invite": showsInvite = true
        case "history": showsHistory = true
        case "chat": showsChat = true
        default: break
        }
    }

    /// A chat notification was tapped.
    private func openPendingChat() {
        guard model.pendingChatGroupID == groupID else { return }
        model.pendingChatGroupID = nil
        showsChat = true
    }

    /// A reminder was tapped: paying is one step away.
    private func openPendingSettle() {
        guard model.pendingSettleGroupID == groupID else { return }
        model.pendingSettleGroupID = nil
        showsSettle = true
    }

    private func perform(_ work: @escaping @Sendable (GroupRepository) async throws -> Void) async {
        if let message = await model.run(work) { alertMessage = message }
    }

    /// With open amounts and others still in, leaving is explained instead of offered.
    private func requestLeave(_ group: SplitGroup) {
        if group.canLeave(userID: model.userID) {
            confirmsLeave = true
        } else {
            alertMessage = BarteError.server(hint: "open_balance").errorDescription
        }
    }

    /// Closing goes back to the overview, where the group now sits under "Abgeschlossen".
    private func setClosed(_ closed: Bool, _ group: SplitGroup) async {
        let id = group.id
        if closed { dismiss() }
        await perform { try await $0.setClosed(closed, group: id) }
    }

    private func leave(_ group: SplitGroup) async {
        let id = group.id
        dismiss()
        await perform { try await $0.leaveGroup(id) }
    }

    private func leaveMessage(_ group: SplitGroup) -> String {
        group.leavingDeletes(userID: model.userID)
            ? String(localized: "Du bist die letzte Person mit Barte in dieser Gruppe. Wenn du gehst, wird sie mit allen Ausgaben gelöscht.")
            : String(localized: "Die Gruppe verschwindet bei dir. Die anderen behalten sie, dein Name bleibt in den Ausgaben stehen.")
    }

    struct Month { let title: String; let expenses: [Expense] }

    static func months(of expenses: [Expense]) -> [Month] {
        let calendar = Calendar.current
        var result: [Month] = []
        for expense in expenses {
            let start = calendar.dateInterval(of: .month, for: expense.date)?.start ?? expense.date
            let isThisYear = calendar.isDate(start, equalTo: .now, toGranularity: .year)
            let title = start.formatted(isThisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
            if result.last?.title == title {
                result[result.count - 1] = Month(title: title, expenses: result[result.count - 1].expenses + [expense])
            } else {
                result.append(Month(title: title, expenses: [expense]))
            }
        }
        return result
    }
}

/// One expense: icon, title, who paid, the amount and what it means for me.
struct ExpenseRow: View {
    let expense: Expense
    let group: SplitGroup
    let me: UUID?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ExpenseIcon.symbol(for: expense.title, isSettlement: expense.isSettlement))
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(expense.isSettlement ? Color.positive : group.color.tint, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.isSettlement ? String(localized: "Ausgleich", comment: "A payment that settles a debt") : expense.title)
                    .font(.body)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(expense.amountCents, currency: group.currency))
                    .font(.amount)
                if let impact {
                    Text(impact.text)
                        .font(.caption)
                        .foregroundStyle(impact.color)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let day = expense.date.formatted(.dateTime.day().month(.abbreviated))
        if expense.isSettlement {
            let to = expense.participantIDs.first.map { group.name(of: $0, me: me) } ?? "?"
            return "\(group.name(of: expense.payerID, me: me)) → \(to) · \(day)"
        }
        let paid = expense.payerID == me
            ? String(localized: "von dir · \(day)", comment: "Expense row: I paid, on this day")
            : String(localized: "von \(group.member(expense.payerID)?.name ?? "?") · \(day)", comment: "Expense row: who paid, on this day")
        // Edits are part of the history; the row says so, the details are one tap away.
        guard group.editedExpenseIDs.contains(expense.id) else { return paid }
        return "\(paid) · \(String(localized: "bearbeitet", comment: "Expense row: the expense was edited"))"
    }

    private var impact: (text: String, color: Color)? {
        guard let me, !expense.isSettlement else { return nil }
        let share = expense.shares[me] ?? 0
        if expense.payerID == me {
            let lent = expense.amountCents - share
            return lent > 0
                ? (String(localized: "du bekommst \(Money.format(lent, currency: group.currency))"), .positive)
                : (String(localized: "nur für dich"), .inkSecondary)
        }
        if share > 0 { return (String(localized: "dein Anteil \(Money.format(share, currency: group.currency))"), .negative) }
        return (String(localized: "nicht beteiligt"), .inkSecondary)
    }
}
