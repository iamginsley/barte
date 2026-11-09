import SwiftUI

struct ExpenseEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExpenseEditorModel
    @State private var confirmsDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 56

    private enum Field: Hashable { case amount, title, exact(UUID) }

    init(group: SplitGroup, expense: Expense?, me: UUID?) {
        _model = State(initialValue: ExpenseEditorModel(group: group, expense: expense, me: me))
    }

    var body: some View {
        @Bindable var model = model
        let group = model.group
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("0,00", text: $model.amountText)
                            .font(.system(size: amountSize, weight: .bold, design: .rounded).monospacedDigit())
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .amount)
                            .fixedSize()
                            .accessibilityLabel("Betrag")
                        Text(Money.symbol(for: group.currency))
                            .font(.system(size: amountSize * 0.55, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.inkSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { focus = .amount }
                    .listRowBackground(Color.clear)
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: ExpenseIcon.symbol(for: model.title))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(group.color.tint, in: .rect(cornerRadius: 9, style: .continuous))
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                        TextField("Wofür?", text: $model.title)
                            .focused($focus, equals: .title)
                            .submitLabel(.done)
                            .onSubmit { focus = nil }
                    }
                    Picker("Bezahlt von", selection: $model.payerID) {
                        ForEach(group.members) { member in
                            Text(member.id == model.me ? "\(member.name) (ich)" : member.name).tag(member.id)
                        }
                    }
                    DatePicker("Datum", selection: $model.date, displayedComponents: .date)
                }

                Section {
                    Picker("Aufteilung", selection: Binding(get: { model.mode }, set: { mode in
                        focus = nil
                        withAnimation(reduceMotion ? nil : .snappy) { model.setMode(mode) }
                    })) {
                        ForEach(ExpenseEditorModel.Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    ForEach(group.members) { member in
                        switch model.mode {
                        case .equal: participantRow(member)
                        case .shares: weightRow(member)
                        case .exact: exactRow(member)
                        }
                    }
                } header: {
                    HStack {
                        Text("Aufgeteilt auf")
                        Spacer()
                        if model.mode == .equal {
                            Button(model.allSelected ? "Keine" : "Alle") { model.toggleAll() }
                                .font(.subheadline)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    if let text = model.footerText {
                        Text(text)
                            .foregroundStyle((model.exactDifference ?? 0) != 0 ? Color.negative : Color.inkSecondary)
                            .contentTransition(.numericText())
                    }
                }

                if let existing = model.existing {
                    Section {
                        NavigationLink {
                            HistoryList(group: group, subjectID: existing.id)
                                .navigationTitle("Verlauf")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label(group.editedExpenseIDs.contains(existing.id) ? "Verlauf · bearbeitet" : "Verlauf", systemImage: "clock.arrow.circlepath")
                        }
                        if group.isShared {
                            NavigationLink {
                                ChatView(groupID: group.id, reference: existing, opensExpenses: false)
                            } label: {
                                Label("Im Chat ansprechen", systemImage: "bubble.left")
                            }
                        }
                    } footer: {
                        Text("Jede Änderung bleibt für alle in der Gruppe sichtbar.")
                    }
                    Section {
                        Button("Ausgabe löschen", role: .destructive) { confirmsDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .navigationTitle(model.existing == nil ? "Neue Ausgabe" : "Ausgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Sichern", role: .confirm) { Task { await save() } }
                            .disabled(!model.canSave)
                    }
                }
            }
            .confirmationDialog("Ausgabe löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { Task { await delete() } }
            }
            .alert("Das hat nicht geklappt", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if model.existing == nil { focus = .amount }
            }
        }
        .interactiveDismissDisabled(isSaving || (model.existing == nil && !model.amountText.isEmpty))
    }

    private func participantRow(_ member: Member) -> some View {
        let selected = model.isSelected(member.id)
        return Button {
            model.toggle(member.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.inkSecondary))
                    .contentTransition(.symbolEffect(.replace))
                MemberAvatar(name: member.name, isMe: member.id == model.me, size: 30)
                Text(memberName(member))
                    .foregroundStyle(Color.ink)
                Spacer()
                if selected, let share = model.shares[member.id], share > 0 {
                    Text(Money.format(share, currency: model.group.currency))
                        .font(.amount)
                        .foregroundStyle(Color.inkSecondary)
                        .contentTransition(.numericText())
                }
            }
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func memberName(_ member: Member) -> String {
        member.id == model.me ? "\(member.name) (ich)" : member.name
    }

    /// Shares mode: tap the row to include someone, the stepper for couples and families.
    private func weightRow(_ member: Member) -> some View {
        let weight = model.weights[member.id] ?? 0
        let share = model.shares[member.id] ?? 0
        return HStack(spacing: 12) {
            Button {
                model.toggle(member.id)
            } label: {
                HStack(spacing: 12) {
                    MemberAvatar(name: member.name, isMe: member.id == model.me, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(memberName(member))
                            .foregroundStyle(weight > 0 ? Color.ink : Color.inkSecondary)
                        if share > 0 {
                            Text(Money.format(share, currency: model.group.currency))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.inkSecondary)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer(minLength: 4)
                }
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            Text(weight == 0 ? "–" : "\(weight)×")
                .font(.amount)
                .foregroundStyle(weight > 0 ? Color.ink : Color.inkSecondary)
                .frame(minWidth: 32, alignment: .trailing)
                .contentTransition(.numericText())
                .accessibilityHidden(true)
            Stepper("Anteile", value: Binding(get: { weight }, set: { model.weights[member.id] = $0 }), in: 0...ExpenseEditorModel.maxWeight)
                .labelsHidden()
                .accessibilityLabel(memberName(member))
                .accessibilityValue(weight == 0 ? "nicht beteiligt" : "\(weight) \(weight == 1 ? "Anteil" : "Anteile"), \(Money.format(share, currency: model.group.currency))")
        }
        .sensoryFeedback(.selection, trigger: weight)
    }

    /// Exact mode: a fixed amount per person. Tapping the name puts the rest on them.
    private func exactRow(_ member: Member) -> some View {
        let text = Binding(get: { model.exactTexts[member.id] ?? "" }, set: { model.exactTexts[member.id] = $0 })
        let canTakeRest = (model.exactDifference ?? 0) < 0 || ((model.exactDifference ?? 0) > 0 && (model.exactCents(member.id) ?? 0) > 0)
        return HStack(spacing: 12) {
            MemberAvatar(name: member.name, isMe: member.id == model.me, size: 30)
                .accessibilityHidden(true)
            Text(memberName(member))
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            if canTakeRest {
                Button("Rest") { model.assignRest(to: member.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: Theme.minTapSize)
                    .accessibilityLabel("Rest auf \(member.name)")
            }
            TextField("0,00", text: text)
                .font(.amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: .exact(member.id))
                .frame(width: 96)
                .frame(minHeight: Theme.minTapSize)
                .accessibilityLabel("Betrag für \(member.name)")
            Text(Money.symbol(for: model.group.currency))
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus = .exact(member.id) }
    }

    private func save() async {
        guard let expense = model.makeExpense() else { return }
        focus = nil
        isSaving = true
        defer { isSaving = false }
        let groupID = model.group.id
        if let message = await app.run({ try await $0.save(expense, in: groupID) }) {
            errorMessage = message
        } else {
            dismiss()
        }
    }

    private func delete() async {
        guard let id = model.existing?.id else { return }
        if let message = await app.run({ try await $0.deleteExpense(id) }) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}
