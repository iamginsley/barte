import SwiftUI

struct GroupEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: GroupEditorModel?
    @FocusState private var focusedRow: UUID?
    @FocusState private var nameFocused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let group: SplitGroup?
    private let onSave: (UUID) -> Void

    init(group: SplitGroup?, onSave: @escaping (UUID) -> Void) {
        self.group = group
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            if let model {
                form(model)
            }
        }
        .onAppear {
            if model == nil { model = GroupEditorModel(group: group, me: group.flatMap { app.me(in: $0.id) }) }
        }
    }

    private func form(_ model: GroupEditorModel) -> some View {
        @Bindable var model = model
        return Form {
            Section {
                GroupCard(group: model.preview, me: model.previewMe)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .animation(.default, value: model.color)
            }

            Section {
                TextField("Name, z. B. Skiurlaub", text: $model.name)
                    .focused($nameFocused)
                    .submitLabel(.next)
                    .onSubmit { focusedRow = model.rows.first { $0.name.isEmpty }?.id }
                colorPicker(selection: $model.color)
                Picker("Währung", selection: $model.currency) {
                    ForEach(Money.currencies, id: \.self) { code in
                        Text("\(Money.name(for: code)) (\(Money.symbol(for: code)))").tag(code)
                    }
                }
            }

            Section {
                ForEach($model.rows) { $row in
                    HStack(spacing: 12) {
                        MemberAvatar(name: row.name, isMe: row.isMe, size: 30)
                        TextField(row.isMe ? "Dein Name" : "Name", text: $row.name)
                            .textContentType(row.isMe ? .givenName : nil)
                            .focused($focusedRow, equals: row.id)
                            .submitLabel(.next)
                            .onSubmit {
                                if row.id == model.rows.last?.id, !row.name.isEmpty { model.addRow() }
                                focusedRow = model.rows.last?.id
                            }
                        if row.isMe {
                            Text("Ich")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                        } else if row.usesApp {
                            Image(systemName: "iphone")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityLabel("nutzt Barte")
                        }
                    }
                    .deleteDisabled(!row.canRemove)
                }
                .onDelete { model.remove(at: $0) }
                Button("Person hinzufügen", systemImage: "person.badge.plus") {
                    model.addRow()
                    focusedRow = model.rows.last?.id
                }
                .frame(minHeight: Theme.minTapSize)
            } header: {
                Text("Wer ist dabei?")
            } footer: {
                Text(model.isNew
                     ? "Freund:innen brauchen die App nicht. Lade sie später mit einem Link ein, dann tragen alle selbst Ausgaben ein."
                     : "Personen, die in Ausgaben vorkommen oder Barte selbst nutzen, lassen sich nicht entfernen.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .navigationTitle(model.isNew ? "Neue Gruppe" : "Gruppe bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(model.isNew ? "Erstellen" : "Sichern", role: .confirm) {
                        Task { await save(model) }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
        .onAppear { if model.isNew { nameFocused = true } }
        .interactiveDismissDisabled(isSaving)
        .alert("Nicht gesichert", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save(_ model: GroupEditorModel) async {
        hideKeyboard()
        isSaving = true
        defer { isSaving = false }
        switch await model.save(with: app) {
        case .success(let id):
            dismiss()
            onSave(id)
        case .failure(let error):
            errorMessage = error.message
        }
    }

    private func colorPicker(selection: Binding<CardColor>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CardColor.allCases) { color in
                    let selected = selection.wrappedValue == color
                    Button {
                        selection.wrappedValue = color
                    } label: {
                        Circle()
                            .fill(color.gradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? color.tint : .clear, lineWidth: 2))
                            .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection.wrappedValue)
    }
}
