import UIKit
import UserNotifications

/// Owns the app model, so a tapped notification can open its group even on a cold start.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([Self.chatCategory])
        return true
    }

    /// Chat pushes (category set by the chat-message function) can be answered right from the banner.
    nonisolated static let replyAction = "REPLY"
    static let chatCategory = UNNotificationCategory(
        identifier: "CHAT_MESSAGE",
        actions: [UNTextInputNotificationAction(
            identifier: replyAction, title: "Antworten", options: [.authenticationRequired],
            textInputButtonTitle: "Senden", textInputPlaceholder: "Nachricht"
        )],
        intentIdentifiers: [],
        options: []
    )

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushToken.update(deviceToken, api: model.api) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No push on this device (simulator without APNs, no signing). Everything else still works.
    }

    // Banners also while the app is open: someone else's expense is news even then.
    // Only the chat that is already on screen stays quiet.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let link = Self.link(of: notification)
        let visible = await MainActor.run { model.visibleChatGroupID }
        if let link, BarteLink.opensChat(link), let id = BarteLink.groupID(from: link), id == visible { return [] }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = Self.link(of: response.notification) else { return }
        if response.actionIdentifier == Self.replyAction, let reply = response as? UNTextInputNotificationResponse,
           let groupID = BarteLink.groupID(from: link) {
            let text = reply.userText
            await send(text, to: groupID)
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { model.open(link) }
        }
    }

    private func send(_ text: String, to groupID: UUID) async {
        await model.sendReply(text, to: groupID)
    }

    nonisolated private static func link(of notification: UNNotification) -> URL? {
        (notification.request.content.userInfo["link"] as? String).flatMap(URL.init(string:))
    }
}
