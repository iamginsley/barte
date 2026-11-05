import Foundation
import Observation

/// Form state for my PayPal.me name and bank account.
@Observable
@MainActor
final class PaymentDetailsModel {
    let original: PaymentDetails
    var paypalText: String
    var ibanText: String
    var holderText: String

    init(details: PaymentDetails?, suggestedHolder: String) {
        original = details ?? PaymentDetails()
        paypalText = details?.paypal ?? ""
        ibanText = details?.iban.map(IBAN.formatted) ?? ""
        holderText = details?.accountHolder ?? (details?.iban == nil ? suggestedHolder : "")
    }

    var paypal: Result<String, PayPalMe.Invalid>? { PayPalMe.normalize(paypalText) }

    var iban: String? { IBAN.compact(ibanText) }

    var paypalError: String? {
        if case .failure = paypal { return "Nur Buchstaben und Zahlen, so wie hinter paypal.me/." }
        return nil
    }

    var ibanError: String? {
        guard let iban, iban.count >= 15 else { return nil }
        return IBAN.isValid(iban) ? nil : "Diese IBAN stimmt nicht. Prüf sie noch einmal."
    }

    /// While someone is still typing a short IBAN, don't shout; only block saving.
    var ibanIsComplete: Bool { iban.map(IBAN.isValid) ?? true }

    var details: PaymentDetails? {
        guard paypalError == nil, ibanIsComplete else { return nil }
        let holder = holderText.trimmingCharacters(in: .whitespacesAndNewlines)
        return PaymentDetails(
            paypal: try? paypal?.get(),
            iban: iban,
            accountHolder: iban == nil || holder.isEmpty ? nil : holder
        )
    }

    var canSave: Bool { details.map { $0 != original } ?? false }

    /// A preview link so people can check the PayPal name before saving.
    var paypalPreviewURL: URL? {
        guard case .success(let name) = paypal else { return nil }
        return URL(string: "https://paypal.me/\(name)")
    }
}
