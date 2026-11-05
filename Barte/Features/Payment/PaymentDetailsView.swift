import SwiftUI

/// Where I want to get money: PayPal.me and/or IBAN. Shown to the others when they settle up with me.
struct PaymentDetailsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PaymentDetailsModel
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case paypal, iban, holder }

    init(details: PaymentDetails?) {
        _model = State(initialValue: PaymentDetailsModel(details: details, suggestedHolder: Preferences.myName))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                HStack(spacing: 0) {
                    Text("paypal.me/")
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityHidden(true)
                    TextField("deinname", text: $model.paypalText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.username)
                        .focused($focus, equals: .paypal)
                        .submitLabel(.next)
                        .onSubmit { focus = .iban }
                        .accessibilityLabel("PayPal.me-Name")
                }
                .frame(minHeight: Theme.minTapSize)
                if let url = model.paypalPreviewURL {
                    Link(destination: url) {
                        Label("Link prüfen", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("PayPal")
            } footer: {
                if let error = model.paypalError {
                    Text(error).foregroundStyle(Color.negative)
                } else {
                    Text("Wer dir etwas schuldet, öffnet PayPal mit dem Betrag schon eingetragen.")
                }
            }

            Section {
                TextField("IBAN", text: $model.ibanText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .focused($focus, equals: .iban)
                    .submitLabel(.next)
                    .onSubmit { focus = .holder }
                    .frame(minHeight: Theme.minTapSize)
                TextField("Kontoinhaber:in", text: $model.holderText)
                    .textContentType(.name)
                    .focused($focus, equals: .holder)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .frame(minHeight: Theme.minTapSize)
            } header: {
                Text("Überweisung")
            } footer: {
                if let error = model.ibanError {
                    Text(error).foregroundStyle(Color.negative)
                } else {
                    Text("Der Name muss zum Konto passen, sonst warnt die Bank bei der Überweisung.")
                }
            }

            Section {
                Label("Sehen nur Personen, mit denen du in einer Gruppe bist. Barte zeigt die Daten beim Ausgleichen, wenn dir jemand Geld schuldet.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .navigationTitle("Zahlungsdaten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Sichern", role: .confirm) { Task { await save() } }
                        .disabled(!model.canSave)
                }
            }
        }
        .alert("Nicht gesichert", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let details = model.details else { return }
        focus = nil
        isSaving = true
        defer { isSaving = false }
        if let message = await app.run({ try await $0.savePaymentDetails(details) }) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

/// The same form as a sheet, for the hint in "Ausgleichen".
struct PaymentDetailsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaymentDetailsView(details: app.myPayment)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", role: .cancel) { dismiss() }
                    }
                }
        }
    }
}
