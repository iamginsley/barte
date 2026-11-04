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
                Row(id: $0.id, memberID: $0.id, name: $0.name, isMe: $0.id == me, canRemove: !group.isInvolved($0.id))
            }
        } else {
            rows = [
                Row(id: UUID(), memberID: nil, name: Identity.myName, isMe: true, canRemove: false),
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
            members: namedRows.map { Member(id: $0.id, name: $0.name) },
            expenses: existing?.expenses ?? [],
            sharing: existing?.sharing ?? .personal
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

    /// Writes the changes. Returns the group's id.
    func save(to repository: GroupRepository) -> UUID {
        if let existing {
            repository.updateGroup(existing.id, name: name, currency: currency, color: color)
            for memberID in removed { try? repository.removeMember(memberID) }
            for row in namedRows {
                if let memberID = row.memberID {
                    if existing.member(memberID)?.name != row.name { repository.renameMember(memberID, to: row.name) }
                } else {
                    repository.addMember(named: row.name, to: existing.id)
                }
            }
            return existing.id
        }
        Identity.myName = rows.first?.name ?? ""
        return repository.createGroup(name: name, currency: currency, color: color, memberNames: namedRows.map(\.name))
    }
}
