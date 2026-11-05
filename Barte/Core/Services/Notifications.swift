import Supabase
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

    static func update(_ data: Data, client: SupabaseClient?) async {
        current = data.map { String(format: "%02x", $0) }.joined()
        await register(client: client)
    }

    static func register(client: SupabaseClient?) async {
        guard let client, let current, client.auth.currentUser != nil else { return }
        _ = try? await client.rpc("register_device", params: ["p_token": current, "p_environment": environment]).execute()
    }

    /// Before signing out, so the next person on this phone doesn't get the previous one's notifications.
    static func unregister(client: SupabaseClient?) async {
        guard let client, let current else { return }
        _ = try? await client.rpc("unregister_device", params: ["p_token": current]).execute()
    }
}

/// Tells the others in a group about a new expense or payback through the notify-group Edge Function.
/// Fire and forget: a missing push never blocks or fails the change itself.
struct GroupNotifier: Sendable {
    enum Kind: String, Sendable {
        case expenseAdded = "expense_added"
        case settlementAdded = "settlement_added"
    }

    let client: SupabaseClient

    func send(_ kind: Kind, expenseID: UUID) {
        let client = client
        Task.detached {
            _ = try? await client.functions.invoke("notify-group", options: .init(body: [
                "kind": kind.rawValue,
                "id": expenseID.uuidString.lowercased(),
            ]))
        }
    }
}
