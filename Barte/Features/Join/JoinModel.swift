import Foundation
import Observation

/// Joining a group with an invite code: look it up, pick who I am, join.
@Observable
@MainActor
final class JoinModel {
    enum Step: Equatable {
        case enterCode
        case loading
        case choose(InvitePreview)
        case alreadyMember(UUID)
    }

    /// Which name I'll be: an unclaimed member, or a new person.
    enum Choice: Hashable {
        case member(UUID)
        case new
    }

    private(set) var step: Step
    var codeText: String
    var choice: Choice?
    var newName = Preferences.myName
    private(set) var isJoining = false
    var errorMessage: String?

    init(code: String?) {
        codeText = code ?? ""
        step = code == nil ? .enterCode : .loading
    }

    var code: String? { InviteLink.normalize(codeText) }

    var canJoin: Bool {
        switch choice {
        case .member: true
        case .new: !newName.trimmingCharacters(in: .whitespaces).isEmpty
        case nil: false
        }
    }

    func lookUp(with repository: GroupRepository?) async {
        guard let repository, let code else {
            errorMessage = "Das sieht nicht nach einem Einladungscode aus."
            return
        }
        step = .loading
        errorMessage = nil
        do {
            let preview = try await repository.previewInvite(code: code)
            if preview.isMember {
                step = .alreadyMember(preview.groupID)
                return
            }
            // Suggest the unclaimed name that matches mine, else a new person.
            let mine = Preferences.myName.lowercased()
            choice = preview.members.first { !$0.isClaimed && !mine.isEmpty && $0.name.lowercased() == mine }.map { .member($0.id) }
            // Don't show my name twice: once as the match, once in the "new person" field.
            if choice != nil { newName = "" }
            step = .choose(preview)
        } catch {
            step = .enterCode
            errorMessage = BarteError.from(error).errorDescription
        }
    }

    /// Returns the group's id when joined.
    func join(with app: AppModel) async -> UUID? {
        guard let code, let choice else { return nil }
        isJoining = true
        defer { isJoining = false }
        let name = newName.trimmingCharacters(in: .whitespaces)
        let memberID: UUID? = if case .member(let id) = choice { id } else { nil }
        let result = await app.runReturning { repository in
            try await repository.joinGroup(code: code, memberID: memberID, name: memberID == nil ? name : nil)
        }
        switch result {
        case .success(let id):
            if memberID == nil { Preferences.myName = name }
            return id
        case .failure(let failure):
            errorMessage = failure.message
            return nil
        }
    }
}
