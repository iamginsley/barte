import SwiftUI

@main
struct BarteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.model)
                .onOpenURL { appDelegate.model.open($0) }
                .onAppear { appDelegate.model.start() }
        }
    }
}
