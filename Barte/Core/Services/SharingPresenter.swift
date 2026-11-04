@preconcurrency import CloudKit
import UIKit

/// Shows Apple's sharing sheet for a group (invite via Messages, link, manage people, stop sharing).
@MainActor
final class SharingPresenter: NSObject, UICloudSharingControllerDelegate {
    static let shared = SharingPresenter()

    private var persistence: Persistence?
    private var title = ""

    func present(share: CKShare, title: String, persistence: Persistence) {
        self.persistence = persistence
        self.title = title
        let controller = UICloudSharingController(share: share, container: persistence.ckContainer)
        controller.delegate = self
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        Self.topViewController()?.present(controller, animated: true)
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {}

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        guard let share = csc.share else { return }
        persistence?.persistUpdatedShare(share)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        persistence?.context.refreshAllObjects()
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
