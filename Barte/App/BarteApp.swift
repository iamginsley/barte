import SwiftUI

@main
struct BarteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let isDemo = DemoData.isEnabled
        if isDemo { Identity.useDemoDefaults() }
        let persistence = Persistence(inMemory: isDemo)
        if isDemo {
            DemoData.seed(into: GroupRepository(persistence: persistence))
        } else {
            persistence.initializeCloudKitSchemaIfRequested()
        }
        AppDelegate.persistence = persistence
        _model = State(initialValue: AppModel(persistence: persistence, isDemo: isDemo))
    }

    var body: some Scene {
        WindowGroup {
            GroupsView()
                .environment(model)
        }
    }
}
