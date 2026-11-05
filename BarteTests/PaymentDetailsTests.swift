import Foundation
import Testing
@testable import Barte

@Suite("Payment details")
struct PaymentDetailsTests {
    @Test(arguments: [
        ("annahuber", "annahuber"),
        ("paypal.me/AnnaHuber", "AnnaHuber"),
        ("https://www.paypal.me/annahuber/", "annahuber"),
        ("  @anna2 ", "anna2"),
        ("https://paypal.me/anna/10EUR", "anna"),
    ])
    func normalizesPayPal(input: String, name: String) {
        #expect(PayPalMe.normalize(input) == .success(name))
    }

    @Test func rejectsBadPayPalNames() {
        #expect(PayPalMe.normalize("") == nil)
        #expect(PayPalMe.normalize("anna huber") == .failure(PayPalMe.Invalid()))
        #expect(PayPalMe.normalize("anna.huber") == .failure(PayPalMe.Invalid()))
        #expect(PayPalMe.normalize(String(repeating: "a", count: 21)) == .failure(PayPalMe.Invalid()))
    }

    @Test func paypalLinkCarriesTheAmount() {
        let details = PaymentDetails(paypal: "annahuber")
        #expect(details.paypalURL(amountCents: 1250, currency: "EUR")?.absoluteString == "https://paypal.me/annahuber/12.50EUR")
        #expect(details.paypalURL(amountCents: 5, currency: "CHF")?.absoluteString == "https://paypal.me/annahuber/0.05CHF")
        #expect(PaymentDetails(iban: "DE89370400440532013000").paypalURL(amountCents: 100, currency: "EUR") == nil)
    }

    @Test(arguments: ["DE89370400440532013000", "AT611904300234573201", "CH9300762011623852957", "GB29NWBK60161331926819"])
    func acceptsValidIBANs(iban: String) {
        #expect(IBAN.isValid(iban))
    }

    @Test(arguments: ["DE89370400440532013001", "DE8937040044", "de89370400440532013000", "1289370400440532013000"])
    func rejectsInvalidIBANs(iban: String) {
        #expect(!IBAN.isValid(iban))
    }

    @Test func formatsIBANs() {
        #expect(IBAN.compact(" de89 3704-0044 0532 0130 00 ") == "DE89370400440532013000")
        #expect(IBAN.compact("  ") == nil)
        #expect(IBAN.formatted("DE89370400440532013000") == "DE89 3704 0044 0532 0130 00")
    }

    @Test @MainActor func formOnlySavesValidChanges() {
        let model = PaymentDetailsModel(details: nil, suggestedHolder: "Dominik")
        #expect(!model.canSave)
        model.ibanText = "DE89 3704 0044 0532 0130 01"
        #expect(model.ibanError != nil)
        #expect(!model.canSave)
        model.ibanText = "DE89 3704 0044 0532 0130 00"
        #expect(model.ibanError == nil)
        #expect(model.details == PaymentDetails(iban: "DE89370400440532013000", accountHolder: "Dominik"))
        model.paypalText = "paypal.me/dominik"
        #expect(model.details?.paypal == "dominik")
        #expect(model.canSave)
    }
}
