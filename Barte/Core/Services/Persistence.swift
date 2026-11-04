@preconcurrency import CloudKit
@preconcurrency import CoreData
import OSLog

/// Owns the Core Data stack. Groups live in two stores synced by CloudKit:
/// the private database (groups this person created) and the shared database
/// (groups friends shared with them). In demo mode a single in-memory store is used.
@MainActor
final class Persistence {
    static let containerIdentifier = "iCloud.com.iamginsley.barte"
    private static let log = Logger(subsystem: "com.iamginsley.barte", category: "Persistence")

    let container: NSPersistentContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var context: NSManagedObjectContext { container.viewContext }
    var cloudKitContainer: NSPersistentCloudKitContainer? { container as? NSPersistentCloudKitContainer }
    var ckContainer: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    init(inMemory: Bool) {
        let privateURL: URL
        let sharedURL: URL?
        if inMemory {
            container = NSPersistentContainer(name: "Barte")
            privateURL = URL(fileURLWithPath: "/dev/null")
            sharedURL = nil
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: privateURL)]
        } else {
            let cloud = NSPersistentCloudKitContainer(name: "Barte")
            let directory = NSPersistentContainer.defaultDirectoryURL()
            privateURL = directory.appending(path: "private.sqlite")
            sharedURL = directory.appending(path: "shared.sqlite")
            cloud.persistentStoreDescriptions = [
                Self.description(url: privateURL, scope: .private),
                Self.description(url: sharedURL!, scope: .shared),
            ]
            container = cloud
        }

        container.loadPersistentStores { description, error in
            if let error {
                Self.log.error("Loading store \(description.url?.lastPathComponent ?? "?") failed: \(error)")
            }
        }
        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: privateURL)
        sharedStore = sharedURL.flatMap { coordinator.persistentStore(for: $0) }

        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "app"
    }

    private static func description(url: URL, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Self.log.error("Save failed: \(error)")
            context.rollback()
        }
    }

    /// Creates the CloudKit schema in the development environment (launch flag `-BarteInitSchema`, Debug only).
    func initializeCloudKitSchemaIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-BarteInitSchema") else { return }
        do {
            try cloudKitContainer?.initializeCloudKitSchema()
            Self.log.info("CloudKit schema initialized")
        } catch {
            Self.log.error("CloudKit schema init failed: \(error)")
        }
        #endif
    }
}

// MARK: - Sharing

extension Persistence {
    func isInSharedStore(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }

    /// Existing shares for the given objects (owner and participant side).
    func shares(for objectIDs: [NSManagedObjectID]) -> [NSManagedObjectID: CKShare] {
        guard let cloudKitContainer, !objectIDs.isEmpty else { return [:] }
        return (try? cloudKitContainer.fetchShares(matching: objectIDs)) ?? [:]
    }

    /// The share for a group, creating one on first use.
    func share(for group: GroupEntity) async throws -> CKShare {
        if let existing = shares(for: [group.objectID])[group.objectID] { return existing }
        guard let cloudKitContainer else { throw CocoaError(.featureUnsupported) }
        let title = group.name ?? "Barte"
        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            cloudKitContainer.share([group], to: nil) { _, share, _, error in
                if let share {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileWriteUnknown))
                }
            }
        }
        share[CKShare.SystemFieldKey.title] = title
        return share
    }

    func persistUpdatedShare(_ share: CKShare) {
        guard let cloudKitContainer, let privateStore else { return }
        cloudKitContainer.persistUpdatedShare(share, in: privateStore) { _, error in
            if let error { Self.log.error("Persisting share failed: \(error)") }
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let cloudKitContainer, let sharedStore else { return }
        cloudKitContainer.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error { Self.log.error("Accepting share failed: \(error)") }
        }
    }

    /// Leaves a group someone else shared: removes the local copy and this person's participation.
    func leave(_ group: GroupEntity) {
        guard let cloudKitContainer, let sharedStore,
              let share = shares(for: [group.objectID])[group.objectID] else {
            context.delete(group)
            save()
            return
        }
        cloudKitContainer.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore) { _, error in
            if let error { Self.log.error("Leaving share failed: \(error)") }
        }
    }
}
