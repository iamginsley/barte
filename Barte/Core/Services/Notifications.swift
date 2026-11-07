import FirebaseAuth
import FirebaseFunctions
import UIKit
import UserNotifications

/// Permission and the push device token.
enum Notifications {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once, at a moment where it makes sense (joining or inviting). Later calls do nothing.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        guard !DemoData.isEnabled else { return false }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// Asks APNs for a token whenever notifications are allowed; the AppDelegate hands it to `PushToken`.
    static func registerForPushIfAllowed() async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        await UIApplication.shared.registerForRemoteNotifications()
    }
}

/// The device token lives here between APNs handing it over and a signed-in session to store it with.
/// The server pushes new expenses and paybacks to the others in a group (functions/src/push).
@MainActor
enum PushToken {
    private(set) static var current: String?

    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private struct Device: Encodable, Sendable {
        let token: String
        let environment: String?
    }

    private struct Empty: Decodable, Sendable {}

    static func update(_ data: Data) async {
        current = data.map { String(format: "%02x", $0) }.joined()
        await register()
    }

    static func register() async {
        guard Backend.isConfigured, let current, Auth.auth().currentUser != nil else { return }
        let callable = Backend.functions.httpsCallable("registerDevice", requestAs: Device.self, responseAs: Empty.self)
        _ = try? await callable(Device(token: current, environment: environment))
    }

    /// Before signing out, so the next person on this phone doesn't get the previous one's notifications.
    static func unregister() async {
        guard Backend.isConfigured, let current, Auth.auth().currentUser != nil else { return }
        let callable = Backend.functions.httpsCallable("unregisterDevice", requestAs: Device.self, responseAs: Empty.self)
        _ = try? await callable(Device(token: current, environment: nil))
    }
}
