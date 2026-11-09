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

    /// The language the app shows (de or en) and the phone's region as a BCP 47 tag, e.g. "en-GB".
    /// The server writes pushes in that language and formats amounts like the phone does.
    static var language: String {
        tag(language: Bundle.main.preferredLocalizations.first, region: Locale.current.region?.identifier)
    }

    static func tag(language: String?, region: String?) -> String {
        let language = language?.split(separator: "-").first.map(String.init) ?? "de"
        guard let region, !region.isEmpty else { return language }
        return "\(language)-\(region)"
    }

    static func update(_ data: Data, api: NhostAPI?) async {
        current = data.map { String(format: "%02x", $0) }.joined()
        await register(api: api)
    }

    static func register(api: NhostAPI?) async {
        guard let api, let current, await api.session.userID != nil else { return }
        _ = try? await api.call("register_device", [
            "p_token": .string(current), "p_environment": .string(environment), "p_language": .string(language),
        ])
    }

    /// Before signing out, so the next person on this phone doesn't get the previous one's notifications.
    static func unregister(api: NhostAPI?) async {
        guard let api, let current else { return }
        _ = try? await api.call("unregister_device", ["p_token": .string(current)])
    }
}
