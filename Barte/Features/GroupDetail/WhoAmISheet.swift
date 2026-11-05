import SwiftUI

/// "That's not me": switches which name in the group belongs to me.
struct WhoAmISheet: View {
    let group: SplitGroup

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newName = Preferences.myName
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        let me = model.me(in: group.id)
        NavigationStack {
            List {
                Section {
                    ForEach(group.members) { member in
                        let isMe = member.id == me
                        let takenByOther = member.usesApp && !isMe
                        Button {
                            Task { await claim(member.id) }
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatar(name: member.name, isMe: isMe)
                                Text(member.name)
                                    .foregroundStyle(takenByOther ? Color.inkSecondary : Color.ink)
                                Spacer()
                                if isMe {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                } else if takenByOther {
                                    Text("nutzt Barte")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                            .frame(minHeight: Theme.minTapSize)
                        }
                        .disabled(takenByOther || isMe || isWorking)
                        .accessibilityAddTraits(isMe ? .isSelected : [])
                    }
                } footer: {
                    Text(errorMessage ?? "Wähle den Namen, unter dem deine Ausgaben eingetragen sind. Namen von Personen, die Barte selbst nutzen, sind vergeben.")
                        .foregroundStyle(errorMessage == nil ? Color.inkSecondary : Color.negative)
                }

                Section("Nicht in der Liste?") {
                    TextField("Dein Name", text: $newName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit { Task { await addMe() } }
                    Button("Mich als neue Person eintragen", systemImage: "person.badge.plus") { Task { await addMe() } }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Wer bist du?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func claim(_ memberID: UUID) async {
        isWorking = true
        defer { isWorking = false }
        if let message = await model.run({ try await $0.claimMember(memberID) }) {
            errorMessage = message
        } else {
            dismiss()
        }
    }

    private func addMe() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let groupID = group.id
        isWorking = true
        defer { isWorking = false }
        let message = await model.run { repository in
            let id = try await repository.addMember(named: name, to: groupID)
            try await repository.claimMember(id)
        }
        if let message {
            errorMessage = message
        } else {
            Preferences.myName = name
            dismiss()
        }
    }
}
