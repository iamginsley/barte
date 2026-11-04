import SwiftUI

/// Asks which member is "me" on this device, e.g. after joining a shared group.
struct WhoAmISheet: View {
    let group: SplitGroup

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newName = Identity.myName

    var body: some View {
        let me = model.me(in: group.id)
        NavigationStack {
            List {
                Section {
                    ForEach(group.members) { member in
                        Button {
                            model.setMe(member.id, in: group.id)
                            if Identity.myName.isEmpty { Identity.myName = member.name }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatar(name: member.name, isMe: member.id == me)
                                Text(member.name)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                if member.id == me {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(minHeight: Theme.minTapSize)
                        }
                        .accessibilityAddTraits(member.id == me ? .isSelected : [])
                    }
                } footer: {
                    Text("Barte merkt sich das nur auf diesem iPhone, damit du deinen eigenen Saldo siehst.")
                }

                Section("Nicht dabei?") {
                    TextField("Dein Name", text: $newName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit(addMe)
                    Button("Mich zur Gruppe hinzufügen", systemImage: "person.badge.plus", action: addMe)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Wer bist du?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Später", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addMe() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = model.repository.addMember(named: name, to: group.id) else { return }
        Identity.myName = name
        model.setMe(id, in: group.id)
        dismiss()
    }
}
