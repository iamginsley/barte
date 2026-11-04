import SwiftUI

struct ExpenseEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExpenseEditorModel
    @State private var confirmsDelete = false
    @FocusState private var focus: Field?
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 56

    private enum Field { case amount, title }

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
                    ForEach(group.members) { member in
                        participantRow(member)
                    }
                } header: {
                    HStack {
                        Text("Aufgeteilt auf")
                        Spacer()
                        Button(model.allSelected ? "Keine" : "Alle") { model.toggleAll() }
                            .font(.subheadline)
                            .textCase(nil)
                    }
                } footer: {
                    if model.participants.isEmpty {
                        Text("Wähle mindestens eine Person aus.")
                    } else if let text = model.perPersonText {
                        Text(text)
                    }
                }

                if model.existing != nil {
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
                    Button("Sichern", role: .confirm, action: save)
                        .disabled(!model.canSave)
                }
            }
            .confirmationDialog("Ausgabe löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let id = model.existing?.id { app.repository.deleteExpense(id) }
                    dismiss()
                }
            }
            .onAppear {
                if model.existing == nil { focus = .amount }
            }
        }
        .interactiveDismissDisabled(model.existing == nil && !model.amountText.isEmpty)
    }

    private func participantRow(_ member: Member) -> some View {
        let selected = model.participants.contains(member.id)
        return Button {
            model.toggle(member.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.inkSecondary))
                    .contentTransition(.symbolEffect(.replace))
                MemberAvatar(name: member.name, isMe: member.id == model.me, size: 30)
                Text(member.id == model.me ? "\(member.name) (ich)" : member.name)
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

    private func save() {
        guard let expense = model.makeExpense() else { return }
        app.repository.save(expense, in: model.group.id)
        dismiss()
    }
}
