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
    @State private var showsWhoAmI = false
    @State private var confirmsDelete = false
    @State private var settlementToDelete: Expense?
    @State private var showsInvite = false
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
                GroupCard(group: group, me: me)
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
                                    Task { await perform { try await $0.deleteExpense(expense.id, in: groupID) } }
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
        .sheet(isPresented: $showsNewExpense) { ExpenseEditorSheet(group: group, expense: nil, me: me) }
        .sheet(item: $editingExpense) { ExpenseEditorSheet(group: group, expense: $0, me: me) }
        .sheet(isPresented: $showsSettle) { SettleUpSheet(groupID: group.id) }
        .sheet(isPresented: $showsEdit) { GroupEditorSheet(group: group) { _ in } }
        .sheet(isPresented: $showsWhoAmI) { WhoAmISheet(group: group) }
        .sheet(isPresented: $showsInvite) { InviteSheet(groupID: group.id) }
        .confirmationDialog(
            canDelete(group) ? "Gruppe löschen?" : "Gruppe verlassen?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(canDelete(group) ? "Löschen" : "Verlassen", role: .destructive) {
                Task { await removeGroup(group) }
            }
        } message: {
            Text(deleteMessage(group))
        }
        .confirmationDialog("Ausgleich löschen?", isPresented: .init(
            get: { settlementToDelete != nil }, set: { if !$0 { settlementToDelete = nil } }
        ), titleVisibility: .visible, presenting: settlementToDelete) { settlement in
            Button("Löschen", role: .destructive) { Task { await perform { try await $0.deleteExpense(settlement.id, in: groupID) } } }
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
        if group.isSettled {
            Label(group.expenses.isEmpty ? "Noch nichts auszugleichen" : "Alle sind quitt", systemImage: "checkmark.seal.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(group.expenses.isEmpty ? Color.inkSecondary : Color.positive)
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
                    Text(count == 1 ? "1 Überweisung" : "\(count) Überweisungen")
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
        ToolbarItem(placement: .topBarTrailing) {
            Button("Einladen", systemImage: "person.crop.circle.badge.plus") { showsInvite = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Mehr", systemImage: "ellipsis") {
                Button("Gruppe bearbeiten", systemImage: "pencil") { showsEdit = true }
                Button("Das bin nicht ich", systemImage: "person.fill.questionmark") { showsWhoAmI = true }
                Divider()
                Button(canDelete(group) ? "Gruppe löschen" : "Gruppe verlassen",
                       systemImage: canDelete(group) ? "trash" : "rectangle.portrait.and.arrow.right",
                       role: .destructive) { confirmsDelete = true }
            }
        }
    }

    // MARK: Actions

    private func appear(_ group: SplitGroup, me: UUID?) {
        guard !didAppear else { return }
        didAppear = true
        guard model.isDemo else { return }
        switch DemoData.argument(after: "-BarteSheet") {
        case "settle": showsSettle = true
        case "expense": showsNewExpense = true
        case "invite": showsInvite = true
        default: break
        }
    }

    private func perform(_ work: @escaping @Sendable (GroupRepository) async throws -> Void) async {
        if let message = await model.run(work) { alertMessage = message }
    }

    private func canDelete(_ group: SplitGroup) -> Bool { group.canDelete(userID: model.userID) }

    private func removeGroup(_ group: SplitGroup) async {
        let id = group.id
        let deletes = canDelete(group)
        dismiss()
        await perform { repository in
            if deletes { try await repository.deleteGroup(id) } else { try await repository.leaveGroup(id) }
        }
    }

    private func deleteMessage(_ group: SplitGroup) -> String {
        let others = group.members.contains { $0.usesApp && $0.userID != model.userID }
        if !canDelete(group) {
            return "Die Gruppe verschwindet bei dir. Die anderen behalten sie, dein Name bleibt in den Ausgaben stehen."
        }
        return others
            ? "Die Gruppe wird für alle gelöscht, auch für die, die du eingeladen hast."
            : "Alle Ausgaben dieser Gruppe werden gelöscht."
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
                Text(expense.isSettlement ? "Ausgleich" : expense.title)
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
        let payer = expense.payerID == me ? "dir" : group.member(expense.payerID)?.name ?? "?"
        return "von \(payer) · \(day)"
    }

    private var impact: (text: String, color: Color)? {
        guard let me, !expense.isSettlement else { return nil }
        let share = expense.shares[me] ?? 0
        if expense.payerID == me {
            let lent = expense.amountCents - share
            return lent > 0 ? ("du bekommst \(Money.format(lent, currency: group.currency))", .positive) : ("nur für dich", .inkSecondary)
        }
        if share > 0 { return ("dein Anteil \(Money.format(share, currency: group.currency))", .negative) }
        return ("nicht beteiligt", .inkSecondary)
    }
}
