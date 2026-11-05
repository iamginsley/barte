import SwiftUI

/// Invite friends: a link to send and the code to read out loud.
struct InviteSheet: View {
    let groupID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let group = model.group(groupID) {
                    content(group)
                }
            }
            .navigationTitle("Freund:innen einladen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func content(_ group: SplitGroup) -> some View {
        let url = InviteLink.url(for: group.inviteCode)
        let unclaimed = group.members.filter { !$0.usesApp }.map(\.name)
        return List {
            Section {
                VStack(spacing: 6) {
                    Text("Einladungscode")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                    Text(Self.spaced(group.inviteCode))
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityLabel(group.inviteCode.map(String.init).joined(separator: " "))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                ShareLink(item: url, message: Text(InviteLink.message(groupName: group.name, code: group.inviteCode))) {
                    Label("Link senden", systemImage: "square.and.arrow.up")
                        .frame(minHeight: Theme.minTapSize)
                }
                Button {
                    UIPasteboard.general.url = url
                    copied = true
                } label: {
                    Label(copied ? "Kopiert" : "Link kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minHeight: Theme.minTapSize)
                }
                .sensoryFeedback(.success, trigger: copied)
            } footer: {
                if unclaimed.isEmpty {
                    Text("Wer den Link öffnet, meldet sich an und ist dabei. Alle tragen dann selbst Ausgaben ein.")
                } else {
                    Text("Wer den Link öffnet, wählt einen Namen aus der Gruppe (\(unclaimed.formatted(.list(type: .or)))) und trägt dann selbst Ausgaben ein.")
                }
            }
        }
    }

    /// "SKI2FUN7" → "SKI2 FUN7", easier to read out loud.
    static func spaced(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }
}
