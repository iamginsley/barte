import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surface)
            case .notConfigured:
                ContentUnavailableView {
                    Label("Firebase fehlt noch", systemImage: "gearshape.2")
                } description: {
                    Text("Lade GoogleService-Info.plist aus der Firebase-Konsole, leg sie nach Barte/Resources, führ xcodegen generate aus und bau die App neu.")
                }
                .background(Color.surface)
            case .signedOut:
                SignInView()
            case .ready:
                GroupsView()
            }
        }
        .animation(.smooth, value: model.phase)
    }
}
