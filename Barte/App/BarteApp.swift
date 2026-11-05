import SwiftUI

@main
struct BarteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.open($0) }
                .onAppear { model.start() }
        }
    }
}
