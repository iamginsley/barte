import SwiftUI

/// Opens from an invite link or "Mit Code beitreten": shows the group's card and asks who I am.
struct JoinSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: JoinModel
    @FocusState private var focus: Field?

    private enum Field { case code, name }
    private let onJoin: (UUID) -> Void

    init(code: String?, onJoin: @escaping (UUID) -> Void) {
        _model = State(initialValue: JoinModel(code: code))
        self.onJoin = onJoin
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Beitreten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", role: .cancel) { dismiss() }
                    }
                    if case .choose = model.step {
                        ToolbarItem(placement: .confirmationAction) {
                            if model.isJoining {
                                ProgressView()
                            } else {
                                Button("Beitreten", role: .confirm) { Task { await join() } }
                                    .disabled(!model.canJoin)
                            }
                        }
                    }
                }
        }
        .task {
            if model.step == .loading { await model.lookUp(with: app.repository) }
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        switch model.step {
        case .enterCode:
            Form {
                Section {
                    TextField("Code, z. B. SKI2FUN7", text: $model.codeText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .focused($focus, equals: .code)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.lookUp(with: app.repository) } }
                } footer: {
                    if let message = model.errorMessage {
                        Text(message).foregroundStyle(Color.negative)
                    } else {
                        Text("Den Code findest du in der Einladung. Ein eingefügter Link geht auch.")
                    }
                }
                Section {
                    Button("Gruppe suchen") { Task { await model.lookUp(with: app.repository) } }
                        .disabled(model.code == nil)
                        .frame(minHeight: Theme.minTapSize)
                }
            }
            .onAppear { focus = .code }
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .alreadyMember(let id):
            ContentUnavailableView {
                Label("Du bist schon dabei", systemImage: "checkmark.seal.fill")
            } description: {
                Text("Diese Gruppe ist bereits in deinem Stapel.")
            } actions: {
                Button("Gruppe öffnen") {
                    dismiss()
                    onJoin(id)
                }
                .buttonStyle(.borderedProminent)
            }
        case .choose(let preview):
            chooser(preview)
        }
    }

    private func chooser(_ preview: InvitePreview) -> some View {
        @Bindable var model = model
        let open = preview.members.filter { !$0.isClaimed }
        return Form {
            Section {
                GroupCard(group: preview.card, me: nil, showsStatus: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(open) { person in
                    choiceRow(.member(person.id)) {
                        MemberAvatar(name: person.name, isMe: model.choice == .member(person.id), size: 30)
                        Text(person.name)
                    }
                }
                choiceRow(.new) {
                    if model.newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: "person.badge.plus")
                            .font(.body)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                    } else {
                        MemberAvatar(name: model.newName, isMe: model.choice == .new, size: 30)
                    }
                    TextField(open.isEmpty ? "Dein Name" : "Nicht dabei? Dein Name", text: $model.newName)
                        .textContentType(.givenName)
                        .focused($focus, equals: .name)
                        .submitLabel(.join)
                        .onSubmit { if model.canJoin { Task { await join() } } }
                        .onChange(of: focus) { if focus == .name { model.choice = .new } }
                }
            } header: {
                Text("Wer bist du?")
            } footer: {
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(Color.negative)
                } else if !open.isEmpty {
                    Text("Wähle deinen Namen, dann gehören die Ausgaben, die schon eingetragen sind, zu dir.")
                }
            }

            let taken = preview.members.filter(\.isClaimed)
            if !taken.isEmpty {
                Section("Schon mit Barte dabei") {
                    ForEach(taken) { person in
                        HStack(spacing: 12) {
                            MemberAvatar(name: person.name, isMe: false, size: 30)
                            Text(person.name)
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .onAppear { if open.isEmpty { model.choice = .new } }
    }

    private func choiceRow<Label: View>(_ choice: JoinModel.Choice, @ViewBuilder label: () -> Label) -> some View {
        let selected = model.choice == choice
        let row = HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.inkSecondary))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            label()
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.minTapSize)
        .contentShape(Rectangle())
        .sensoryFeedback(.selection, trigger: selected)
        return Group {
            if choice == .new {
                // Holds a text field, so it can't be one button; focusing the field selects it.
                row.onTapGesture {
                    model.choice = .new
                    focus = .name
                }
            } else {
                Button {
                    model.choice = choice
                    focus = nil
                } label: {
                    row
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func join() async {
        focus = nil
        guard let id = await model.join(with: app) else { return }
        dismiss()
        onJoin(id)
    }
}
