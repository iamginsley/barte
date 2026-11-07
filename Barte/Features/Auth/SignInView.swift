import AuthenticationServices
import SwiftUI

/// The one screen before the cards: what Barte does and "Sign in with Apple".
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SignInViewModel?
    @State private var split: CGFloat = 0

    private static let privacyURL = URL(string: "https://iamginsley.github.io/barte/datenschutz")!

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            hero
            Spacer(minLength: 32)
            points
            Spacer(minLength: 32)
            if let model { signIn(model) }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface.ignoresSafeArea())
        .onAppear {
            if model == nil { model = SignInViewModel(session: app.api?.session) }
            // The card halves slide apart once, like the icon.
            withAnimation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.45).delay(0.15)) { split = 1 }
        }
    }

    private var hero: some View {
        VStack(spacing: 20) {
            BarteLogo(size: 120, split: split)
                .shadow(color: .cardIndigo.opacity(0.3), radius: 24, y: 12)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Barte")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Ausgaben teilen, ohne Rechnerei.")
                    .font(.title3)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 16) {
            point("rectangle.stack.fill", "Eine Karte pro Urlaub, WG oder Pizza-Abend.")
            point("person.2.fill", "Lade Freund:innen per Link ein, dann tragen alle selbst ein.")
            point("arrow.left.arrow.right", "Barte findet die wenigsten Überweisungen, mit denen ihr quitt seid.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signIn(_ model: SignInViewModel) -> some View {
        VStack(spacing: 14) {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if app.isDemo {
                Button {
                    app.signInDemo()
                } label: {
                    Label("Mit Apple anmelden", systemImage: "apple.logo")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(colorScheme == .dark ? .white : .black)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    model.prepare(request)
                } onCompletion: { result in
                    Task { await model.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .clipShape(.capsule)
                .disabled(model.isWorking)
                .overlay {
                    if model.isWorking { ProgressView().tint(colorScheme == .dark ? .black : .white) }
                }
            }

            Text("Kostenlos und ohne Werbung. [Datenschutz](\(Self.privacyURL.absoluteString))")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
