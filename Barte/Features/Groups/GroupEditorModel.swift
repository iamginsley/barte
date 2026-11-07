import Foundation
import Observation

/// Form state for creating a group or editing its name, color, currency and people.
@Observable
@MainActor
final class GroupEditorModel {
    struct Row: Identifiable, Hashable {
        let id: UUID
        /// The stored member, nil for people added in this form.
        let memberID: UUID?
        var name: String
        var isMe: Bool
        var usesApp = false
        var canRemove: Bool
    }

    let existing: SplitGroup?
    var name: String
    var color: CardColor
    var currency: String
    var rows: [Row]
    private(set) var removed: [UUID] = []

    init(group: SplitGroup?, me: UUID?) {
        existing = group
        name = group?.name ?? ""
        color = group?.color ?? CardColor.allCases.randomElement() ?? .blue
        currency = group?.currency ?? "EUR"
        if let group {
            rows = group.members.map {
                Row(id: $0.id, memberID: $0.id, name: $0.name, isMe: $0.id == me, usesApp: $0.usesApp, canRemove: !$0.usesApp && !group.isInvolved($0.id))
            }
        } else {
            rows = [
                Row(id: UUID(), memberID: nil, name: Preferences.myName, isMe: true, canRemove: false),
                Row(id: UUID(), memberID: nil, name: "", isMe: false, canRemove: true),
            ]
        }
    }

    var isNew: Bool { existing == nil }

    private var namedRows: [Row] { rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }

    var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !namedRows.isEmpty else { return false }
        // A new group needs my own name, so balances can say "Du".
        return !isNew || !(rows.first?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    /// Live preview of the card while editing.
    var preview: SplitGroup {
        SplitGroup(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? "Neue Gruppe" : name,
            currency: currency,
            color: color,
            createdAt: .now,
            members: namedRows.map { Member(id: $0.id, name: $0.name, userID: existing?.member($0.id)?.userID) },
            expenses: existing?.expenses ?? []
        )
    }

    var previewMe: UUID? { rows.first(where: \.isMe)?.id }

    func addRow() {
        rows.append(Row(id: UUID(), memberID: nil, name: "", isMe: false, canRemove: true))
    }

    func remove(at offsets: IndexSet) {
        for index in offsets where rows[index].canRemove {
            if let memberID = rows[index].memberID { removed.append(memberID) }
        }
        rows = rows.enumerated().filter { !offsets.contains($0.offset) || !$0.element.canRemove }.map(\.element)
    }

    /// Writes the changes. Returns the group's id, or a message when something failed.
    func save(with app: AppModel) async -> Result<UUID, SaveError> {
        let name = name.trimmingCharacters(in: .whitespaces)
        let currency = currency
        let color = color
        if let existing {
            let removed = removed
            let renamed = namedRows.compactMap { row in
                row.memberID.flatMap { id in existing.member(id)?.name != row.name ? (id, row.name) : nil }
            }
            let added = namedRows.filter { $0.memberID == nil }.map(\.name)
            let message = await app.run { repository in
                try await repository.updateGroup(existing.id, name: name, currency: currency, color: color)
                for id in removed { try await repository.removeMember(id, from: existing.id) }
                for (id, newName) in renamed { try await repository.renameMember(id, in: existing.id, to: newName) }
                for newName in added { _ = try await repository.addMember(named: newName, to: existing.id) }
            }
            return message.map { .failure(SaveError(message: $0)) } ?? .success(existing.id)
        }
        let myName = rows.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let others = namedRows.dropFirst().map(\.name)
        Preferences.myName = myName
        let result = await app.runReturning { repository in
            try await repository.createGroup(name: name, currency: currency, color: color, myName: myName, otherNames: Array(others))
        }
        return result.mapError { SaveError(message: $0.message) }
    }

    struct SaveError: Error { let message: String }
}
