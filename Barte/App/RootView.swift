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
                    Label("Supabase fehlt noch", systemImage: "gearshape.2")
                } description: {
                    Text("Kopiere Config.example.xcconfig nach Config.xcconfig, trage Host und Anon Key deines Supabase-Projekts ein und baue die App neu.")
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
