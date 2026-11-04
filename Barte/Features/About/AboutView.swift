import SwiftUI

/// About Barte: my name, how the math works, privacy and contact.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var myName = Preferences.myName
    @State private var split: CGFloat = 1
    @State private var taps = 0
    @State private var confirmsSignOut = false
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @Environment(AppModel.self) private var app

    private static let privacyURL = URL(string: "https://iamginsley.github.io/barte/datenschutz")!
    private static let contactURL = URL(string: "mailto:dominik.gintsberger@outlook.de?subject=Barte")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        BarteLogo(size: 96, split: split)
                            .onTapGesture(perform: tapLogo)
                            .accessibilityAddTraits(.isButton)
                        Text("Barte")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text(taps >= 7 ? "Bar + Karte = Barte. Jetzt aber zurück zum Ausgleichen!" : "Ausgaben teilen, ohne Rechnerei.")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Dein Name", text: $myName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onChange(of: myName) { Preferences.myName = myName }
                } header: {
                    Text("Dein Name")
                } footer: {
                    Text("Wird bei neuen Gruppen und beim Beitreten vorgeschlagen.")
                }

                Section("So rechnet Barte") {
                    explanation("1", "Jede Ausgabe wird gleichmäßig auf die ausgewählten Personen verteilt, auf den Cent genau.")
                    explanation("2", "Daraus ergibt sich für alle ein Saldo: Wer mehr bezahlt hat, bekommt Geld, wer weniger bezahlt hat, schuldet.")
                    explanation("3", "Barte sucht dann die wenigsten Überweisungen, mit denen alle quitt sind. Statt dass jede:r jeder:m etwas zahlt, reichen oft ein, zwei Überweisungen.")
                }

                Section {
                    Button("Abmelden") { confirmsSignOut = true }
                        .frame(minHeight: Theme.minTapSize)
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        HStack {
                            Text("Konto löschen")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .frame(minHeight: Theme.minTapSize)
                    }
                    .disabled(isDeleting)
                } header: {
                    Text("Konto")
                } footer: {
                    Text("Angemeldet mit deiner Apple-ID.")
                }

                Section {
                    Link(destination: Self.privacyURL) {
                        Label("Datenschutz", systemImage: "hand.raised.fill")
                    }
                    Link(destination: Self.contactURL) {
                        Label("Feedback senden", systemImage: "envelope.fill")
                    }
                } footer: {
                    Text("Barte ist kostenlos und ohne Werbung. Deine Gruppen sehen nur die Personen, die du einlädst.\n\nVersion \(Self.version)")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .confirmationDialog("Abmelden?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) {
                    dismiss()
                    Task { await app.signOut() }
                }
            } message: {
                Text("Deine Gruppen bleiben erhalten. Melde dich wieder mit deiner Apple-ID an, um sie zu sehen.")
            }
            .confirmationDialog("Konto endgültig löschen?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Konto löschen", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("Du bestätigst gleich mit deiner Apple-ID. Danach wird dein Konto sofort gelöscht und Barte von deiner Apple-ID getrennt. Gruppen, in denen sonst niemand Barte nutzt, werden mitgelöscht. In geteilten Gruppen bleibt dein Name bei den Ausgaben stehen. Das lässt sich nicht rückgängig machen.")
            }
            .alert("Konto nicht gelöscht", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .navigationTitle("Über Barte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", role: .close) { dismiss() }
                }
            }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await app.deleteAccount()
            dismiss()
        } catch AppleReauthentication.Failure.canceled {
            return
        } catch {
            errorMessage = BarteError.from(error).errorDescription
        }
    }

    private func explanation(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    /// Easter egg: the halves snap together and apart; after a few taps the name explains itself.
    private func tapLogo() {
        taps += 1
        guard !reduceMotion else { return }
        withAnimation(.spring(duration: 0.18)) { split = 0 }
        withAnimation(.spring(duration: 0.5, bounce: 0.6).delay(0.18)) { split = taps % 7 == 0 ? 3 : 1 }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
