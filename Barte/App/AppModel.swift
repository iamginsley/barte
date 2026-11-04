@preconcurrency import CoreData
import Foundation
import Observation

/// App-wide state: the list of groups, refreshed whenever the store changes
/// (local edits as well as changes merged in from iCloud).
@Observable
@MainActor
final class AppModel {
    let repository: GroupRepository
    let isDemo: Bool
    private(set) var groups: [SplitGroup] = []
    /// Bumps when "who am I" changes, so views re-read `Identity`.
    private(set) var identityVersion = 0

    init(persistence: Persistence, isDemo: Bool) {
        repository = GroupRepository(persistence: persistence)
        self.isDemo = isDemo
        reload()
        NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didChangeObjectsNotification,
            object: persistence.context,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        groups = repository.fetchGroups()
    }

    func group(_ id: UUID) -> SplitGroup? { groups.first { $0.id == id } }

    func me(in groupID: UUID) -> UUID? {
        _ = identityVersion
        return Identity.me(in: groupID)
    }

    func setMe(_ memberID: UUID?, in groupID: UUID) {
        Identity.setMe(memberID, in: groupID)
        identityVersion += 1
    }
}
