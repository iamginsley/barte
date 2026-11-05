import SwiftUI
import UserNotifications

/// Shows whether notifications are on and offers the one step that makes sense from here.
struct NotificationSettingsRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Group {
            switch status {
            case .notDetermined:
                Button {
                    Task {
                        await Notifications.requestAuthorization()
                        await refresh()
                    }
                } label: {
                    Label("Mitteilungen erlauben", systemImage: "bell")
                }
            case .denied:
                Button {
                    openSettings()
                } label: {
                    Label("Mitteilungen in Einstellungen erlauben", systemImage: "bell.slash")
                }
            case .authorized, .provisional, .ephemeral:
                LabeledContent {
                    Button("Anpassen") { openSettings() }
                } label: {
                    Label("Mitteilungen sind an", systemImage: "bell.badge")
                }
            default:
                ProgressView()
            }
        }
        .task { await refresh() }
        // Coming back from the Settings app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        status = await Notifications.authorizationStatus()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
