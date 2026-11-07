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
            case .signedOut:
                SignInView()
            case .ready:
                GroupsView()
            }
        }
        .animation(.smooth, value: model.phase)
    }
}
